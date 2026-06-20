import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import '../shared/auth/token_store.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/phone/phone_normalizer.dart';
import 'api_exception.dart';

export 'api_exception.dart';

part 'api/api_auth.dart';
part 'api/api_listings.dart';
part 'api/api_chat.dart';
part 'api/api_admin.dart';

class ApiService {
  /// 60s to allow Render (and similar PaaS) cold starts on first request.
  static const Duration _defaultTimeout = Duration(seconds: 60);
  static const Duration _uploadTimeout = Duration(seconds: 180);

  static String get baseUrl {
    return apiBaseApi();
  }

  static String? _accessToken;
  static String? _refreshToken;

  static final http.Client _productionHttpClient = http.Client();
  static http.Client? _testHttpClient;

  /// Widget/integration tests: route API calls through [FakeApiServer] mock client.
  @visibleForTesting
  static set testHttpClient(http.Client? client) {
    _testHttpClient = client;
  }

  @visibleForTesting
  static http.Client? get boundTestHttpClient => _testHttpClient;

  /// Whether tests have bound an in-memory HTTP client (skip real-time transports).
  static bool get isTestHttpClientBound => _testHttpClient != null;

  static http.Client get _httpClient =>
      _testHttpClient ?? _productionHttpClient;

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
    _accessToken = null;
    _refreshToken = null;
  }

  static Future<void> _ensureTokenLoaded() async {
    if (_accessToken != null && _accessToken!.isNotEmpty) return;
    await TokenStore.load();
    final t = TokenStore.token;
    if (t != null && t.isNotEmpty) {
      _accessToken = t;
    }
  }

  // Get headers with authorization
  static Map<String, String> _getHeaders({bool includeAuth = true}) {
    Map<String, String> headers = {'Content-Type': 'application/json'};

    if (includeAuth && _accessToken != null && _accessToken!.isNotEmpty) {
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
      if (_accessToken != null && _accessToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }
      final streamed = await request.send().timeout(_uploadTimeout);
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
    final rt = (_refreshToken ?? '').trim();
    if (rt.isEmpty) return false;
    try {
      final response = await _httpClient
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
    await _ensureTokenLoaded();
    final url = Uri.parse('$baseUrl$endpoint');
    final requestHeaders = {..._getHeaders(), ...?headers};

    http.Response response;

    switch (method.toUpperCase()) {
      case 'GET':
        response = await _httpClient
            .get(url, headers: requestHeaders)
            .timeout(_defaultTimeout);
        break;
      case 'POST':
        response = await _httpClient
            .post(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            )
            .timeout(_defaultTimeout);
        break;
      case 'PUT':
        response = await _httpClient
            .put(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            )
            .timeout(_defaultTimeout);
        break;
      case 'PATCH':
        response = await _httpClient
            .patch(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            )
            .timeout(_defaultTimeout);
        break;
      case 'DELETE':
        response = await _httpClient
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
            response = await _httpClient
                .get(url, headers: requestHeaders)
                .timeout(_defaultTimeout);
            break;
          case 'POST':
            response = await _httpClient
                .post(
                  url,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null,
                )
                .timeout(_defaultTimeout);
            break;
          case 'PUT':
            response = await _httpClient
                .put(
                  url,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null,
                )
                .timeout(_defaultTimeout);
            break;
          case 'PATCH':
            response = await _httpClient
                .patch(
                  url,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null,
                )
                .timeout(_defaultTimeout);
            break;
          case 'DELETE':
            response = await _httpClient
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

  // Authentication & profile (api/api_auth.dart)
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
  }) =>
      _ApiServiceAuth.registerEmailRequest(
        username: username,
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

  static Future<Map<String, dynamic>> confirmSignup(String token) =>
      _ApiServiceAuth.confirmSignup(token);

  static Future<Map<String, dynamic>> login(
    String emailOrPhone,
    String password,
  ) =>
      _ApiServiceAuth.login(emailOrPhone, password);

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
  }) =>
      _ApiServiceAuth.phoneStart(
        phoneNumber: phoneNumber,
        username: username,
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
        isDealer: isDealer,
        dealershipName: dealershipName,
        dealershipPhone: dealershipPhone,
        dealershipLocation: dealershipLocation,
      );

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
  }) =>
      _ApiServiceAuth.phoneVerify(
        phoneNumber: phoneNumber,
        code: code,
        username: username,
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
        isDealer: isDealer,
        dealershipName: dealershipName,
        dealershipPhone: dealershipPhone,
        dealershipLocation: dealershipLocation,
      );

  static Future<void> logout() => _ApiServiceAuth.logout();

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _ApiServiceAuth.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

  static Future<Map<String, dynamic>> deleteAccount({String? password}) =>
      _ApiServiceAuth.deleteAccount(password: password);

  static Future<Map<String, dynamic>> forgotPassword(
    String value, {
    bool isPhone = false,
  }) =>
      _ApiServiceAuth.forgotPassword(value, isPhone: isPhone);

  static Future<Map<String, dynamic>> resetPassword(
    String token,
    String newPassword,
  ) =>
      _ApiServiceAuth.resetPassword(token, newPassword);

  static Future<Map<String, dynamic>> verifyEmail(String token) =>
      _ApiServiceAuth.verifyEmail(token);

  static Future<Map<String, dynamic>> sendEmailVerification() =>
      _ApiServiceAuth.sendEmailVerification();

  static Future<Map<String, dynamic>> sendPhoneVerificationCode(
    String phoneNumber,
  ) =>
      _ApiServiceAuth.sendPhoneVerificationCode(phoneNumber);

  static Future<Map<String, dynamic>> verifyPhone(
    String phoneNumber,
    String code,
  ) =>
      _ApiServiceAuth.verifyPhone(phoneNumber, code);

  static Future<Map<String, dynamic>> getProfile() => _ApiServiceAuth.getProfile();

  static Future<Map<String, dynamic>> getDealerProfile(String dealerPublicId) =>
      _ApiServiceAuth.getDealerProfile(dealerPublicId);

  static Future<Map<String, dynamic>> searchDealers({
    String? q,
    int page = 1,
    int perPage = 20,
  }) =>
      _ApiServiceAuth.searchDealers(q: q, page: page, perPage: perPage);

  static Future<Map<String, dynamic>> updateDealerProfile(
    Map<String, dynamic> dealerData,
  ) =>
      _ApiServiceAuth.updateDealerProfile(dealerData);

  static Future<Map<String, dynamic>> adminDealersPending() =>
      _ApiServiceAuth.adminDealersPending();

  static Future<Map<String, dynamic>> adminApproveDealer(String publicUserId) =>
      _ApiServiceAuth.adminApproveDealer(publicUserId);

  static Future<Map<String, dynamic>> adminRejectDealer(
    String publicUserId, {
    String? reason,
  }) =>
      _ApiServiceAuth.adminRejectDealer(publicUserId, reason: reason);

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profileData,
  ) =>
      _ApiServiceAuth.updateProfile(profileData);

  static Future<Map<String, dynamic>> uploadProfilePicture(XFile imageFile) =>
      _ApiServiceAuth.uploadProfilePicture(imageFile);

  static Future<Map<String, dynamic>> uploadDealerCoverPicture(XFile imageFile) =>
      _ApiServiceAuth.uploadDealerCoverPicture(imageFile);

  // Listings, favorites, saved searches (api/api_listings.dart)
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
  }) =>
      _ApiServiceListings.getCars(
        page: page,
        perPage: perPage,
        brand: brand,
        model: model,
        yearMin: yearMin,
        yearMax: yearMax,
        priceMin: priceMin,
        priceMax: priceMax,
        location: location,
        condition: condition,
        bodyType: bodyType,
        transmission: transmission,
        driveType: driveType,
        engineType: engineType,
      );

  static Future<Map<String, dynamic>> getCar(String carId) =>
      _ApiServiceListings.getCar(carId);

  static Future<Map<String, dynamic>> createCar(
    Map<String, dynamic> carData,
  ) =>
      _ApiServiceListings.createCar(carData);

  static Future<Map<String, dynamic>> updateCar(
    String carId,
    Map<String, dynamic> carData,
  ) =>
      _ApiServiceListings.updateCar(carId, carData);

  static Future<Map<String, dynamic>> deleteCar(String carId) =>
      _ApiServiceListings.deleteCar(carId);

  static Future<Map<String, dynamic>> markListingSold(String carId) =>
      _ApiServiceListings.markListingSold(carId);

  static Future<Map<String, dynamic>> markListingActive(String carId) =>
      _ApiServiceListings.markListingActive(carId);

  static Future<Map<String, dynamic>> uploadCarImages(
    String carId,
    List<XFile> imageFiles, {
    bool blurPlates = false,
    String imageKind = 'listing',
  }) =>
      _ApiServiceListings.uploadCarImages(
        carId,
        imageFiles,
        blurPlates: blurPlates,
        imageKind: imageKind,
      );

  static Future<Map<String, dynamic>> attachCarImages(
    String carId,
    List<String> paths, {
    String kind = 'listing',
  }) =>
      _ApiServiceListings.attachCarImages(carId, paths, kind: kind);

  static Future<Map<String, dynamic>> signR2ImageUpload({
    String? filename,
    String? contentType,
  }) =>
      _ApiServiceListings.signR2ImageUpload(
        filename: filename,
        contentType: contentType,
      );

  static Future<void> uploadToSignedUpload(String uploadUrl, XFile file) =>
      _ApiServiceListings.uploadToSignedUpload(uploadUrl, file);

  static Future<Map<String, dynamic>> attachCarImageUrls(
    String carId,
    List<String> urls, {
    String kind = 'listing',
  }) =>
      _ApiServiceListings.attachCarImageUrls(carId, urls, kind: kind);

  static List<String>? getLastProcessedServerPaths() =>
      _ApiServiceListings.getLastProcessedServerPaths();

  static Future<Map<String, dynamic>> uploadCarVideos(
    String carId,
    List<XFile> videoFiles,
  ) =>
      _ApiServiceListings.uploadCarVideos(carId, videoFiles);

  static Future<Map<String, dynamic>> getFavorites({
    int page = 1,
    int perPage = 20,
  }) =>
      _ApiServiceListings.getFavorites(page: page, perPage: perPage);

  static Future<Map<String, dynamic>> toggleFavorite(String carId) =>
      _ApiServiceListings.toggleFavorite(carId);

  static Future<bool> isCarFavorited(String carId) =>
      _ApiServiceListings.isCarFavorited(carId);

  static Future<Map<String, dynamic>> getSavedSearches() =>
      _ApiServiceListings.getSavedSearches();

  static Future<Map<String, dynamic>> syncSavedSearches(
    List<Map<String, dynamic>> items,
  ) =>
      _ApiServiceListings.syncSavedSearches(items);

  static Future<Map<String, dynamic>> createSavedSearch({
    required String name,
    required Map<String, dynamic> filters,
    bool notify = true,
    bool autoSaved = false,
  }) =>
      _ApiServiceListings.createSavedSearch(
        name: name,
        filters: filters,
        notify: notify,
        autoSaved: autoSaved,
      );

  static Future<Map<String, dynamic>> updateSavedSearch(
    String searchId, {
    String? name,
    Map<String, dynamic>? filters,
    bool? notify,
    bool? autoSaved,
  }) =>
      _ApiServiceListings.updateSavedSearch(
        searchId,
        name: name,
        filters: filters,
        notify: notify,
        autoSaved: autoSaved,
      );

  static Future<void> deleteSavedSearch(String searchId) =>
      _ApiServiceListings.deleteSavedSearch(searchId);

  static Future<Map<String, dynamic>> getRecentlyViewed({
    int page = 1,
    int perPage = 20,
  }) =>
      _ApiServiceListings.getRecentlyViewed(page: page, perPage: perPage);

  static Future<void> recordListingView(String listingId) =>
      _ApiServiceListings.recordListingView(listingId);

  static Future<void> clearRecentlyViewed() =>
      _ApiServiceListings.clearRecentlyViewed();

  static Future<void> deleteRecentlyViewedListing(String listingId) =>
      _ApiServiceListings.deleteRecentlyViewedListing(listingId);

  static Future<Map<String, dynamic>> getMyListings({
    int page = 1,
    int perPage = 20,
  }) =>
      _ApiServiceListings.getMyListings(page: page, perPage: perPage);

  // Check if user is authenticated
  static bool get isAuthenticated =>
      _accessToken != null && _accessToken!.isNotEmpty;

  // Get current access token
  static String? get accessToken => _accessToken;

  // Chat HTTP + attachments (api/api_chat.dart)
  static Future<Map<String, dynamic>> sendChatMessageByConversation({
    required String conversationId,
    required String content,
    String? receiverId,
    Map<String, dynamic>? listingPreview,
    String? replyToMessageId,
  }) =>
      _ApiServiceChat.sendChatMessageByConversation(
        conversationId: conversationId,
        content: content,
        receiverId: receiverId,
        listingPreview: listingPreview,
        replyToMessageId: replyToMessageId,
      );

  static Future<int> getUnreadChatCount() =>
      _ApiServiceChat.getUnreadChatCount();

  static Future<Map<String, dynamic>> getChatMessagesByConversation(
    String conversationId, {
    int page = 1,
    int perPage = 50,
  }) =>
      _ApiServiceChat.getChatMessagesByConversation(
        conversationId,
        page: page,
        perPage: perPage,
      );

  static Future<Map<String, dynamic>> sendChatImage({
    required String conversationId,
    required XFile imageFile,
    String? receiverId,
    String? caption,
    String? replyToMessageId,
  }) =>
      _ApiServiceChat.sendChatImage(
        conversationId: conversationId,
        imageFile: imageFile,
        receiverId: receiverId,
        caption: caption,
        replyToMessageId: replyToMessageId,
      );

  static Future<Map<String, dynamic>> sendChatVideo({
    required String conversationId,
    required XFile videoFile,
    String? receiverId,
    String? caption,
    String? replyToMessageId,
  }) =>
      _ApiServiceChat.sendChatVideo(
        conversationId: conversationId,
        videoFile: videoFile,
        receiverId: receiverId,
        caption: caption,
        replyToMessageId: replyToMessageId,
      );

  static Future<Map<String, dynamic>> sendChatAudio({
    required String conversationId,
    required XFile audioFile,
    String? receiverId,
    String? replyToMessageId,
  }) =>
      _ApiServiceChat.sendChatAudio(
        conversationId: conversationId,
        audioFile: audioFile,
        receiverId: receiverId,
        replyToMessageId: replyToMessageId,
      );

  static Future<Map<String, dynamic>> sendChatMediaGroup({
    required String conversationId,
    required List<XFile> files,
    String? receiverId,
    String? caption,
    String? replyToMessageId,
    Map<String, dynamic>? listingPreview,
  }) =>
      _ApiServiceChat.sendChatMediaGroup(
        conversationId: conversationId,
        files: files,
        receiverId: receiverId,
        caption: caption,
        replyToMessageId: replyToMessageId,
        listingPreview: listingPreview,
      );

  static Future<Map<String, dynamic>> editChatMessage({
    required String messageId,
    required String content,
    List<Map<String, dynamic>>? attachments,
  }) =>
      _ApiServiceChat.editChatMessage(
        messageId: messageId,
        content: content,
        attachments: attachments,
      );

  static Future<Map<String, dynamic>> deleteChatMessage({
    required String messageId,
  }) =>
      _ApiServiceChat.deleteChatMessage(messageId: messageId);

  static Future<List<Map<String, dynamic>>> getChats() =>
      _ApiServiceChat.getChats();

  // Push, moderation, reports, blocks (api/api_admin.dart)
  static Future<void> registerPushToken(
    String token, {
    bool enabled = true,
  }) =>
      _ApiServiceAdmin.registerPushToken(token, enabled: enabled);

  static Future<Map<String, dynamic>> getPushStatus() =>
      _ApiServiceAdmin.getPushStatus();

  static Future<Map<String, dynamic>> sendTestPush() =>
      _ApiServiceAdmin.sendTestPush();

  static Future<void> blockUser(String userId) =>
      _ApiServiceAdmin.blockUser(userId);

  static Future<void> unblockUser(String userId) =>
      _ApiServiceAdmin.unblockUser(userId);

  static Future<void> reportUser(
    String userId, {
    required String reason,
    String? details,
  }) =>
      _ApiServiceAdmin.reportUser(
        userId,
        reason: reason,
        details: details,
      );

  static Future<void> reportListing(
    String listingId, {
    required String reason,
    String? details,
  }) =>
      _ApiServiceAdmin.reportListing(
        listingId,
        reason: reason,
        details: details,
      );

  static Future<Map<String, dynamic>> adminListReports({
    String status = 'pending',
    String type = 'all',
    int page = 1,
    int perPage = 20,
  }) =>
      _ApiServiceAdmin.adminListReports(
        status: status,
        type: type,
        page: page,
        perPage: perPage,
      );

  static Future<Map<String, dynamic>> adminUpdateUserReport(
    int reportId, {
    required String status,
    String? adminNotes,
  }) =>
      _ApiServiceAdmin.adminUpdateUserReport(
        reportId,
        status: status,
        adminNotes: adminNotes,
      );

  static Future<Map<String, dynamic>> adminUpdateListingReport(
    int reportId, {
    required String status,
    String? adminNotes,
  }) =>
      _ApiServiceAdmin.adminUpdateListingReport(
        reportId,
        status: status,
        adminNotes: adminNotes,
      );

  static Future<List<String>> getBlockedUsers() =>
      _ApiServiceAdmin.getBlockedUsers();
}