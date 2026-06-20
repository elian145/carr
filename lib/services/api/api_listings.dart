part of '../api_service.dart';

/// Cars, favorites, saved searches (split from [ApiService]).
abstract final class _ApiServiceListings {
  _ApiServiceListings._();

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

      final response = await ApiService._httpClient
          .get(
            Uri.parse('${ApiService.baseUrl}/cars?$queryString'),
            headers: ApiService._getHeaders(includeAuth: false),
          )
          .timeout(ApiService._defaultTimeout);

      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> getCar(String carId) async {
      await ApiService._ensureTokenLoaded();
      final response = await ApiService._httpClient
          .get(
            Uri.parse('${ApiService.baseUrl}/cars/${Uri.encodeComponent(carId.trim())}'),
            headers: ApiService._getHeaders(includeAuth: true),
          )
          .timeout(ApiService._defaultTimeout);

      return unwrapCarApiPayload(ApiService._handleResponse(response));
    }

  /// Parses car detail JSON (legacy list, `{car: ...}`, or flat map). Returns null when unknown.
  static Map<String, dynamic>? parseCarDetailPayload(dynamic data) {
      if (data is List && data.isNotEmpty && data.first is Map) {
        return Map<String, dynamic>.from(
          (data.first as Map).map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      if (data is Map) {
        final map = Map<String, dynamic>.from(
          data.map((k, v) => MapEntry(k.toString(), v)),
        );
        return unwrapCarApiPayload(map);
      }
      return null;
    }

  /// Loads a single listing for detail pages; returns null on failure (callers may use cache).
  static Future<Map<String, dynamic>?> getCarDetail(String carId) async {
      final id = Uri.encodeComponent(carId.trim());
      if (id.isEmpty) return null;
      try {
        await ApiService._ensureTokenLoaded();
        final url = Uri.parse('${ApiService.baseUrl}/cars/$id');
        var headers = ApiService._getHeaders(includeAuth: true);
        var response = await ApiService._httpClient
            .get(url, headers: headers)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 401 &&
            await ApiService._refreshAccessToken()) {
          headers = ApiService._getHeaders(includeAuth: true);
          response = await ApiService._httpClient
              .get(url, headers: headers)
              .timeout(const Duration(seconds: 20));
        }
        if (response.statusCode != 200) return null;
        if (response.body.isEmpty) return null;
        final decoded = json.decode(response.body);
        return parseCarDetailPayload(decoded);
      } catch (_) {
        return null;
      }
    }

  static Future<Map<String, dynamic>> createCar(
    Map<String, dynamic> carData,
  ) async {
      return await ApiService._makeAuthenticatedRequest('POST', '/cars', body: carData);
    }

  static Future<Map<String, dynamic>> updateCar(
    String carId,
    Map<String, dynamic> carData,
  ) async {
      final id = Uri.encodeComponent(carId.trim());
      return await ApiService._makeAuthenticatedRequest(
        'PUT',
        '/cars/$id',
        body: carData,
      );
    }

  static Future<Map<String, dynamic>> deleteCar(String carId) async {
      final id = Uri.encodeComponent(carId.trim());
      return await ApiService._makeAuthenticatedRequest('DELETE', '/cars/$id');
    }

  static Future<Map<String, dynamic>> markListingSold(String carId) async {
      final id = Uri.encodeComponent(carId.trim());
      return await ApiService._makeAuthenticatedRequest('POST', '/cars/$id/mark-sold');
    }

  static Future<Map<String, dynamic>> markListingActive(String carId) async {
      final id = Uri.encodeComponent(carId.trim());
      return await ApiService._makeAuthenticatedRequest('POST', '/cars/$id/mark-active');
    }

  static Future<Map<String, dynamic>> uploadCarImages(
    String carId,
    List<XFile> imageFiles, {
      bool blurPlates = false,
      /// Backend: `kind=damage` for crash/damage disclosure (excluded from main gallery).
      String imageKind = 'listing',
    }) async {
      // App-default behavior: do NOT blur unless user explicitly requests it.
      // FORCE_SKIP_BLUR remains a hard override for dev/testing builds.
      final bool skipBlur = forceSkipBlur() || !blurPlates;
      final qp = <String>[];
      if (skipBlur) qp.add('skip_blur=1');
      if (imageKind.toLowerCase() == 'damage') qp.add('kind=damage');
      final String query = qp.isEmpty ? '' : '?${qp.join('&')}';
      final data = await ApiService._sendAuthenticatedMultipart(() async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${ApiService.baseUrl}/cars/$carId/images$query'),
        );
        // Add files once under 'images' (backend accepts 'files', 'images', 'image', etc. and extends one list — do not send same file under multiple keys or backend gets duplicates)
        for (final file in imageFiles) {
          request.files.add(await http.MultipartFile.fromPath('images', file.path));
        }
        return request;
      });
      // Backend compatibility: some endpoints return { uploaded: [...] }
      // Normalize to { images: [...] } expected by UI services
      if (!data.containsKey('images') && data.containsKey('uploaded')) {
        data['images'] = List.from(data['uploaded'] as List);
      }
      return data;
    }

  static Future<Map<String, dynamic>> attachCarImages(
    String carId,
    List<String> paths, {
      String kind = 'listing',
    }) async {
      final body = <String, dynamic>{
        'paths': paths,
        if (kind.toLowerCase() == 'damage') 'kind': 'damage',
      };
      return await ApiService._makeAuthenticatedRequest(
        'POST',
        '/cars/$carId/images/attach',
        body: body,
      );
    }

  static Future<Map<String, dynamic>> signR2ImageUpload({
      String? filename,
      String? contentType,
    }) async {
      final body = <String, dynamic>{};
      if (filename != null && filename.isNotEmpty) {
        body['filename'] = filename;
      }
      if (contentType != null && contentType.isNotEmpty) {
        body['content_type'] = contentType;
      }
      return await ApiService._makeAuthenticatedRequest(
        'POST',
        '/media/r2/sign-upload',
        body: body.isNotEmpty ? body : null,
      );
    }

  static Future<void> uploadToSignedUpload(String uploadUrl, XFile file) async {
      final bytes = await file.readAsBytes();
      final uri = Uri.parse(uploadUrl);
      final response = await ApiService._httpClient
          .put(
            uri,
            body: bytes,
            headers: <String, String>{
              'Content-Type': file.mimeType ?? 'image/jpeg',
            },
          )
          .timeout(ApiService._uploadTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          statusCode: response.statusCode,
          message: response.body.isNotEmpty ? response.body : 'Upload failed',
        );
      }
    }

  static Future<Map<String, dynamic>> attachCarImageUrls(
    String carId,
    List<String> urls, {
      String kind = 'listing',
    }) async {
      final body = <String, dynamic>{
        'urls': urls,
        if (kind.toLowerCase() == 'damage') 'kind': 'damage',
      };
      return await ApiService._makeAuthenticatedRequest(
        'POST',
        '/cars/$carId/images/attach',
        body: body,
      );
    }

  static List<String>? getLastProcessedServerPaths() {
    // Attach-based flow removed; always return null so callers skip.
    return null;
  }

  static Future<Map<String, dynamic>> uploadCarVideos(
    String carId,
    List<XFile> videoFiles, {
    Future<http.MultipartFile> Function(XFile file)? multipartFileBuilder,
  }) async {
      final buildFile = multipartFileBuilder ??
          (file) => http.MultipartFile.fromPath('files', file.path);
      final data = await ApiService._sendAuthenticatedMultipart(() async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${ApiService.baseUrl}/cars/$carId/videos'),
        );
        for (final file in videoFiles) {
          request.files.add(await buildFile(file));
        }
        return request;
      });
      // Normalize { uploaded: [...] } -> { videos: [...] }
      if (!data.containsKey('videos') && data.containsKey('uploaded')) {
        data['videos'] = List.from(data['uploaded'] as List);
      }
      return data;
    }

  static Future<Map<String, dynamic>> getFavorites({
      int page = 1,
      int perPage = 20,
    }) async {
      return await ApiService._makeAuthenticatedRequest(
        'GET',
        '/user/favorites?page=$page&per_page=$perPage',
      );
    }

  static Future<Map<String, dynamic>> toggleFavorite(String carId) async {
      return await ApiService._makeAuthenticatedRequest('POST', '/cars/$carId/favorite');
    }

  static Future<bool> isCarFavorited(String carId) async {
      final res = await ApiService._makeAuthenticatedRequest('GET', '/cars/$carId/favorite');
      return (res['is_favorited'] == true) || (res['favorited'] == true);
    }

  static Future<Map<String, dynamic>> getSavedSearches() async {
      return await ApiService._makeAuthenticatedRequest('GET', '/saved-searches');
    }

  static Future<Map<String, dynamic>> syncSavedSearches(
    List<Map<String, dynamic>> items,
  ) async {
      return await ApiService._makeAuthenticatedRequest(
        'POST',
        '/saved-searches/sync',
        body: {'items': items},
      );
    }

  static Future<Map<String, dynamic>> createSavedSearch({
      required String name,
      required Map<String, dynamic> filters,
      bool notify = true,
      bool autoSaved = false,
    }) async {
      return await ApiService._makeAuthenticatedRequest(
        'POST',
        '/saved-searches',
        body: {
          'name': name,
          'filters': filters,
          'notify': notify,
          'auto_saved': autoSaved,
        },
      );
    }

  static Future<Map<String, dynamic>> updateSavedSearch(
    String searchId, {
      String? name,
      Map<String, dynamic>? filters,
      bool? notify,
      bool? autoSaved,
    }) async {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (filters != null) body['filters'] = filters;
      if (notify != null) body['notify'] = notify;
      if (autoSaved != null) body['auto_saved'] = autoSaved;
      return await ApiService._makeAuthenticatedRequest(
        'PUT',
        '/saved-searches/$searchId',
        body: body,
      );
    }

  static Future<void> deleteSavedSearch(String searchId) async {
      await ApiService._makeAuthenticatedRequest('DELETE', '/saved-searches/$searchId');
    }

  static Future<Map<String, dynamic>> getRecentlyViewed({
      int page = 1,
      int perPage = 20,
    }) async {
      return await ApiService._makeAuthenticatedRequest(
        'GET',
        '/user/recently-viewed?page=$page&per_page=$perPage',
      );
    }

  static Future<void> recordListingView(String listingId) async {
      final id = listingId.trim();
      if (id.isEmpty) return;
      await ApiService._makeAuthenticatedRequest(
        'POST',
        '/user/recently-viewed',
        body: {'listing_id': id},
      );
    }

  static Future<void> clearRecentlyViewed() async {
      await ApiService._makeAuthenticatedRequest('DELETE', '/user/recently-viewed');
    }

  static Future<void> deleteRecentlyViewedListing(String listingId) async {
      final id = Uri.encodeComponent(listingId.trim());
      if (id.isEmpty) return;
      await ApiService._makeAuthenticatedRequest('DELETE', '/user/recently-viewed/$id');
    }

  static Future<Map<String, dynamic>> getMyListings({
      int page = 1,
      int perPage = 20,
    }) async {
      return await ApiService._makeAuthenticatedRequest(
        'GET',
        '/user/my-listings?page=$page&per_page=$perPage',
      );
    }

  /// Legacy mobile alias: `GET /api/my_listings` returns a bare JSON array.
  static Future<List<Map<String, dynamic>>> getMyListingsCompat() async {
      return ApiService._makeAuthenticatedListRequest('/my_listings');
    }

  /// Public car search with arbitrary query params (home feed, filters, sort fallbacks).
  static Future<http.Response> getCarsRaw(
    Map<String, String> queryParams, {
    Duration timeout = const Duration(seconds: 60),
    Map<String, String>? extraHeaders,
  }) async {
      final uri = Uri.parse('${ApiService.baseUrl}/cars')
          .replace(queryParameters: queryParams);
      final headers = {
        ...ApiService._getHeaders(includeAuth: false),
        ...?extraHeaders,
      };
      return ApiService._httpClient
          .get(uri, headers: headers)
          .timeout(timeout);
    }

}
