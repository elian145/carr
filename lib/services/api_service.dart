import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import '../shared/auth/token_store.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? body;

  ApiException({
    required this.statusCode,
    required this.message,
    this.body,
  });

  @override
  String toString() => message;
}

class ApiService {
  /// 60s to allow Render (and similar PaaS) cold starts on first request.
  static const Duration _defaultTimeout = Duration(seconds: 60);
  static const Duration _uploadTimeout = Duration(seconds: 180);

  static String get baseUrl {
    return apiBaseApi();
  }

  static String? _accessToken;
  static String? _refreshToken;

  // Initialize tokens from storage
  static Future<void> initializeTokens() async {
    await TokenStore.load();
    _accessToken = TokenStore.token;
    _refreshToken = TokenStore.refreshToken;
  }

  // Save tokens to storage
  static Future<void> _saveAccessToken(String accessToken) async {
    await TokenStore.save(accessToken);
    _accessToken = TokenStore.token;
  }

  static Future<void> _saveRefreshToken(String? refreshToken) async {
    await TokenStore.saveRefresh(refreshToken);
    _refreshToken = TokenStore.refreshToken;
  }

  /// Set the current access token (best-effort persisted).
  /// Use this when the app obtains a token outside of [ApiService.login],
  /// e.g. after signup or external auth.
  static Future<void> setAccessToken(String? token) async {
    final t = (token ?? '').trim();
    if (t.isEmpty) {
      await clearTokens();
      return;
    }
    await _saveAccessToken(t);
  }

  /// Set the current refresh token (best-effort persisted).
  static Future<void> setRefreshToken(String? token) async {
    final t = (token ?? '').trim();
    if (t.isEmpty) {
      await _saveRefreshToken(null);
      return;
    }
    await _saveRefreshToken(t);
  }

  /// Set both access and refresh tokens (best-effort persisted).
  static Future<void> setTokens({String? accessToken, String? refreshToken}) async {
    await setAccessToken(accessToken);
    await setRefreshToken(refreshToken);
  }

  // Clear tokens
  static Future<void> clearTokens() async {
    await TokenStore.clear();
    _accessToken = null;
    _refreshToken = null;
  }

  // Get headers with authorization
  static Map<String, String> _getHeaders({bool includeAuth = true}) {
    Map<String, String> headers = {'Content-Type': 'application/json'};

    if (includeAuth && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }

    return headers;
  }

  // Handle API response
  static Map<String, dynamic> _handleResponse(http.Response response) {
    final int code = response.statusCode;
    final String body = response.body;
    if (code >= 200 && code < 300) {
      return body.isNotEmpty ? json.decode(body) : <String, dynamic>{};
    }
    try {
      final Map<String, dynamic> err = body.isNotEmpty
          ? json.decode(body)
          : <String, dynamic>{};
      final msg = (err['message'] ?? err['error'] ?? '').toString().trim();
      throw ApiException(
        statusCode: code,
        message: msg.isNotEmpty ? msg : 'API request failed ($code)',
        body: err,
      );
    } catch (_) {
      throw ApiException(statusCode: code, message: 'API request failed ($code)');
    }
  }

