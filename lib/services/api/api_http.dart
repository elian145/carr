part of '../api_service.dart';

/// Token storage and authenticated HTTP core (split from [ApiService]).
abstract final class _ApiServiceHttp {
  _ApiServiceHttp._();

    // Initialize tokens from storage
    static Future<void> initializeTokens() async {
      await TokenStore.load();
      ApiService._accessToken = TokenStore.token;
      ApiService._refreshToken = TokenStore.refreshToken;
    }

    // Save tokens to storage
    static Future<void> _saveAccessToken(String accessToken) async {
      await TokenStore.save(accessToken);
      ApiService._accessToken = TokenStore.token;
    }

    static Future<void> _saveRefreshToken(String? refreshToken) async {
      await TokenStore.saveRefresh(refreshToken);
      ApiService._refreshToken = TokenStore.refreshToken;
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
    static Future<void> setTokens({
      String? accessToken,
      String? refreshToken,
    }) async {
      await setAccessToken(accessToken);
      await setRefreshToken(refreshToken);
    }

    // Clear tokens
    static Future<void> clearTokens() async {
      await TokenStore.clear();
      ApiService._accessToken = null;
      ApiService._refreshToken = null;
    }

    static Future<void> _ensureTokenLoaded() async {
      if (ApiService._accessToken != null && ApiService._accessToken!.isNotEmpty) return;
      await TokenStore.load();
      final t = TokenStore.token;
      if (t != null && t.isNotEmpty) {
        ApiService._accessToken = t;
      }
    }

    // Get headers with authorization
    static Map<String, String> _getHeaders({bool includeAuth = true}) {
      Map<String, String> headers = {'Content-Type': 'application/json'};

      if (includeAuth && ApiService._accessToken != null && ApiService._accessToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $ApiService._accessToken';
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
      if (code == 429) {
        String message = 'Too many requests. Please try again later.';
        int? retryAfterSeconds;

        try {
          final Map<String, dynamic> err = body.isNotEmpty
              ? json.decode(body)
              : <String, dynamic>{};
          final msg = (err['message'] ?? err['error'] ?? '').toString().trim();
          if (msg.isNotEmpty) {
            message = msg;
          }
          final retryAfter = err['retry_after'];
          if (retryAfter is int) {
            retryAfterSeconds = retryAfter;
          } else if (retryAfter is num) {
            retryAfterSeconds = retryAfter.toInt();
          }
        } catch (_) {}

        final retryHeader = response.headers['retry-after'];
        if (retryAfterSeconds == null && retryHeader != null) {
          retryAfterSeconds = int.tryParse(retryHeader.trim());
        }

        if (retryAfterSeconds != null && retryAfterSeconds > 0) {
          final minutes = (retryAfterSeconds / 60).ceil();
          message =
              '$message Please try again in $minutes minute${minutes == 1 ? '' : 's'}.';
        }

        throw ApiException(statusCode: code, message: message);
      }
      try {
        final Map<String, dynamic> err = body.isNotEmpty
            ? json.decode(body) as Map<String, dynamic>
            : <String, dynamic>{};
        final messagePart =
            (err['message'] ?? '').toString().trim();
        final errorPart = (err['error'] ?? '').toString().trim();
        String msg = messagePart;
        if (errorPart.isNotEmpty &&
            errorPart != messagePart &&
            !messagePart.contains(errorPart)) {
          msg = msg.isEmpty ? errorPart : '$msg ($errorPart)';
        }
        if (msg.isEmpty) {
          msg = errorPart;
        }
        throw ApiException(
          statusCode: code,
          message: msg.isNotEmpty ? msg : 'API request failed ($code)',
          body: err,
        );
      } on ApiException {
        rethrow;
      } catch (_) {
        throw ApiException(
          statusCode: code,
          message: 'API request failed ($code)',
        );
      }
    }

    static Map<String, dynamic> _decodeMapBody(
      String body, {
      required int statusCode,
      String fallbackMessage = 'API request failed',
    }) {
      if (body.trim().isEmpty) {
        return <String, dynamic>{};
      }
      try {
        final decoded = json.decode(body);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
        }
        throw ApiException(
          statusCode: statusCode,
          message: '$fallbackMessage ($statusCode)',
        );
      } on ApiException {
        rethrow;
      } catch (_) {
        throw ApiException(
          statusCode: statusCode,
          message: body.trim().isNotEmpty
              ? body.trim()
              : '$fallbackMessage ($statusCode)',
        );
      }
    }

    static ApiException _uploadException(int statusCode, String responseBody) {
      String message = 'Upload failed';
      Map<String, dynamic>? body;
      try {
        final decoded = responseBody.trim().isNotEmpty
            ? json.decode(responseBody)
            : <String, dynamic>{};
        if (decoded is Map) {
          body = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
          final msg = (body['message'] ?? body['error'] ?? '').toString().trim();
          if (msg.isNotEmpty) message = msg;
        } else if (responseBody.trim().isNotEmpty) {
          message = responseBody.trim();
        }
      } catch (_) {
        if (responseBody.trim().isNotEmpty) message = responseBody.trim();
      }
      return ApiException(statusCode: statusCode, message: message, body: body);
    }

    static Future<Map<String, dynamic>> _sendAuthenticatedMultipart(
      Future<http.MultipartRequest> Function() buildRequest,
    ) async {
      await _ensureTokenLoaded();

      Future<http.Response> sendOnce() async {
        final request = await buildRequest();
        if (ApiService._accessToken != null && ApiService._accessToken!.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $ApiService._accessToken';
        }
        final streamed = await request.send().timeout(ApiService._uploadTimeout);
        return http.Response.fromStream(streamed);
      }

      var response = await sendOnce();
      if (response.statusCode == 401 && await _refreshAccessToken()) {
        response = await sendOnce();
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _decodeMapBody(
          response.body,
          statusCode: response.statusCode,
          fallbackMessage: 'Upload failed',
        );
      }
      if (response.statusCode == 401) {
        await clearTokens();
      }
      throw _uploadException(response.statusCode, response.body);
    }

    // Refresh access token
    static Future<bool> _refreshAccessToken() async {
      final rt = (ApiService._refreshToken ?? '').trim();
      if (rt.isEmpty) return false;
      try {
        final response = await ApiService._httpClient
            .post(
              Uri.parse('${ApiService.baseUrl}/auth/refresh'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $rt',
              },
            )
            .timeout(ApiService._defaultTimeout);
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
      await _ensureTokenLoaded();
      final url = Uri.parse('${ApiService.baseUrl}$endpoint');
      final requestHeaders = {..._getHeaders(), ...?headers};

      http.Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await ApiService._httpClient
              .get(url, headers: requestHeaders)
              .timeout(ApiService._defaultTimeout);
          break;
        case 'POST':
          response = await ApiService._httpClient
              .post(
                url,
                headers: requestHeaders,
                body: body != null ? json.encode(body) : null,
              )
              .timeout(ApiService._defaultTimeout);
          break;
        case 'PUT':
          response = await ApiService._httpClient
              .put(
                url,
                headers: requestHeaders,
                body: body != null ? json.encode(body) : null,
              )
              .timeout(ApiService._defaultTimeout);
          break;
        case 'PATCH':
          response = await ApiService._httpClient
              .patch(
                url,
                headers: requestHeaders,
                body: body != null ? json.encode(body) : null,
              )
              .timeout(ApiService._defaultTimeout);
          break;
        case 'DELETE':
          response = await ApiService._httpClient
              .delete(url, headers: requestHeaders)
              .timeout(ApiService._defaultTimeout);
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      // If unauthorized, try to refresh token
      if (response.statusCode == 401) {
        if (await _refreshAccessToken()) {
          // Retry request with new token
          requestHeaders['Authorization'] = 'Bearer $ApiService._accessToken';

          switch (method.toUpperCase()) {
            case 'GET':
              response = await ApiService._httpClient
                  .get(url, headers: requestHeaders)
                  .timeout(ApiService._defaultTimeout);
              break;
            case 'POST':
              response = await ApiService._httpClient
                  .post(
                    url,
                    headers: requestHeaders,
                    body: body != null ? json.encode(body) : null,
                  )
                  .timeout(ApiService._defaultTimeout);
              break;
            case 'PUT':
              response = await ApiService._httpClient
                  .put(
                    url,
                    headers: requestHeaders,
                    body: body != null ? json.encode(body) : null,
                  )
                  .timeout(ApiService._defaultTimeout);
              break;
            case 'PATCH':
              response = await ApiService._httpClient
                  .patch(
                    url,
                    headers: requestHeaders,
                    body: body != null ? json.encode(body) : null,
                  )
                  .timeout(ApiService._defaultTimeout);
              break;
            case 'DELETE':
              response = await ApiService._httpClient
                  .delete(url, headers: requestHeaders)
                  .timeout(ApiService._defaultTimeout);
              break;
          }
        } else {
          await clearTokens();
          throw Exception('Authentication failed');
        }
      }

      return _handleResponse(response);
    }
}
