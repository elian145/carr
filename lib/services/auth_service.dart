import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'api_service.dart';
import 'push_notification_service.dart';
import 'websocket_service.dart';

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

  static Map<String, dynamic> profileFromResponse(Map<String, dynamic> response) {
    return userMapFrom(response['user']) ??
        Map<String, dynamic>.from(response);
  }

  bool _isAuthenticated = false;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = false;
  Future<void>? _initFuture;

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
    } catch (e) {
      developer.log('Auth initialization error: $e', name: 'AuthService');
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

  // Load user profile
  Future<void> _loadUserProfile() async {
    final tokenAtStart = ApiService.accessToken;
    if (tokenAtStart == null || tokenAtStart.isEmpty) return;

    try {
      final response = await ApiService.getProfile();
      if (ApiService.accessToken != tokenAtStart) {
        return;
      }
      _currentUser = profileFromResponse(response);
      _isAuthenticated = true;
      notifyListeners();
    } catch (e) {
      developer.log('Load profile error: $e', name: 'AuthService');
      if (ApiService.accessToken != tokenAtStart) {
        return;
      }
      await _clearAuthState();
    }
  }

  // Start email-based registration (no account yet – user must confirm via email link)
  Future<void> registerEmailWithVerification({
    String? username,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
    bool isDealer = false,
    String? dealershipName,
    String? dealershipPhone,
    String? dealershipLocation,
  }) async {
    _setLoading(true);
    try {
      await ApiService.registerEmailRequest(
        username: username?.trim(),
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        isDealer: isDealer,
        dealershipName: dealershipName,
        dealershipPhone: dealershipPhone,
        dealershipLocation: dealershipLocation,
      );
    } finally {
      _setLoading(false);
    }
  }

  // Confirm signup from email link; creates account and logs user in.
  Future<Map<String, dynamic>> confirmSignup(String token) async {
    _setLoading(true);
    try {
      final data = await ApiService.confirmSignup(token);
      if (data['user'] is Map) {
        await activateSession(
          user: userMapFrom(data['user']),
        );
      } else if (ApiService.isAuthenticated) {
        await activateSession();
      }
      return data;
    } finally {
      _setLoading(false);
    }
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
        } catch (e) {
          if (kDebugMode) {
            developer.log('Profile fetch failed: $e', name: 'AuthService');
          }
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

  // Logout user
  Future<void> logout() async {
    _setLoading(true);

    try {
      await ApiService.logout();
      WebSocketService.disconnect();
    } catch (e) {
      developer.log('Logout error: $e', name: 'AuthService');
    } finally {
      await _clearAuthState();
      _setLoading(false);
    }
  }

  // Forgot password (email or phone; SMS when [isPhone] is true)
  Future<Map<String, dynamic>> forgotPassword(
    String value, {
    bool isPhone = false,
  }) async {
    _setLoading(true);

    try {
      final response = await ApiService.forgotPassword(value, isPhone: isPhone);
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

  /// Permanently delete the current user's account. Optionally pass [password] for confirmation.
  /// Clears local auth state and disconnects WebSocket after successful deletion.
  Future<void> deleteAccount({String? password}) async {
    _setLoading(true);
    try {
      await ApiService.deleteAccount(password: password);
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

  Future<Map<String, dynamic>> uploadDealerCoverPicture(dynamic imageFile) async {
    _setLoading(true);
    try {
      final response = await ApiService.uploadDealerCoverPicture(imageFile);
      if (_currentUser != null && response['dealership_cover_picture'] != null) {
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

  // Clear authentication state
  Future<void> _clearAuthState() async {
    _isAuthenticated = false;
    _currentUser = null;
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
  Future<void> adoptTestSession({Map<String, dynamic>? user}) async {
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
    _currentUser = userMapFrom(user) ??
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
