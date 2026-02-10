import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import '../shared/auth/token_store.dart';

class ApiService {
  static String get baseUrl {
    return apiBaseApi();
  }

  static String? _accessToken;

  // Initialize tokens from storage
  static Future<void> initializeTokens() async {
    await TokenStore.load();
    _accessToken = TokenStore.token;
  }

  // Save tokens to storage
  static Future<void> _saveAccessToken(String accessToken) async {
    await TokenStore.save(accessToken);
    _accessToken = TokenStore.token;
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

  // Clear tokens
  static Future<void> clearTokens() async {
    await TokenStore.clear();
    _accessToken = null;
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
      throw Exception(
        err['error'] ??
            err['message'] ??
            'API request failed (${response.statusCode})',
      );
    } catch (_) {
      throw Exception('API request failed (${response.statusCode})');
    }
  }

  // Refresh access token
  static Future<bool> _refreshAccessToken() async {
    // No refresh token endpoint in backend; always fail
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
        response = await http.get(url, headers: requestHeaders);
        break;
      case 'POST':
        response = await http.post(
          url,
          headers: requestHeaders,
          body: body != null ? json.encode(body) : null,
        );
        break;
      case 'PUT':
        response = await http.put(
          url,
          headers: requestHeaders,
          body: body != null ? json.encode(body) : null,
        );
        break;
      case 'DELETE':
        response = await http.delete(url, headers: requestHeaders);
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
            response = await http.get(url, headers: requestHeaders);
            break;
          case 'POST':
            response = await http.post(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            );
            break;
          case 'PUT':
            response = await http.put(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            );
            break;
          case 'DELETE':
            response = await http.delete(url, headers: requestHeaders);
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
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
  }) async {
    String otp = '000000';
    if ((phoneNumber ?? '').trim().isNotEmpty) {
      try {
        final r = await http.post(
          Uri.parse('$baseUrl/auth/send_otp'),
          headers: _getHeaders(includeAuth: false),
          body: json.encode({'phone': phoneNumber}),
        );
        if (r.statusCode == 200) {
          final d = json.decode(r.body);
          // When SMS isn’t configured, backend returns dev_code
          otp = (d['dev_code'] ?? otp).toString();
        }
      } catch (_) {}
    }

    final response = await http.post(
      Uri.parse('$baseUrl/auth/signup'),
      headers: _getHeaders(includeAuth: false),
      body: json.encode({
        'username': username,
        'email': email,
        'phone': (phoneNumber ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'otp_code': otp,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> login(
    String emailOrPhone,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _getHeaders(includeAuth: false),
      body: json.encode({'username': emailOrPhone, 'password': password}),
    );

    // Accept either legacy {'token': '<jwt>'} or new {'access_token': '...', 'refresh_token': '...'}
    final data = _handleResponse(response);
    final String? legacyToken = (data['token'] as String?)?.trim();
    final String? access = (data['access_token'] as String?)?.trim();
    final token = (legacyToken != null && legacyToken.isNotEmpty)
        ? legacyToken
        : access;
    if (token != null && token.isNotEmpty) {
      await _saveAccessToken(token);
    }
    return data;
  }

  static Future<void> logout() async {
    await clearTokens();
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: _getHeaders(includeAuth: false),
      body: json.encode({'email': email}),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> resetPassword(
    String token,
    String newPassword,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: _getHeaders(includeAuth: false),
      body: json.encode({'token': token, 'password': newPassword}),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> verifyEmail(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/verify-email'),
      headers: _getHeaders(includeAuth: false),
      body: json.encode({'token': token}),
    );

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

    final response = await request.send();
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

    final response = await http.get(
      Uri.parse('$baseUrl/cars?$queryString'),
      headers: _getHeaders(includeAuth: false),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getCar(String carId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/cars/$carId'),
      headers: _getHeaders(includeAuth: false),
    );

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
    List<XFile> imageFiles,
  ) async {
    // IMPORTANT: Do not blur on submit. Blurring only happens when user taps "Blur Plates"
    // which uses /api/process-car-images. Here we always skip blur.
    const String query = '?skip_blur=1';
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

    final response = await request.send();
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
    for (final file in videoFiles) {
      request.files.add(await http.MultipartFile.fromPath('video', file.path));
    }

    final response = await request.send();
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

  // Check if user is authenticated
  static bool get isAuthenticated => _accessToken != null;

  // Get current access token
  static String? get accessToken => _accessToken;
}
