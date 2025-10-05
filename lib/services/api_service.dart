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

  // Normalize a car object so the UI has consistent keys and types
  static Map<String, dynamic> _normalizeCar(Map<String, dynamic> input) {
    final Map<String, dynamic> car = Map<String, dynamic>.from(input);
    // Ensure id is a string
    final dynamic idRaw = car['id'];
    car['id'] = idRaw?.toString() ?? '';
    // Strings
    for (final key in [
      'brand', 'model', 'body_type', 'transmission', 'drive_type', 'engine_type',
      'condition', 'color', 'location', 'title', 'title_status', 'license_plate_type',
      'city',
    ]) {
      final v = car[key];
      car[key] = v == null ? '' : v.toString();
    }
    // Numbers
    car['year'] = car['year'] is num ? car['year'] : int.tryParse('${car['year'] ?? ''}') ?? 0;
    car['mileage'] = car['mileage'] is num ? car['mileage'] : int.tryParse('${car['mileage'] ?? ''}') ?? 0;
    car['price'] = car['price'] is num ? car['price'] : double.tryParse('${car['price'] ?? ''}') ?? 0.0;
    car['seating'] = car['seating'] is num ? car['seating'] : int.tryParse('${car['seating'] ?? ''}') ?? 0;
    car['cylinder_count'] = car['cylinder_count'] is num ? car['cylinder_count'] : int.tryParse('${car['cylinder_count'] ?? ''}') ?? 0;
    // Images: accept list of strings or list of maps {image_url}
    final dynamic imagesRaw = car['images'];
    List<String> images = const [];
    if (imagesRaw is List) {
      images = imagesRaw.map((it) {
        if (it is String) return it;
        if (it is Map && it['image_url'] is String) return it['image_url'] as String;
        return '';
      }).where((s) => s.isNotEmpty).toList();
    }
    car['images'] = images;
    // Videos: accept list of strings or list of maps {video_url}
    final dynamic videosRaw = car['videos'];
    List<String> videos = const [];
    if (videosRaw is List) {
      videos = videosRaw.map((it) {
        if (it is String) return it;
        if (it is Map && it['video_url'] is String) return it['video_url'] as String;
        return '';
      }).where((s) => s.isNotEmpty).toList();
    }
    car['videos'] = videos;
    // Primary image
    final dynamic imageUrlRaw = car['image_url'];
    car['image_url'] = imageUrlRaw is String && imageUrlRaw.isNotEmpty
        ? imageUrlRaw
        : (images.isNotEmpty ? images.first : '');
    return car;
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
    // Accept multiple token shapes from different backends
    String? rawToken;
    final dynamic t1 = data['token'];
    final dynamic t2 = data['access_token'];
    if (t1 is String && t1.trim().isNotEmpty) rawToken = t1.trim();
    if ((rawToken == null || rawToken.isEmpty) && t2 is String && t2.trim().isNotEmpty) rawToken = t2.trim();
    if ((rawToken == null || rawToken.isEmpty) && data['jwt'] is String) rawToken = (data['jwt'] as String).trim();
    if (rawToken != null && rawToken.isNotEmpty) {
      await _saveAccessToken(rawToken);
    }
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
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
    // Try common endpoints in order
    try {
      return await _makeAuthenticatedRequest('GET', '/auth/me');
    } catch (_) {}
    try {
      // Some backends expose /user as bare object
      final resp = await _makeAuthenticatedRequest('GET', '/user');
      return (resp is Map<String, dynamic> && resp.containsKey('id')) ? resp : resp;
    } catch (_) {}
    // Fallback to empty
    return <String, dynamic>{};
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
    final dynamic decoded = _handleResponse(response);
    if (decoded is List) {
      // Wrap list into expected shape
      final int total = decoded.length;
      final cars = List<Map<String, dynamic>>.from(decoded.map((e) => Map<String, dynamic>.from(e as Map)));
      final normalized = cars.map(_normalizeCar).toList();
      return {
        'cars': normalized,
        'pagination': {
          'page': page,
          'per_page': perPage,
          'total': total,
          'pages': (total / (perPage == 0 ? 1 : perPage)).ceil(),
          'has_next': total > perPage,
          'has_prev': page > 1,
        },
      };
    }
    if (decoded is Map<String, dynamic>) {
      // If shape is {cars:[...]}
      if (decoded['cars'] is List) {
        final list = List<Map<String, dynamic>>.from((decoded['cars'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        decoded['cars'] = list.map(_normalizeCar).toList();
      }
      return decoded;
    }
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> getCar(String carId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/cars/$carId'),
      headers: _getHeaders(includeAuth: false),
    );
    final dynamic decoded = _handleResponse(response);
    if (decoded is Map<String, dynamic> && decoded.containsKey('car')) {
      final obj = Map<String, dynamic>.from(decoded);
      if (obj['car'] is Map<String, dynamic>) {
        obj['car'] = _normalizeCar(Map<String, dynamic>.from(obj['car'] as Map));
      }
      return obj;
    }
    if (decoded is Map<String, dynamic>) {
      return {'car': _normalizeCar(decoded)};
    }
    return <String, dynamic>{};
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
      // Support both backends: some expect 'files', others expect 'video'
      final multipart = await http.MultipartFile.fromPath('video', file.path);
      request.files.add(multipart);
      // Also include under 'files' for compatibility (ignored by servers that only read 'video')
      request.files.add(await http.MultipartFile.fromPath('files', file.path));
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Normalize response to always return {'videos': List<String>}
      final dynamic decoded = responseBody.isNotEmpty ? json.decode(responseBody) : <String, dynamic>{};
      List<dynamic> raw;
      if (decoded is Map && decoded['videos'] is List) {
        raw = decoded['videos'] as List;
      } else if (decoded is Map && decoded['uploaded'] is List) {
        raw = decoded['uploaded'] as List; // e.g., ["car_videos/xyz.mp4"]
      } else {
        raw = const [];
      }

      // Map items to relative string paths like 'car_videos/filename'
      final List<String> normalized = raw.map((it) {
        if (it is String) {
          final s = it.startsWith('uploads/') ? it.substring(8) : it;
          return s;
        }
        if (it is Map && it['video_url'] is String) {
          final s = (it['video_url'] as String);
          return s.startsWith('uploads/') ? s.substring(8) : s;
        }
        return '';
      }).where((s) => s.isNotEmpty).toList();

      return {'videos': normalized};
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
