part of '../api_service.dart';

/// Auth, profile, and dealer admin HTTP (split from [ApiService]).
abstract final class _ApiServiceAuth {
  _ApiServiceAuth._();

  static Future<Map<String, dynamic>> registerEmailRequest({
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
      final u = (username ?? '').trim();
      final normalizedPhone = (phoneNumber != null && phoneNumber.trim().isNotEmpty)
          ? normalizePhoneNumber(phoneNumber)
          : null;
      final response = await ApiService._httpClient
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/register-request'),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode({
              if (!isDealer) 'username': u,
              'email': email,
              'password': password,
              'first_name': firstName,
              'last_name': lastName,
              if (normalizedPhone != null && normalizedPhone.isNotEmpty)
                'phone_number': normalizedPhone,
              'is_dealer': isDealer,
              if (isDealer &&
                  dealershipName != null &&
                  dealershipName.trim().isNotEmpty)
                'dealership_name': dealershipName.trim(),
              if (isDealer &&
                  dealershipPhone != null &&
                  dealershipPhone.trim().isNotEmpty)
                'dealership_phone': dealershipPhone.trim(),
              if (isDealer &&
                  dealershipLocation != null &&
                  dealershipLocation.trim().isNotEmpty)
                'dealership_location': dealershipLocation.trim(),
            }),
          )
          .timeout(ApiService._defaultTimeout);

      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> confirmSignup(String token) async {
      final response = await ApiService._httpClient
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/register-confirm'),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode({'token': token}),
          )
          .timeout(ApiService._defaultTimeout);

      final data = ApiService._handleResponse(response);
      final String? access = (data['access_token'] as String?)?.trim();
      final String? refresh = (data['refresh_token'] as String?)?.trim();
      if (access != null && access.isNotEmpty) {
        await ApiService._saveAccessToken(access);
      }
      if (refresh != null && refresh.isNotEmpty) {
        await ApiService._saveRefreshToken(refresh);
      }
      return data;
    }

  static Future<Map<String, dynamic>> login(
    String emailOrPhone,
    String password,
  ) async {
      final response = await ApiService._httpClient
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/login'),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode({'username': emailOrPhone, 'password': password}),
          )
          .timeout(ApiService._defaultTimeout);

      // Accept either legacy {'token': '<jwt>'} or new {'access_token': '...', 'refresh_token': '...'}
      final data = ApiService._handleResponse(response);
      final String? legacyToken = (data['token'] as String?)?.trim();
      final String? access = (data['access_token'] as String?)?.trim();
      final String? refresh = (data['refresh_token'] as String?)?.trim();
      final token = (legacyToken != null && legacyToken.isNotEmpty)
          ? legacyToken
          : access;
      if (token != null && token.isNotEmpty) {
        await ApiService._saveAccessToken(token);
      }
      if (refresh != null && refresh.isNotEmpty) {
        await ApiService._saveRefreshToken(refresh);
      }
      return data;
    }

  static Future<Map<String, dynamic>> phoneStart({
      required String phoneNumber,
      String? username,
      String? firstName,
      String? lastName,
      String? email,
      String? password,
      bool isDealer = false,
      String? dealershipName,
      String? dealershipPhone,
      String? dealershipLocation,
    }) async {
      final normalizedPhone = normalizePhoneNumber(phoneNumber);
      final response = await ApiService._httpClient
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/phone/start'),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode({
              'phone_number': normalizedPhone,
              if ((username ?? '').trim().isNotEmpty) 'username': username,
              if ((firstName ?? '').trim().isNotEmpty) 'first_name': firstName,
              if ((lastName ?? '').trim().isNotEmpty) 'last_name': lastName,
              if ((email ?? '').trim().isNotEmpty) 'email': email,
              if ((password ?? '').trim().isNotEmpty) 'password': password,
              'is_dealer': isDealer,
              if (isDealer && (dealershipName ?? '').trim().isNotEmpty)
                'dealership_name': dealershipName,
              if (isDealer && (dealershipPhone ?? '').trim().isNotEmpty)
                'dealership_phone': dealershipPhone,
              if (isDealer && (dealershipLocation ?? '').trim().isNotEmpty)
                'dealership_location': dealershipLocation,
            }),
          )
          .timeout(ApiService._defaultTimeout);
      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> phoneVerify({
      required String phoneNumber,
      required String code,
      String? username,
      String? firstName,
      String? lastName,
      String? email,
      String? password,
      bool isDealer = false,
      String? dealershipName,
      String? dealershipPhone,
      String? dealershipLocation,
    }) async {
      final normalizedPhone = normalizePhoneNumber(phoneNumber);
      final response = await ApiService._httpClient
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/phone/verify'),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode({
              'phone_number': normalizedPhone,
              'code': code,
              if ((username ?? '').trim().isNotEmpty) 'username': username,
              if ((firstName ?? '').trim().isNotEmpty) 'first_name': firstName,
              if ((lastName ?? '').trim().isNotEmpty) 'last_name': lastName,
              if ((email ?? '').trim().isNotEmpty) 'email': email,
              if ((password ?? '').trim().isNotEmpty) 'password': password,
              'is_dealer': isDealer,
              if (isDealer && (dealershipName ?? '').trim().isNotEmpty)
                'dealership_name': dealershipName,
              if (isDealer && (dealershipPhone ?? '').trim().isNotEmpty)
                'dealership_phone': dealershipPhone,
              if (isDealer && (dealershipLocation ?? '').trim().isNotEmpty)
                'dealership_location': dealershipLocation,
            }),
          )
          .timeout(ApiService._defaultTimeout);

      final data = ApiService._handleResponse(response);
      final String? access = (data['access_token'] as String?)?.trim();
      final String? refresh = (data['refresh_token'] as String?)?.trim();
      if (access != null && access.isNotEmpty) {
        await ApiService._saveAccessToken(access);
      }
      if (refresh != null && refresh.isNotEmpty) {
        await ApiService._saveRefreshToken(refresh);
      }
      return data;
    }

  static Future<void> logout() async {
      // Best-effort server-side revocation; then clear locally.
      try {
        final headers = ApiService._getHeaders();
        final rt = (ApiService._refreshToken ?? '').trim();
        final body = (rt.isNotEmpty) ? json.encode({'refresh_token': rt}) : null;
        await ApiService._httpClient
            .post(Uri.parse('${ApiService.baseUrl}/auth/logout'), headers: headers, body: body)
            .timeout(ApiService._defaultTimeout);
      } catch (_) {}
      await ApiService.clearTokens();
    }

  static Future<Map<String, dynamic>> changePassword({
      required String currentPassword,
      required String newPassword,
    }) async {
      return await ApiService._makeAuthenticatedRequest(
        'POST',
        '/auth/change-password',
        body: {'current_password': currentPassword, 'new_password': newPassword},
      );
    }

  static Future<Map<String, dynamic>> deleteAccount({String? password}) async {
      final body = <String, dynamic>{};
      if (password != null && password.trim().isNotEmpty) {
        body['password'] = password.trim();
      }
      return await ApiService._makeAuthenticatedRequest(
        'POST',
        '/auth/delete-account',
        body: body.isNotEmpty ? body : null,
      );
    }

  static Future<Map<String, dynamic>> forgotPassword(
    String value, {
      bool isPhone = false,
    }) async {
      final trimmed = value.trim();
      final Map<String, dynamic> body;
      if (isPhone) {
        body = {'phone_number': normalizePhoneNumber(trimmed)};
      } else {
        // Backwards-compatible: backend historically mirrored email into phone_number.
        body = {'email': trimmed, 'phone_number': trimmed};
      }
      final response = await ApiService._httpClient
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/forgot-password'),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode(body),
          )
          .timeout(ApiService._defaultTimeout);

      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> resetPassword(
    String token,
    String newPassword,
  ) async {
      final response = await ApiService._httpClient
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/reset-password'),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode({'token': token, 'password': newPassword}),
          )
          .timeout(ApiService._defaultTimeout);

      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> verifyEmail(String token) async {
      final response = await ApiService._httpClient
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/verify-email'),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode({'token': token}),
          )
          .timeout(ApiService._defaultTimeout);

      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> sendEmailVerification() async {
      return await ApiService._makeAuthenticatedRequest(
        'POST',
        '/auth/send-email-verification',
      );
    }

  static Future<Map<String, dynamic>> sendPhoneVerificationCode(
    String phoneNumber,
  ) async {
      final normalizedPhone = normalizePhoneNumber(phoneNumber);
      final apiRoot = ApiService.baseUrl.endsWith('/api') ? ApiService.baseUrl : '${ApiService.baseUrl}/api';
      final url = '$apiRoot/auth/send-verification';
      final response = await ApiService._httpClient
          .post(
            Uri.parse(url),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode({'phone_number': normalizedPhone}),
          )
          .timeout(ApiService._defaultTimeout);
      if (response.statusCode == 404) {
        throw ApiException(
          statusCode: 404,
          message: 'Endpoint not found (404). Tried: $url',
          body: <String, dynamic>{'status': 404},
        );
      }
      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> sendOtpLegacy({
      required String phone,
      bool isDealer = false,
      String? dealershipName,
      String? dealershipPhone,
      String? dealershipLocation,
    }) async {
      final body = <String, dynamic>{
        'phone': phone.trim(),
        if (isDealer) ...<String, dynamic>{
          'is_dealer': true,
          'dealership_name': (dealershipName ?? '').trim(),
          'dealership_phone': (dealershipPhone ?? '').trim(),
          'dealership_location': (dealershipLocation ?? '').trim(),
        },
      };
      final response = await ApiService._httpClient
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/send_otp'),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode(body),
          )
          .timeout(ApiService._defaultTimeout);
      return ApiService._handleResponse(response);
    }

  /// Legacy phone/dealer signup (`POST /auth/signup` with OTP).
  static Future<Map<String, dynamic>> signupLegacy(
    Map<String, dynamic> body,
  ) async {
      final response = await ApiService._httpClient
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/signup'),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode(body),
          )
          .timeout(ApiService._defaultTimeout);
      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> verifyPhone(
    String phoneNumber,
    String code,
  ) async {
      final normalizedPhone = normalizePhoneNumber(phoneNumber);
      final apiRoot = ApiService.baseUrl.endsWith('/api') ? ApiService.baseUrl : '${ApiService.baseUrl}/api';
      final url = '$apiRoot/auth/verify-phone';
      final response = await ApiService._httpClient
          .post(
            Uri.parse(url),
            headers: ApiService._getHeaders(includeAuth: false),
            body: json.encode({
              'phone_number': normalizedPhone,
              'verification_code': code,
            }),
          )
          .timeout(ApiService._defaultTimeout);
      if (response.statusCode == 404) {
        throw ApiException(
          statusCode: 404,
          message: 'Endpoint not found (404). Tried: $url',
          body: <String, dynamic>{'status': 404},
        );
      }
      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> getProfile() async {
      return await ApiService._makeAuthenticatedRequest('GET', '/auth/me');
    }

  static Future<Map<String, dynamic>> getDealerProfile(String dealerPublicId) async {
      final id = Uri.encodeComponent(dealerPublicId.trim());
      final response = await ApiService._httpClient
          .get(
            Uri.parse('${ApiService.baseUrl}/dealers/$id'),
            headers: ApiService._getHeaders(includeAuth: false),
          )
          .timeout(ApiService._defaultTimeout);
      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> searchDealers({
      String? q,
      int page = 1,
      int perPage = 20,
    }) async {
      final params = <String, String>{
        'page': page.toString(),
        'per_page': perPage.toString(),
      };
      final query = (q ?? '').trim();
      if (query.isNotEmpty) params['q'] = query;
      final uri = Uri.parse('${ApiService.baseUrl}/dealers').replace(queryParameters: params);
      final response = await ApiService._httpClient
          .get(uri, headers: ApiService._getHeaders(includeAuth: false))
          .timeout(ApiService._defaultTimeout);
      return ApiService._handleResponse(response);
    }

  static Future<Map<String, dynamic>> updateDealerProfile(
    Map<String, dynamic> dealerData,
  ) async {
      return await ApiService._makeAuthenticatedRequest(
        'PUT',
        '/user/dealer-profile',
        body: dealerData,
      );
    }

  static Future<Map<String, dynamic>> adminDealersPending() async {
      return await ApiService._makeAuthenticatedRequest('GET', '/admin/dealers/pending');
    }

  static Future<Map<String, dynamic>> adminApproveDealer(String publicUserId) async {
      final id = Uri.encodeComponent(publicUserId.trim());
      return await ApiService._makeAuthenticatedRequest('POST', '/admin/dealers/$id/approve');
    }

  static Future<Map<String, dynamic>> adminRejectDealer(
    String publicUserId, {
      String? reason,
    }) async {
      final id = Uri.encodeComponent(publicUserId.trim());
      final body = <String, dynamic>{};
      if (reason != null && reason.trim().isNotEmpty) {
        body['reason'] = reason.trim();
      }
      return await ApiService._makeAuthenticatedRequest(
        'POST',
        '/admin/dealers/$id/reject',
        body: body.isNotEmpty ? body : null,
      );
    }

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profileData,
  ) async {
      return await ApiService._makeAuthenticatedRequest(
        'PUT',
        '/user/profile',
        body: profileData,
      );
    }

  static Future<Map<String, dynamic>> uploadProfilePicture(
    XFile imageFile,
  ) async {
      return ApiService._sendAuthenticatedMultipart(() async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${ApiService.baseUrl}/user/upload-profile-picture'),
        );
        request.files.add(
          await http.MultipartFile.fromPath('file', imageFile.path),
        );
        return request;
      });
    }

  static Future<Map<String, dynamic>> uploadDealerCoverPicture(
    XFile imageFile,
  ) async {
      return ApiService._sendAuthenticatedMultipart(() async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${ApiService.baseUrl}/user/upload-dealer-cover'),
        );
        request.files.add(
          await http.MultipartFile.fromPath('file', imageFile.path),
        );
        return request;
      });
    }

}
