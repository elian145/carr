import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';

class ApiService {
  static String get baseUrl {
    return apiBaseApi();
  }
  static String? _accessToken;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // Initialize tokens from storage
  static Future<void> initializeTokens() async {
    // Align with AuthStore key; guard against keychain issues on sideload builds
    try {
      _accessToken = await _storage.read(key: 'auth_token');
    } catch (_) {
      _accessToken = null;
    }
  }

  // Save tokens to storage
  static Future<void> _saveAccessToken(String accessToken) async {
    try {
      await _storage.write(key: 'auth_token', value: accessToken);
      _accessToken = accessToken;
    } catch (_) {
      _accessToken = accessToken;
    }
  }

  // Clear tokens
  static Future<void> clearTokens() async {
    try {
      await _storage.delete(key: 'auth_token');
    } catch (_) {}
    _accessToken = null;
  }

  // Get headers with authorization
  static Map<String, String> _getHeaders({bool includeAuth = true}) {
    Map<String, String> headers = {
      'Content-Type': 'application/json',
    };
    
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
      final Map<String, dynamic> err = body.isNotEmpty ? json.decode(body) : <String, dynamic>{};
      throw Exception(err['error'] ?? err['message'] ?? 'API request failed (${response.statusCode})');
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
        'phone': phoneNumber ?? '',
        'password': password,
        'otp_code': otp,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _getHeaders(includeAuth: false),
      body: json.encode({
        'username': username,
        'password': password,
      }),
    );

    final data = _handleResponse(response);
    final String? token = (data['token'] as String?)?.trim();
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

  static Future<Map<String, dynamic>> resetPassword(String token, String newPassword) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: _getHeaders(includeAuth: false),
      body: json.encode({
        'token': token,
        'password': newPassword,
      }),
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

  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> profileData) async {
    return await _makeAuthenticatedRequest('PUT', '/user/profile', body: profileData);
  }

  static Future<Map<String, dynamic>> uploadProfilePicture(XFile imageFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/user/upload-profile-picture'),
    );

    // Add authorization header
    if (_accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    // Add file
    request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));

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

  static Future<Map<String, dynamic>> createCar(Map<String, dynamic> carData) async {
    return await _makeAuthenticatedRequest('POST', '/cars', body: carData);
  }

  static Future<Map<String, dynamic>> updateCar(String carId, Map<String, dynamic> carData) async {
    return await _makeAuthenticatedRequest('PUT', '/cars/$carId', body: carData);
  }

  static Future<Map<String, dynamic>> deleteCar(String carId) async {
    return await _makeAuthenticatedRequest('DELETE', '/cars/$carId');
  }

  static Future<Map<String, dynamic>> uploadCarImages(String carId, List<XFile> imageFiles) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/cars/$carId/images'),
    );

    // Add authorization header
    if (_accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    // Add files
    for (final file in imageFiles) {
      request.files.add(await http.MultipartFile.fromPath('files', file.path));
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(responseBody);
    } else {
      final error = json.decode(responseBody);
      throw Exception(error['message'] ?? 'Upload failed');
    }
  }

  /// Request a presigned POST to upload an image directly to Cloudflare R2.
  ///
  /// Returns:
  /// - upload: { url, fields }
  /// - public_url: final public URL to store/display
  static Future<Map<String, dynamic>> signR2ImageUpload({
    required String carId,
    required String filename,
    required String contentType,
    int? sizeBytes,
  }) async {
    final res = await _makeAuthenticatedRequest(
      'POST',
      '/media/r2/sign-upload',
      body: {
        'listing_id': carId,
        'filename': filename,
        'content_type': contentType,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
      },
    );
    return res;
  }

  /// Upload a file to R2 using a presigned POST payload returned by [signR2ImageUpload].
  static Future<void> uploadToPresignedPost({
    required String url,
    required Map<String, dynamic> fields,
    required XFile file,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse(url));
    fields.forEach((k, v) {
      if (v == null) return;
      req.fields[k] = v.toString();
    });
    req.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
      ),
    );
    final resp = await req.send();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = await resp.stream.bytesToString();
      throw Exception('R2 upload failed (${resp.statusCode}): $body');
    }
  }

  /// Attach already-uploaded R2 public URLs to a listing.
  static Future<Map<String, dynamic>> attachCarImageUrls({
    required String carId,
    required List<String> urls,
  }) async {
    return await _makeAuthenticatedRequest(
      'POST',
      '/cars/$carId/images/attach',
      body: {'urls': urls},
    );
  }

  static Future<Map<String, dynamic>> uploadCarVideos(String carId, List<XFile> videoFiles) async {
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
      request.files.add(await http.MultipartFile.fromPath('files', file.path));
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(responseBody);
    } else {
      final error = json.decode(responseBody);
      throw Exception(error['message'] ?? 'Upload failed');
    }
  }

  // Favorites methods
  static Future<Map<String, dynamic>> getFavorites({int page = 1, int perPage = 20}) async {
    return await _makeAuthenticatedRequest('GET', '/user/favorites?page=$page&per_page=$perPage');
  }

  static Future<Map<String, dynamic>> toggleFavorite(String carId) async {
    return await _makeAuthenticatedRequest('POST', '/cars/$carId/favorite');
  }

  // Check if user is authenticated
  static bool get isAuthenticated => _accessToken != null;

  // Get current access token
  static String? get accessToken => _accessToken;
}
