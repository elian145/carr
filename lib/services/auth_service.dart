import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'push_notification_service.dart';
import 'websocket_service.dart';
import '../shared/debug/app_log.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    ApiService.onTokensCleared = onApiTokensCleared;
  }

  /// JSON maps from [ApiService] may be [Map<dynamic, dynamic>]; normalize safely.
  static Map<String, dynamic>? userMapFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
    final id = map['id'];
    if (id != null && id is! String) {
      map['id'] = id.toString();
    }
    return map;
  }

  static Map<String, dynamic> profileFromResponse(
    Map<String, dynamic> response,
  ) {
    return userMapFrom(response['user']) ?? Map<String, dynamic>.from(response);
  }

  bool _isAuthenticated = false;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = false;
  Future<void>? _initFuture;

  // Bounded, self-contained recovery for a transient (non-401)
  // `_loadUserProfile()` failure. Without this, a single transient
  // network/5xx hiccup on `/auth/me` could permanently strand a session in
  // `ApiService.isAuthenticated == true` + `AuthService.isAuthenticated ==
  // false`, which leaves every `AuthGuard`-protected page spinning forever
  // (nothing else ever retries `/auth/me`). See `_scheduleProfileRetry`.
  static const int _maxProfileRetryAttempts = 3;
  static const List<Duration> _defaultProfileRetryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  /// Test-only override for [_profileRetryDelays] so tests can prove the
  /// retry count/guards are correctly bounded without real multi-second
  /// waits. Always `null` in production. Reset by [resetTestSession].
  @visibleForTesting
  static List<Duration>? debugProfileRetryDelaysOverride;

  static List<Duration> get _profileRetryDelays =>
      debugProfileRetryDelaysOverride ?? _defaultProfileRetryDelays;

  int _profileRetryAttempts = 0;
  bool _profileRetryScheduled = false;

  // Single-flight guard for the real, underlying `/auth/me` HTTP request.
  //
  // `Future.timeout()` (used below and inside `ApiService.getProfile`) does
  // NOT cancel the request it wraps: the real HTTP call keeps running in
  // the background even after a caller "gives up" on it. Without this
  // guard, a slow/hanging backend could let the bounded automatic retry
  // (`_scheduleProfileRetry`) fire additional, genuinely overlapping
  // `/auth/me` requests while an earlier one is still in flight — wasted
  // load on an already-struggling backend, though not a security issue
  // (see `_fetchProfileSingleFlight` for why auth state stays safe).
  //
  // This tracks the *raw* fetch (deliberately called with no per-call
  // timeout) so every caller — the initial load and every retry — shares
  // the exact same underlying request instead of starting a new one. Each
  // caller then applies its own timeout bound *on top of* the shared
  // Future in `_loadUserProfile`; wrapping a Future in `.timeout()` never
  // mutates or cancels it, so multiple callers can independently "give up"
  // on the same shared request without affecting each other or starting a
  // second real HTTP call. The slot is cleared only when the real
  // underlying request itself finishes (success or error) — never merely
  // because some caller's own timeout fired early.
  //
  // [_inFlightProfileFetchToken] guards the existing token-identity
  // invariant: a request is only ever shared with a caller whose own
  // token matches the token the in-flight request was actually started
  // for. This prevents a logout/login (or account switch) from adopting a
  // still-pending request that was authenticated as a *different* user —
  // the stale request, if any, is simply left to resolve and clear itself
  // in the background, unobserved, exactly as it already was before this
  // guard existed; a fresh request is started for the new token instead.
  Future<Map<String, dynamic>>? _inFlightProfileFetch;
  String? _inFlightProfileFetchToken;

  Future<Map<String, dynamic>> _fetchProfileSingleFlight(String tokenAtStart) {
    final inFlight = _inFlightProfileFetch;
    if (inFlight != null && _inFlightProfileFetchToken == tokenAtStart) {
      return inFlight;
    }
    final future = ApiService.getProfile();
    _inFlightProfileFetch = future;
    _inFlightProfileFetchToken = tokenAtStart;
    return future.whenComplete(() {
      if (identical(_inFlightProfileFetch, future)) {
        _inFlightProfileFetch = null;
        _inFlightProfileFetchToken = null;
      }
    });
  }

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoading => _isLoading;

  // Initialize authentication state (runs once per app session).
  Future<void> initialize() {
    return _initFuture ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    _setLoading(true);

    try {
      await ApiService.initializeTokens();

      if (ApiService.isAuthenticated) {
        await _loadUserProfile();
        await WebSocketService.connect();
        await PushNotificationService.syncTokenWithBackend();
      }
    } catch (e, st) {
      logNonFatal(e, st, 'AuthService.initialize');
      await _clearAuthState();
    } finally {
      _setLoading(false);
    }
  }

  /// After tokens are saved elsewhere (signup OTP, external auth), adopt the session.
  Future<void> activateSession({Map<String, dynamic>? user}) async {
    if (!ApiService.isAuthenticated) {
      await _clearAuthState();
      return;
    }
    if (user != null) {
      _currentUser = Map<String, dynamic>.from(user);
      _isAuthenticated = true;
    } else {
      await _loadUserProfile();
      if (!ApiService.isAuthenticated) return;
    }
    await WebSocketService.connect();
    await PushNotificationService.syncTokenWithBackend();
    notifyListeners();
  }

  /// Called when [ApiService.clearTokens] drops the HTTP session out-of-band (401 refresh fail).
  void onApiTokensCleared() {
    if (!_isAuthenticated && _currentUser == null) return;
    _isAuthenticated = false;
    _currentUser = null;
    notifyListeners();
  }

  // Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Load user profile.
  //
  // [timeout], when provided, bounds this specific attempt instead of the
  // normal adaptive (warm/cold-start) timeout — used only by the automatic
  // retry path (see `_scheduleProfileRetry`) so a retry fails fast rather
  // than potentially inheriting the much longer cold-start budget. The
  // initial load (app init, login, activateSession, refreshProfile, ...)
  // never passes this, so it keeps the existing adaptive-timeout behavior.
  Future<void> _loadUserProfile({Duration? timeout}) async {
    final tokenAtStart = ApiService.accessToken;
    if (tokenAtStart == null || tokenAtStart.isEmpty) return;

    try {
      // Reuse a still-pending real request instead of starting a second,
      // overlapping one (see `_fetchProfileSingleFlight`). The per-call
      // [timeout] is applied locally on top of the shared Future, so it
      // only bounds *this* caller's wait — it never cancels the shared
      // request or affects any other caller awaiting the same Future.
      final sharedFetch = _fetchProfileSingleFlight(tokenAtStart);
      final response = timeout == null
          ? await sharedFetch
          : await sharedFetch.timeout(timeout);
      if (ApiService.accessToken != tokenAtStart) {
        return;
      }
      _currentUser = profileFromResponse(response);
      _isAuthenticated = true;
      _profileRetryAttempts = 0;
      notifyListeners();
    } catch (e, st) {
      logNonFatal(e, st, 'AuthService._loadUserProfile');
      if (ApiService.accessToken != tokenAtStart) {
        return;
      }
      // 401s already clear tokens (and this session) via onApiTokensCleared,
      // triggered from inside ApiService. A transient network/5xx failure here
      // must not log the user out — the token is still valid, so keep the
      // existing session and let a bounded retry (or the next successful
      // call) repopulate it, instead of permanently stranding
      // ApiService.isAuthenticated == true / AuthService.isAuthenticated ==
      // false.
      if (e is ApiException && e.statusCode == 401) {
        await _clearAuthState();
      } else {
        _scheduleProfileRetry(tokenAtStart);
      }
    }
  }

  /// Bounded, self-contained recovery for a transient `_loadUserProfile()`
  /// failure (non-401: network error, timeout, 5xx, etc.).
  ///
  /// Re-runs the exact same authenticated `/auth/me` fetch used everywhere
  /// else in this class — it never marks the session authenticated without
  /// a successful profile response, and a genuine 401 encountered on retry
  /// still clears auth state via the normal path above. Callers (e.g.
  /// `AuthGuard`) never need to know this exists: on success,
  /// `_loadUserProfile()` already calls `notifyListeners()`, which is
  /// exactly what un-sticks a `Provider.of<AuthService>(context)` gate.
  ///
  /// - Bounded: at most [_maxProfileRetryAttempts] attempts per failure
  ///   streak (reset to 0 on any successful load or auth-state clear).
  /// - No retry storm: only one retry ever in flight at a time
  ///   (`_profileRetryScheduled`), with short, spaced-out delays.
  /// - Non-blocking: fire-and-forget — never awaited by `_loadUserProfile()`
  ///   or its callers, so it can never block app initialization, login, or
  ///   any UI interaction.
  void _scheduleProfileRetry(String tokenAtFailureTime) {
    if (_profileRetryScheduled) return;
    if (_profileRetryAttempts >= _maxProfileRetryAttempts) return;
    final delay = _profileRetryDelays[_profileRetryAttempts.clamp(
      0,
      _profileRetryDelays.length - 1,
    )];
    _profileRetryAttempts++;
    _profileRetryScheduled = true;
    Future.delayed(delay, () async {
      _profileRetryScheduled = false;
      // Already resolved (recovered via another call, logged out, or
      // switched accounts) by the time this fires — nothing to do.
      if (_isAuthenticated) return;
      if (!ApiService.isAuthenticated) return;
      if (ApiService.accessToken != tokenAtFailureTime) return;
      // Bounded warm-path timeout, not the adaptive one: on a cold-start
      // backend every attempt would otherwise reuse ApiService's ~55s
      // cold-start budget, so 3 retries could cost minutes instead of
      // seconds before this class gives up.
      await _loadUserProfile(timeout: ApiService.warmRequestTimeout);
    });
  }

  // Login user
  Future<Map<String, dynamic>> login(
    String emailOrPhone,
    String password,
  ) async {
    await initialize();
    _setLoading(true);

    try {
      final response = await ApiService.login(emailOrPhone, password);
      final userFromLogin = userMapFrom(response['user']);
      if (userFromLogin != null) {
        _currentUser = userFromLogin;
      } else {
        try {
          final me = await ApiService.getProfile();
          _currentUser = profileFromResponse(me);
        } catch (e, st) {
          logNonFatal(e, st, 'AuthService.login.profileFetch');
        }
      }
      _isAuthenticated = true;

      // Connect to WebSocket
      await WebSocketService.connect();
      await PushNotificationService.syncTokenWithBackend();

      notifyListeners();
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  static bool isDealerAccount(Map<String, dynamic>? user) {
    if (user == null) return false;
    final accountType = (user['account_type'] ?? 'user')
        .toString()
        .trim()
        .toLowerCase();
    final rawApplication = user['dealer_application'];
    final applicationStatus = rawApplication is Map
        ? rawApplication['status']
        : null;
    final dealerStatus =
        (user['dealer_application_status'] ??
                applicationStatus ??
                user['dealer_status'] ??
                'none')
            .toString()
            .trim()
            .toLowerCase();
    if (accountType == 'dealer') return true;
    if (dealerStatus == 'pending' ||
        dealerStatus == 'draft' ||
        dealerStatus == 'submitted' ||
        dealerStatus == 'under_review' ||
        dealerStatus == 'needs_changes' ||
        dealerStatus == 'approved' ||
        dealerStatus == 'rejected') {
      return true;
    }
    return false;
  }

  /// Send a one-time code to [phoneNumber] for passwordless login or signup.
  Future<Map<String, dynamic>> sendPhoneLoginCode(
    String phoneNumber, {
    bool createIfMissing = true,
    String? purpose,
    bool isDealer = false,
    String? dealershipName,
    String? dealershipPhone,
    String? dealershipLocation,
  }) async {
    return ApiService.phoneStart(
      phoneNumber: phoneNumber,
      createIfMissing: createIfMissing,
      purpose: purpose,
      isDealer: isDealer,
      dealershipName: dealershipName,
      dealershipPhone: dealershipPhone,
      dealershipLocation: dealershipLocation,
    );
  }

  /// Verify the phone OTP and sign in, creating an account when the number is new.
  Future<Map<String, dynamic>> loginWithPhoneOtp(
    String phoneNumber,
    String code, {
    String? purpose,
    bool isDealer = false,
    String? dealershipName,
    String? dealershipPhone,
    String? dealershipLocation,
  }) async {
    await initialize();
    _setLoading(true);

    try {
      final response = await ApiService.phoneVerify(
        phoneNumber: phoneNumber,
        code: code,
        createIfMissing: true,
        purpose: purpose,
        isDealer: isDealer,
        dealershipName: dealershipName,
        dealershipPhone: dealershipPhone,
        dealershipLocation: dealershipLocation,
      );
      final userFromVerify = userMapFrom(response['user']);
      await activateSession(user: userFromVerify);
      return response;
    } finally {
      _setLoading(false);
    }
  }

  // Logout user
  Future<void> logout() async {
    _setLoading(true);

    try {
      await ApiService.logout();
      WebSocketService.disconnect();
    } catch (e, st) {
      logNonFatal(e, st, 'AuthService.logout');
    } finally {
      await _clearAuthState();
      _setLoading(false);
    }
  }

  // Forgot password (SMS only)
  Future<Map<String, dynamic>> forgotPassword(
    String value, {
    bool isPhone = true,
  }) async {
    _setLoading(true);

    try {
      final response = await ApiService.forgotPassword(value, isPhone: true);
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Reset password (with token from forgot-password flow)
  Future<Map<String, dynamic>> resetPassword(
    String token,
    String newPassword,
  ) async {
    _setLoading(true);

    try {
      final response = await ApiService.resetPassword(token, newPassword);
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Change password (authenticated user: current + new password)
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _setLoading(true);
    try {
      final response = await ApiService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Sends an SMS confirmation code for account deletion.
  Future<Map<String, dynamic>> sendDeleteAccountCode() {
    return ApiService.sendDeleteAccountCode();
  }

  /// Permanently delete the current user's account, confirmed by an SMS [code]
  /// or a [password] for accounts that have one.
  /// Clears local auth state and disconnects WebSocket after successful deletion.
  Future<void> deleteAccount({String? password, String? code}) async {
    _setLoading(true);
    try {
      await ApiService.deleteAccount(password: password, code: code);
      WebSocketService.disconnect();
      await _clearAuthState();
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Verify email (with token from verification email link or manual entry)
  Future<Map<String, dynamic>> verifyEmail(String token) async {
    _setLoading(true);
    try {
      final response = await ApiService.verifyEmail(token);
      if (ApiService.isAuthenticated) {
        await _loadUserProfile();
      }
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Send verification email to current user (authenticated)
  Future<Map<String, dynamic>> sendEmailVerification() async {
    _setLoading(true);
    try {
      final response = await ApiService.sendEmailVerification();
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Update profile
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profileData,
  ) async {
    _setLoading(true);

    try {
      final response = await ApiService.updateProfile(profileData);

      // Update current user data
      final user = userMapFrom(response['user']);
      if (user != null) {
        _currentUser = user;
        notifyListeners();
      }

      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Sends an ownership code to [email] before it can become the account's
  /// personal login/contact email (S7: the profile-update endpoint refuses
  /// to accept a new email without this proof).
  Future<Map<String, dynamic>> sendAccountEmailChangeCode(String email) {
    return ApiService.sendAccountEmailChangeCode(email);
  }

  Future<Map<String, dynamic>> verifyAccountEmailChange(
    String email,
    String code,
  ) async {
    final response = await ApiService.verifyAccountEmailChange(email, code);
    if (_currentUser != null) {
      _currentUser!['email'] = email;
      _currentUser!['email_verified'] = true;
      notifyListeners();
    }
    return response;
  }

  Future<Map<String, dynamic>> updateDealerProfile(
    Map<String, dynamic> dealerData,
  ) async {
    _setLoading(true);
    try {
      final response = await ApiService.updateDealerProfile(dealerData);
      final user = userMapFrom(response['user']);
      if (user != null) {
        _currentUser = user;
        notifyListeners();
      }
      return response;
    } finally {
      _setLoading(false);
    }
  }

  Future<Map<String, dynamic>> saveDealerApplication(
    Map<String, dynamic> applicationData,
  ) async {
    _setLoading(true);
    try {
      final response = await ApiService.saveDealerApplication(applicationData);
      final user = userMapFrom(response['user']);
      if (user != null) {
        _currentUser = user;
        notifyListeners();
      }
      return response;
    } finally {
      _setLoading(false);
    }
  }

  // Upload profile picture
  Future<Map<String, dynamic>> uploadProfilePicture(dynamic imageFile) async {
    _setLoading(true);

    try {
      final response = await ApiService.uploadProfilePicture(imageFile);

      // Update current user data
      if (_currentUser != null && response['profile_picture'] != null) {
        _currentUser!['profile_picture'] = response['profile_picture'];
        notifyListeners();
      }

      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<Map<String, dynamic>> uploadDealerCoverPicture(
    dynamic imageFile,
  ) async {
    _setLoading(true);
    try {
      final response = await ApiService.uploadDealerCoverPicture(imageFile);
      if (_currentUser != null &&
          response['dealership_cover_picture'] != null) {
        _currentUser!['dealership_cover_picture'] =
            response['dealership_cover_picture'];
        notifyListeners();
      }
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<Map<String, dynamic>> uploadDealerVerificationPhoto(
    dynamic imageFile,
  ) async {
    _setLoading(true);
    try {
      final response = await ApiService.uploadDealerVerificationPhoto(
        imageFile,
      );
      final application = _currentUser?['dealer_application'];
      if (application is Map && response['has_verification_photo'] == true) {
        application['has_verification_photo'] = true;
        notifyListeners();
      }
      return response;
    } finally {
      _setLoading(false);
    }
  }

  // Clear authentication state
  Future<void> _clearAuthState() async {
    _isAuthenticated = false;
    _currentUser = null;
    _profileRetryAttempts = 0;
    // A pending retry timer from the just-cleared session (if any) will
    // still fire harmlessly later (guarded by its own isAuthenticated/token
    // checks), but resetting this now lets a *new* session's own failure
    // schedule its own retry immediately instead of waiting for the old
    // timer to expire first.
    _profileRetryScheduled = false;
    // Stop treating any still-pending request as shareable. It is not
    // cancelled (can't be — see `_fetchProfileSingleFlight`) and keeps
    // running harmlessly in the background, but a future call (even one
    // that happens to reuse the same token, e.g. re-login) will now start
    // a fresh request instead of ever adopting this one's eventual result.
    _inFlightProfileFetch = null;
    _inFlightProfileFetchToken = null;
    await ApiService.clearTokens();
    notifyListeners();
  }

  // Check if user is verified
  bool get isUserVerified => _currentUser?['is_verified'] ?? false;

  Future<void> refreshProfile() async {
    if (!ApiService.isAuthenticated) return;
    await _loadUserProfile();
  }

  /// Test-only: authenticated session without network login.
  @visibleForTesting
  Future<void> adoptTestSession({Map<String, dynamic>? user}) async {
    assert(kDebugMode, 'adoptTestSession is debug-only');
    if (!kDebugMode) return;
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
    _currentUser =
        userMapFrom(user) ??
        userMapFrom({
          'id': 1,
          'username': 'test',
          'is_admin': false,
          'account_type': 'individual',
        });
    _isAuthenticated = true;
    _isLoading = false;
    notifyListeners();
  }

  void resetTestSession() {
    _initFuture = null;
    _isAuthenticated = false;
    _currentUser = null;
    _isLoading = false;
    _profileRetryAttempts = 0;
    _profileRetryScheduled = false;
    _inFlightProfileFetch = null;
    _inFlightProfileFetchToken = null;
    debugProfileRetryDelaysOverride = null;
    notifyListeners();
  }

  // Get user ID
  String? get userId {
    final id = _currentUser?['id'];
    if (id == null) return null;
    return id.toString();
  }

  // Get user name
  String get userName => _currentUser != null
      ? '${_currentUser!['first_name'] ?? ''} ${_currentUser!['last_name'] ?? ''}'
            .trim()
      : '';

  // Get user email
  String? get userEmail => _currentUser?['email'];

  // Get user phone
  String? get userPhone => _currentUser?['phone_number'];

  // Get profile picture
  String? get profilePicture => _currentUser?['profile_picture'];

  // Check if user is admin
  bool get isAdmin => _currentUser?['is_admin'] ?? false;
}