  // Refresh access token
  static Future<bool> _refreshAccessToken() async {
    final rt = (_refreshToken ?? '').trim();
    if (rt.isEmpty) return false;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $rt',
            },
          )
          .timeout(_defaultTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = response.body.isNotEmpty
            ? json.decode(response.body)
            : <String, dynamic>{};
        final String? access = (data['access_token'] as String?)?.trim();
        final String? refresh = (data['refresh_token'] as String?)?.trim();
        if (access != null && access.isNotEmpty) {
          await _saveAccessToken(access);
          if (refresh != null && refresh.isNotEmpty) {
            await _saveRefreshToken(refresh);
          }
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  // Make authenticated request with automatic token refresh
  static Future<Map<String, dynamic>> _makeAuthenticatedRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final requestHeaders = {..._getHeaders(), ...?headers};

    http.Response response;

    switch (method.toUpperCase()) {
      case 'GET':
        response = await http
            .get(url, headers: requestHeaders)
            .timeout(_defaultTimeout);
        break;
      case 'POST':
        response = await http
            .post(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            )
            .timeout(_defaultTimeout);
        break;
      case 'PUT':
        response = await http
            .put(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            )
            .timeout(_defaultTimeout);
        break;
      case 'PATCH':
        response = await http
            .patch(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            )
            .timeout(_defaultTimeout);
        break;
      case 'DELETE':
        response = await http
            .delete(url, headers: requestHeaders)
            .timeout(_defaultTimeout);
        break;
      default:
        throw Exception('Unsupported HTTP method: $method');
    }

    // If unauthorized, try to refresh token
    if (response.statusCode == 401) {
      if (await _refreshAccessToken()) {
        // Retry request with new token
        requestHeaders['Authorization'] = 'Bearer $_accessToken';

        switch (method.toUpperCase()) {
          case 'GET':
            response = await http
                .get(url, headers: requestHeaders)
                .timeout(_defaultTimeout);
            break;
          case 'POST':
            response = await http
                .post(
                  url,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null,
                )
                .timeout(_defaultTimeout);
            break;
          case 'PUT':
            response = await http
                .put(
                  url,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null,
                )
                .timeout(_defaultTimeout);
            break;
          case 'PATCH':
            response = await http
                .patch(
                  url,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null,
                )
                .timeout(_defaultTimeout);
            break;
          case 'DELETE':
            response = await http
                .delete(url, headers: requestHeaders)
                .timeout(_defaultTimeout);
            break;
        }
      } else {
        await clearTokens();
        throw Exception('Authentication failed');
      }
    }

    return _handleResponse(response);
  }

  // Authentication methods
  static Future<Map<String, dynamic>> registerEmailRequest({
    required String username,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/register-request'),
          headers: _getHeaders(includeAuth: false),
          body: json.encode({
            'username': username,
            'email': email,
            'password': password,
            'first_name': firstName,
            'last_name': lastName,
            if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
              'phone_number': phoneNumber.trim(),
          }),
        )
        .timeout(_defaultTimeout);

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> confirmSignup(String token) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/register-confirm'),
          headers: _getHeaders(includeAuth: false),
          body: json.encode({'token': token}),
        )
        .timeout(_defaultTimeout);

    final data = _handleResponse(response);
    final String? access = (data['access_token'] as String?)?.trim();
    final String? refresh = (data['refresh_token'] as String?)?.trim();
    if (access != null && access.isNotEmpty) {
      await _saveAccessToken(access);
    }
    if (refresh != null && refresh.isNotEmpty) {
      await _saveRefreshToken(refresh);
    }
    return data;
  }

  static Future<Map<String, dynamic>> login(
    String emailOrPhone,
    String password,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/login'),
          headers: _getHeaders(includeAuth: false),
          body: json.encode({'username': emailOrPhone, 'password': password}),
        )
        .timeout(_defaultTimeout);

    // Accept either legacy {'token': '<jwt>'} or new {'access_token': '...', 'refresh_token': '...'}
    final data = _handleResponse(response);
    final String? legacyToken = (data['token'] as String?)?.trim();
    final String? access = (data['access_token'] as String?)?.trim();
    final String? refresh = (data['refresh_token'] as String?)?.trim();
    final token = (legacyToken != null && legacyToken.isNotEmpty)
        ? legacyToken
        : access;
    if (token != null && token.isNotEmpty) {
      await _saveAccessToken(token);
    }
    if (refresh != null && refresh.isNotEmpty) {
      await _saveRefreshToken(refresh);
    }
    return data;
  }

  // Phone OTP (Option D)
  static Future<Map<String, dynamic>> phoneStart({
    required String phoneNumber,
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    String? password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/phone/start'),
          headers: _getHeaders(includeAuth: false),
          body: json.encode({
            'phone_number': phoneNumber,
            if ((username ?? '').trim().isNotEmpty) 'username': username,
            if ((firstName ?? '').trim().isNotEmpty) 'first_name': firstName,
            if ((lastName ?? '').trim().isNotEmpty) 'last_name': lastName,
            if ((email ?? '').trim().isNotEmpty) 'email': email,
            if ((password ?? '').trim().isNotEmpty) 'password': password,
          }),
        )
        .timeout(_defaultTimeout);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> phoneVerify({
    required String phoneNumber,
    required String code,
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    String? password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/phone/verify'),
          headers: _getHeaders(includeAuth: false),
          body: json.encode({
            'phone_number': phoneNumber,
            'code': code,
            if ((username ?? '').trim().isNotEmpty) 'username': username,
            if ((firstName ?? '').trim().isNotEmpty) 'first_name': firstName,
            if ((lastName ?? '').trim().isNotEmpty) 'last_name': lastName,
            if ((email ?? '').trim().isNotEmpty) 'email': email,
            if ((password ?? '').trim().isNotEmpty) 'password': password,
          }),
        )
        .timeout(_defaultTimeout);

    final data = _handleResponse(response);
    final String? access = (data['access_token'] as String?)?.trim();
    final String? refresh = (data['refresh_token'] as String?)?.trim();
    if (access != null && access.isNotEmpty) {
      await _saveAccessToken(access);
    }
    if (refresh != null && refresh.isNotEmpty) {
      await _saveRefreshToken(refresh);
    }
    return data;
  }

  static Future<void> logout() async {
    // Best-effort server-side revocation; then clear locally.
    try {
      final headers = _getHeaders();
      final rt = (_refreshToken ?? '').trim();
      final body = (rt.isNotEmpty) ? json.encode({'refresh_token': rt}) : null;
      await http
          .post(
            Uri.parse('$baseUrl/auth/logout'),
            headers: headers,
            body: body,
          )
          .timeout(_defaultTimeout);
    } catch (_) {}
    await clearTokens();
  }

  /// Change password (authenticated). Requires current and new password.
  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return await _makeAuthenticatedRequest(
      'POST',
      '/auth/change-password',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  /// Permanently delete the current user's account. Optionally pass [password] for confirmation.
  static Future<Map<String, dynamic>> deleteAccount({String? password}) async {
    final body = <String, dynamic>{};
    if (password != null && password.trim().isNotEmpty) {
      body['password'] = password.trim();
    }
    return await _makeAuthenticatedRequest(
      'POST',
      '/auth/delete-account',
      body: body.isNotEmpty ? body : null,
    );
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/forgot-password'),
          headers: _getHeaders(includeAuth: false),
          // Backwards-compatible: backend historically used phone_number.
          body: json.encode({'email': email, 'phone_number': email}),
        )
        .timeout(_defaultTimeout);

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> resetPassword(
    String token,
    String newPassword,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: _getHeaders(includeAuth: false),
          body: json.encode({'token': token, 'password': newPassword}),
        )
        .timeout(_defaultTimeout);

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> verifyEmail(String token) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/verify-email'),
          headers: _getHeaders(includeAuth: false),
          body: json.encode({'token': token}),
        )
        .timeout(_defaultTimeout);

    return _handleResponse(response);
  }

  /// Request a verification email for the current user (authenticated).
  static Future<Map<String, dynamic>> sendEmailVerification() async {
    return await _makeAuthenticatedRequest('POST', '/auth/send-email-verification');
  }

  /// Send 6-digit SMS code to phone (for verification). Rate-limited.
  static Future<Map<String, dynamic>> sendPhoneVerificationCode(String phoneNumber) async {
    final apiRoot = baseUrl.endsWith('/api') ? baseUrl : '$baseUrl/api';
    final url = '$apiRoot/auth/send-verification';
    final response = await http
        .post(
          Uri.parse(url),
          headers: _getHeaders(includeAuth: false),
          body: json.encode({'phone_number': phoneNumber}),
        )
        .timeout(_defaultTimeout);
    if (response.statusCode == 404) {
      throw ApiException(
        statusCode: 404,
        message: 'Endpoint not found (404). Tried: $url',
        body: <String, dynamic>{'status': 404},
      );
    }
    return _handleResponse(response);
  }

  /// Verify phone with 6-digit code.
  static Future<Map<String, dynamic>> verifyPhone(String phoneNumber, String code) async {
    final apiRoot = baseUrl.endsWith('/api') ? baseUrl : '$baseUrl/api';
    final url = '$apiRoot/auth/verify-phone';
    final response = await http
        .post(
          Uri.parse(url),
          headers: _getHeaders(includeAuth: false),
          body: json.encode({
            'phone_number': phoneNumber,
            'verification_code': code,
          }),
        )
        .timeout(_defaultTimeout);
    if (response.statusCode == 404) {
      throw ApiException(
        statusCode: 404,
        message: 'Endpoint not found (404). Tried: $url',
        body: <String, dynamic>{'status': 404},
      );
    }
    return _handleResponse(response);
  }

  // User profile methods
  static Future<Map<String, dynamic>> getProfile() async {
    return await _makeAuthenticatedRequest('GET', '/auth/me');
  }

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profileData,
  ) async {
    return await _makeAuthenticatedRequest(
      'PUT',
      '/user/profile',
      body: profileData,
    );
  }

  static Future<Map<String, dynamic>> uploadProfilePicture(
    XFile imageFile,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/user/upload-profile-picture'),
    );

    // Add authorization header
    if (_accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    // Add file
    request.files.add(
      await http.MultipartFile.fromPath('file', imageFile.path),
    );

    final response = await request.send().timeout(_uploadTimeout);
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(responseBody);
    } else {
      final error = json.decode(responseBody);
      throw Exception(error['message'] ?? 'Upload failed');
    }
  }

  // Car listing methods
  static Future<Map<String, dynamic>> getCars({
    int page = 1,
    int perPage = 20,
    String? brand,
    String? model,
    int? yearMin,
    int? yearMax,
    double? priceMin,
    double? priceMax,
    String? location,
    String? condition,
    String? bodyType,
    String? transmission,
    String? driveType,
    String? engineType,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };

    if (brand != null) queryParams['brand'] = brand;
    if (model != null) queryParams['model'] = model;
    if (yearMin != null) queryParams['year_min'] = yearMin.toString();
    if (yearMax != null) queryParams['year_max'] = yearMax.toString();
    if (priceMin != null) queryParams['price_min'] = priceMin.toString();
    if (priceMax != null) queryParams['price_max'] = priceMax.toString();
    if (location != null) queryParams['location'] = location;
    if (condition != null) queryParams['condition'] = condition;
    if (bodyType != null) queryParams['body_type'] = bodyType;
    if (transmission != null) queryParams['transmission'] = transmission;
    if (driveType != null) queryParams['drive_type'] = driveType;
    if (engineType != null) queryParams['engine_type'] = engineType;

    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final response = await http
        .get(
          Uri.parse('$baseUrl/cars?$queryString'),
          headers: _getHeaders(includeAuth: false),
        )
        .timeout(_defaultTimeout);

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getCar(String carId) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/cars/$carId'),
          headers: _getHeaders(includeAuth: false),
        )
        .timeout(_defaultTimeout);

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> createCar(
    Map<String, dynamic> carData,
  ) async {
    return await _makeAuthenticatedRequest('POST', '/cars', body: carData);
  }

  static Future<Map<String, dynamic>> updateCar(
    String carId,
    Map<String, dynamic> carData,
  ) async {
    return await _makeAuthenticatedRequest(
      'PUT',
      '/cars/$carId',
      body: carData,
    );
  }

  static Future<Map<String, dynamic>> deleteCar(String carId) async {
    return await _makeAuthenticatedRequest('DELETE', '/cars/$carId');
  }

  static Future<Map<String, dynamic>> uploadCarImages(
    String carId,
    List<XFile> imageFiles, {
    bool blurPlates = false,
  }) async {
    // App-default behavior: do NOT blur unless user explicitly requests it.
    // FORCE_SKIP_BLUR remains a hard override for dev/testing builds.
    final bool skipBlur = forceSkipBlur() || !blurPlates;
    final String query = skipBlur ? '?skip_blur=1' : '';
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/cars/$carId/images$query'),
    );

    // Add authorization header
    if (_accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    // Add files once under 'images' (backend accepts 'files', 'images', 'image', etc. and extends one list — do not send same file under multiple keys or backend gets duplicates)
    for (final file in imageFiles) {
      request.files.add(await http.MultipartFile.fromPath('images', file.path));
    }

    final response = await request.send().timeout(_uploadTimeout);
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Backend compatibility: some endpoints return { uploaded: [...] }
      // Normalize to { images: [...] } expected by UI services
      final Map<String, dynamic> data = json.decode(responseBody);
      if (!data.containsKey('images') && data.containsKey('uploaded')) {
        data['images'] = List.from(data['uploaded'] as List);
      }
      return data;
    } else {
      final error = json.decode(responseBody);
      throw Exception(error['message'] ?? 'Upload failed');
    }
  }

  static Future<Map<String, dynamic>> attachCarImages(
    String carId,
    List<String> paths,
  ) async {
    return await _makeAuthenticatedRequest(
      'POST',
      '/cars/$carId/images/attach',
      body: {'paths': paths},
    );
  }

  /// Request a presigned R2 PUT URL for one image. Returns { upload_url, key, public_url? }.
  static Future<Map<String, dynamic>> signR2ImageUpload({
    String? filename,
    String? contentType,
  }) async {
    final body = <String, dynamic>{};
    if (filename != null && filename.isNotEmpty) body['filename'] = filename;
    if (contentType != null && contentType.isNotEmpty) body['content_type'] = contentType;
    return await _makeAuthenticatedRequest(
      'POST',
      '/media/r2/sign-upload',
      body: body.isNotEmpty ? body : null,
    );
  }

  /// Upload file bytes to a presigned PUT URL (e.g. R2). No auth header.
  static Future<void> uploadToSignedUpload(String uploadUrl, XFile file) async {
    final bytes = await file.readAsBytes();
    final uri = Uri.parse(uploadUrl);
    final response = await http.put(
      uri,
      body: bytes,
      headers: <String, String>{
        'Content-Type': file.mimeType ?? 'image/jpeg',
      },
    ).timeout(_uploadTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: response.body.isNotEmpty ? response.body : 'Upload failed',
      );
    }
  }

  /// Attach image URLs (e.g. R2 public URLs) to a car listing.
  static Future<Map<String, dynamic>> attachCarImageUrls(
    String carId,
    List<String> urls,
  ) async {
    return await _makeAuthenticatedRequest(
      'POST',
      '/cars/$carId/images/attach',
      body: {'urls': urls},
    );
  }

  static List<String>? getLastProcessedServerPaths() {
    // Attach-based flow removed; always return null so callers skip.
    return null;
  }

  static Future<Map<String, dynamic>> uploadCarVideos(
    String carId,
    List<XFile> videoFiles,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/cars/$carId/videos'),
    );

    // Add authorization header
    if (_accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    // Add files
    // Backend expects `request.files["files"]` (list).
    for (final file in videoFiles) {
      request.files.add(await http.MultipartFile.fromPath('files', file.path));
    }

    final response = await request.send().timeout(_uploadTimeout);
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Normalize { uploaded: [...] } -> { videos: [...] }
      final Map<String, dynamic> data = json.decode(responseBody);
      if (!data.containsKey('videos') && data.containsKey('uploaded')) {
        data['videos'] = List.from(data['uploaded'] as List);
      }
      return data;
    } else {
      final error = json.decode(responseBody);
      throw Exception(error['message'] ?? 'Upload failed');
    }
  }

  // Favorites methods
  static Future<Map<String, dynamic>> getFavorites({
    int page = 1,
    int perPage = 20,
  }) async {
    return await _makeAuthenticatedRequest(
      'GET',
      '/user/favorites?page=$page&per_page=$perPage',
    );
  }

  static Future<Map<String, dynamic>> toggleFavorite(String carId) async {
    return await _makeAuthenticatedRequest('POST', '/cars/$carId/favorite');
  }

  static Future<bool> isCarFavorited(String carId) async {
    final res = await _makeAuthenticatedRequest('GET', '/cars/$carId/favorite');
    return (res['is_favorited'] == true) || (res['favorited'] == true);
  }

  static Future<Map<String, dynamic>> getMyListings({
    int page = 1,
    int perPage = 20,
  }) async {
    return await _makeAuthenticatedRequest(
      'GET',
      '/user/my-listings?page=$page&per_page=$perPage',
    );
  }

  // Check if user is authenticated
  static bool get isAuthenticated => _accessToken != null;

  // Get current access token
  static String? get accessToken => _accessToken;

  // Chat fallback endpoint (works without Socket.IO connectivity).
  static Future<Map<String, dynamic>> sendChatMessageByConversation({
    required String conversationId,
    required String content,
    String? receiverId,
    Map<String, dynamic>? listingPreview,
    String? replyToMessageId,
  }) async {
    final payload = <String, dynamic>{'content': content};
    if (receiverId != null && receiverId.trim().isNotEmpty) {
      payload['receiver_id'] = receiverId.trim();
    }
    if (listingPreview != null && listingPreview.isNotEmpty) {
      payload['listing_preview'] = listingPreview;
    }
    if (replyToMessageId != null && replyToMessageId.trim().isNotEmpty) {
      payload['reply_to_message_id'] = replyToMessageId.trim();
    }
    return await _makeAuthenticatedRequest(
      'POST',
      '/chat/$conversationId/send',
      body: payload,
    );
  }

  static Future<int> getUnreadChatCount() async {
    final result = await _makeAuthenticatedRequest('GET', '/chat/unread_count');
    return (result['unread_count'] as num?)?.toInt() ?? 0;
  }

  /// Load chat history for a listing conversation (car public_id or numeric id).
  ///
  /// Returns a map with keys: `messages` (list), `page`, `per_page`, `total`, `has_more`.
  static Future<Map<String, dynamic>> getChatMessagesByConversation(
    String conversationId, {
    int page = 1,
    int perPage = 50,
  }) async {
    final endpoint = '/chat/$conversationId/messages?page=$page&per_page=$perPage';
    final url = Uri.parse('$baseUrl$endpoint');
    Map<String, String> headers = _getHeaders();

    http.Response response = await http
        .get(url, headers: headers)
        .timeout(_defaultTimeout);

    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        await clearTokens();
        throw Exception('Authentication failed');
      }
      headers = _getHeaders();
      response = await http
          .get(url, headers: headers)
          .timeout(_defaultTimeout);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _handleResponse(response);
    }

    if (response.body.trim().isEmpty) {
      return {'messages': <Map<String, dynamic>>[], 'has_more': false, 'total': 0, 'page': page};
    }
    final decoded = json.decode(response.body);

    List<Map<String, dynamic>> messages = [];
    bool hasMore = false;
    int total = 0;

    if (decoded is Map) {
      if (decoded['messages'] is List) {
        messages = (decoded['messages'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
            .toList();
      }
      hasMore = decoded['has_more'] == true;
      total = (decoded['total'] as num?)?.toInt() ?? messages.length;
    } else if (decoded is List) {
      messages = decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .toList();
    }

    return {
      'messages': messages,
      'has_more': hasMore,
      'total': total,
      'page': page,
    };
  }

  /// Upload an image and send it as a chat message.
  static Future<Map<String, dynamic>> sendChatImage({
    required String conversationId,
    required XFile imageFile,
    String? receiverId,
    String? caption,
    String? replyToMessageId,
  }) async {
    return _sendChatAttachment(
      conversationId: conversationId,
      endpointSuffix: 'send_image',
      fieldName: 'image',
      file: imageFile,
      receiverId: receiverId,
      caption: caption,
      replyToMessageId: replyToMessageId,
    );
  }

  static Future<Map<String, dynamic>> sendChatVideo({
    required String conversationId,
    required XFile videoFile,
    String? receiverId,
    String? caption,
    String? replyToMessageId,
  }) async {
    return _sendChatAttachment(
      conversationId: conversationId,
      endpointSuffix: 'send_video',
      fieldName: 'video',
      file: videoFile,
      receiverId: receiverId,
      caption: caption,
      replyToMessageId: replyToMessageId,
    );
  }

  static Future<Map<String, dynamic>> sendChatMediaGroup({
    required String conversationId,
    required List<XFile> files,
    String? receiverId,
    String? caption,
    String? replyToMessageId,
  }) async {
    if (files.isEmpty) {
      throw Exception('No attachments selected');
    }
    final url = Uri.parse('$baseUrl/chat/$conversationId/send_media_group');

    Future<http.Response> makeRequest() async {
      final req = http.MultipartRequest('POST', url);
      req.headers.addAll(_getHeaders());
      for (final file in files) {
        req.files.add(await http.MultipartFile.fromPath('attachments', file.path));
      }
      if (receiverId != null && receiverId.trim().isNotEmpty) {
        req.fields['receiver_id'] = receiverId.trim();
      }
      if (caption != null && caption.trim().isNotEmpty) {
        req.fields['content'] = caption.trim();
      }
      if (replyToMessageId != null && replyToMessageId.trim().isNotEmpty) {
        req.fields['reply_to_message_id'] = replyToMessageId.trim();
      }
      final streamedResponse = await req.send().timeout(_uploadTimeout);
      return http.Response.fromStream(streamedResponse);
    }

    var response = await makeRequest();
    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        await clearTokens();
        throw Exception('Authentication failed');
      }
      response = await makeRequest();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _handleResponse(response);
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _sendChatAttachment({
    required String conversationId,
    required String endpointSuffix,
    required String fieldName,
    required XFile file,
    String? receiverId,
    String? caption,
    String? replyToMessageId,
  }) async {
    final url = Uri.parse('$baseUrl/chat/$conversationId/$endpointSuffix');

    Future<http.Response> makeRequest() async {
      final req = http.MultipartRequest('POST', url);
      req.headers.addAll(_getHeaders());
      req.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
      if (receiverId != null && receiverId.trim().isNotEmpty) {
        req.fields['receiver_id'] = receiverId.trim();
      }
      if (caption != null && caption.trim().isNotEmpty) {
        req.fields['content'] = caption.trim();
      }
      if (replyToMessageId != null && replyToMessageId.trim().isNotEmpty) {
        req.fields['reply_to_message_id'] = replyToMessageId.trim();
      }
      final streamedResponse = await req.send().timeout(_uploadTimeout);
      return http.Response.fromStream(streamedResponse);
    }

    var response = await makeRequest();
    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        await clearTokens();
        throw Exception('Authentication failed');
      }
      response = await makeRequest();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _handleResponse(response);
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> editChatMessage({
    required String messageId,
    required String content,
  }) async {
    return await _makeAuthenticatedRequest(
      'PATCH',
      '/chat/messages/$messageId',
      body: {'content': content},
    );
  }

  static Future<Map<String, dynamic>> deleteChatMessage({
    required String messageId,
  }) async {
    return await _makeAuthenticatedRequest(
      'DELETE',
      '/chat/messages/$messageId',
    );
  }

  /// Register FCM push notification token with the backend.
  static Future<void> registerPushToken(String token) async {
    await _makeAuthenticatedRequest('POST', '/users/push_token', body: {'token': token});
  }

  /// Block a user.
  static Future<void> blockUser(String userId) async {
    await _makeAuthenticatedRequest('POST', '/users/$userId/block');
  }

  /// Unblock a user.
  static Future<void> unblockUser(String userId) async {
    await _makeAuthenticatedRequest('POST', '/users/$userId/unblock');
  }

  /// Report a user.
  static Future<void> reportUser(String userId, {required String reason, String? details}) async {
    await _makeAuthenticatedRequest('POST', '/users/$userId/report', body: {
      'reason': reason,
      if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
    });
  }

  /// Get list of blocked user IDs.
  static Future<List<String>> getBlockedUsers() async {
    final result = await _makeAuthenticatedRequest('GET', '/users/blocked');
    final raw = result['blocked_users'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  // Load recent chat conversations for the current user.
  static Future<List<Map<String, dynamic>>> getChats() async {
    final endpoint = '/chats';
    final url = Uri.parse('$baseUrl$endpoint');
    Map<String, String> headers = _getHeaders();

    http.Response response = await http
        .get(url, headers: headers)
        .timeout(_defaultTimeout);

    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        await clearTokens();
        throw Exception('Authentication failed');
      }
      headers = _getHeaders();
      response = await http
          .get(url, headers: headers)
          .timeout(_defaultTimeout);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _handleResponse(response); // Throws ApiException.
    }

    if (response.body.trim().isEmpty) return <Map<String, dynamic>>[];
    final decoded = json.decode(response.body);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .toList();
    }
    if (decoded is Map && decoded['chats'] is List) {
      final raw = decoded['chats'] as List;
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }
}
