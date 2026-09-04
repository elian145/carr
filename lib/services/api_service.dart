import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import '../shared/auth/token_store.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/phone/phone_normalizer.dart';
import 'api_exception.dart';
import '../shared/debug/app_log.dart';
import '../shared/debug/expected_client_noise.dart';

export 'api_exception.dart';

part 'api/api_http.dart';
part 'api/api_auth.dart';
part 'api/api_listings.dart';
part 'api/api_chat.dart';
part 'api/api_admin.dart';

class ApiService {
  /// Warm path: typical Render response when the service is already awake.
  static const Duration _warmTimeout = Duration(seconds: 20);

  /// Cold path: first request / long idle — Render free tier can take ~30–60s.
  static const Duration _coldTimeout = Duration(seconds: 55);

  /// After this idle gap, treat the next request as a cold start.
  static const Duration _idleForColdStart = Duration(minutes: 12);

  static const Duration _uploadTimeout = Duration(seconds: 180);

  /// Soft TTL for in-memory GET stale-while-revalidate fallbacks.
  static const Duration _getSwrTtl = Duration(minutes: 5);

  static DateTime? _lastSuccessfulRequestAt;
  static final Map<String, _ApiGetCacheEntry> _getResponseCache =
      <String, _ApiGetCacheEntry>{};

  /// Adaptive request timeout (warm vs cold-start).
  static Duration requestTimeout() {
    final last = _lastSuccessfulRequestAt;
    if (last == null) return _coldTimeout;
    if (DateTime.now().difference(last) >= _idleForColdStart) {
      return _coldTimeout;
    }
    return _warmTimeout;
  }

  /// Back-compat alias used by API parts.
  static Duration get _defaultTimeout => requestTimeout();

  static void _markRequestSuccess() {
    _lastSuccessfulRequestAt = DateTime.now();
  }

  @visibleForTesting
  static void debugResetTimeoutPolicy() {
    _lastSuccessfulRequestAt = null;
    _getResponseCache.clear();
  }

  @visibleForTesting
  static void debugMarkRequestSuccessAt(DateTime at) {
    _lastSuccessfulRequestAt = at;
  }

  static String get baseUrl {
    return apiBaseApi();
  }

  static String? _accessToken;
  static String? _refreshToken;

  /// Optional hook when [clearTokens] runs outside [AuthService.logout].
  static void Function()? onTokensCleared;

  static http.Client _productionHttpClient = http.Client();
  static http.Client? _testHttpClient;

  /// Replace the shared [http.Client] after iOS reclaims keep-alive sockets.
  static void recycleProductionHttpClient() {
    if (_testHttpClient != null) return;
    final previous = _productionHttpClient;
    _productionHttpClient = http.Client();
    try {
      previous.close();
    } catch (_) {}
  }

  /// Widget/integration tests: route API calls through [FakeApiServer] mock client.
  @visibleForTesting
  static set testHttpClient(http.Client? client) {
    _testHttpClient = client;
  }

  @visibleForTesting
  static http.Client? get boundTestHttpClient => _testHttpClient;

  /// Whether tests have bound an in-memory HTTP client (skip real-time transports).
  static bool get isTestHttpClientBound => _testHttpClient != null;

  /// Shared GET helper for services that are not yet on [ApiService] endpoints.
  ///
  /// Uses the adaptive warm/cold timeout unless [timeout] is passed.
  static Future<http.Response> getHttp(
    Uri uri, {
    Duration? timeout,
    Map<String, String>? headers,
  }) {
    return _ApiServiceHttp._getWithAdaptiveTimeout(
      uri,
      timeout: timeout,
      headers: headers,
    );
  }

  static http.Client get _httpClient =>
      _testHttpClient ?? _productionHttpClient;

  // HTTP + token core (api/api_http.dart)
  static Future<void> initializeTokens() => _ApiServiceHttp.initializeTokens();

  static Future<void> _saveAccessToken(String accessToken) =>
      _ApiServiceHttp._saveAccessToken(accessToken);

  static Future<void> _saveRefreshToken(String? refreshToken) =>
      _ApiServiceHttp._saveRefreshToken(refreshToken);

  static Future<void> setAccessToken(String? token) =>
      _ApiServiceHttp.setAccessToken(token);

  static Future<void> setRefreshToken(String? token) =>
      _ApiServiceHttp.setRefreshToken(token);

  static Future<void> setTokens({String? accessToken, String? refreshToken}) =>
      _ApiServiceHttp.setTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

  static Future<void> clearTokens() => _ApiServiceHttp.clearTokens();

  static Future<void> _ensureTokenLoaded() =>
      _ApiServiceHttp._ensureTokenLoaded();

  static Map<String, String> _getHeaders({bool includeAuth = true}) =>
      _ApiServiceHttp._getHeaders(includeAuth: includeAuth);

  static Map<String, dynamic> _handleResponse(http.Response response) =>
      _ApiServiceHttp._handleResponse(response);

  static Future<Map<String, dynamic>> _sendAuthenticatedMultipart(
    Future<http.MultipartRequest> Function() buildRequest,
  ) => _ApiServiceHttp._sendAuthenticatedMultipart(buildRequest);

  static Future<bool> _refreshAccessToken() =>
      _ApiServiceHttp._refreshAccessToken();

  static Future<Map<String, dynamic>> _makeAuthenticatedRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) => _ApiServiceHttp._makeAuthenticatedRequest(
    method,
    endpoint,
    body: body,
    headers: headers,
  );

  static Future<Map<String, dynamic>> makeAuthenticatedRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) =>
      _makeAuthenticatedRequest(method, endpoint, body: body, headers: headers);

  static Future<List<Map<String, dynamic>>> _makeAuthenticatedListRequest(
    String endpoint,
  ) => _ApiServiceHttp.makeAuthenticatedListRequest(endpoint);

  static Future<List<Map<String, dynamic>>> getAuthenticatedJsonList(
    String endpoint,
  ) => _makeAuthenticatedListRequest(endpoint);

  // Authentication & profile (api/api_auth.dart)
  static Future<Map<String, dynamic>> getDealerApplication() =>
      _ApiServiceAuth.getDealerApplication();

  static Future<Map<String, dynamic>> saveDealerApplication(
    Map<String, dynamic> applicationData,
  ) => _ApiServiceAuth.saveDealerApplication(applicationData);

  static Future<Map<String, dynamic>> getUserNotifications({
    bool unreadOnly = false,
    String? type,
    int page = 1,
    int perPage = 20,
  }) => _ApiServiceAuth.getUserNotifications(
    unreadOnly: unreadOnly,
    type: type,
    page: page,
    perPage: perPage,
  );

  static Future<Map<String, dynamic>> markUserNotificationRead(
    String notificationId,
  ) => _ApiServiceAuth.markUserNotificationRead(notificationId);

  static Future<Map<String, dynamic>> login(
    String emailOrPhone,
    String password,
  ) => _ApiServiceAuth.login(emailOrPhone, password);

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
    bool createIfMissing = true,
    String? purpose,
  }) => _ApiServiceAuth.phoneStart(
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
    createIfMissing: createIfMissing,
    purpose: purpose,
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
    bool createIfMissing = true,
    String? purpose,
  }) => _ApiServiceAuth.phoneVerify(
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
    createIfMissing: createIfMissing,
    purpose: purpose,
  );

  static Future<void> logout() => _ApiServiceAuth.logout();

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _ApiServiceAuth.changePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  static Future<Map<String, dynamic>> sendDeleteAccountCode() =>
      _ApiServiceAuth.sendDeleteAccountCode();

  static Future<Map<String, dynamic>> deleteAccount({
    String? password,
    String? code,
  }) => _ApiServiceAuth.deleteAccount(password: password, code: code);

  static Future<Map<String, dynamic>> forgotPassword(
    String value, {
    bool isPhone = true,
  }) => _ApiServiceAuth.forgotPassword(value, isPhone: true);

  static Future<Map<String, dynamic>> resetPassword(
    String token,
    String newPassword,
  ) => _ApiServiceAuth.resetPassword(token, newPassword);

  static Future<Map<String, dynamic>> verifyEmail(String token) =>
      _ApiServiceAuth.verifyEmail(token);

  static Future<Map<String, dynamic>> sendEmailVerification() =>
      _ApiServiceAuth.sendEmailVerification();

  static Future<Map<String, dynamic>> sendPhoneVerificationCode(
    String phoneNumber,
  ) => _ApiServiceAuth.sendPhoneVerificationCode(phoneNumber);

  static Future<Map<String, dynamic>> sendOtpLegacy({
    required String phone,
    bool isDealer = false,
    String? dealershipName,
    String? dealershipPhone,
    String? dealershipLocation,
  }) => _ApiServiceAuth.sendOtpLegacy(
    phone: phone,
    isDealer: isDealer,
    dealershipName: dealershipName,
    dealershipPhone: dealershipPhone,
    dealershipLocation: dealershipLocation,
  );

  static Future<Map<String, dynamic>> signupLegacy(Map<String, dynamic> body) =>
      _ApiServiceAuth.signupLegacy(body);

  static Future<Map<String, dynamic>> verifyPhone(
    String phoneNumber,
    String code,
  ) => _ApiServiceAuth.verifyPhone(phoneNumber, code);

  static Future<Map<String, dynamic>> getProfile() =>
      _ApiServiceAuth.getProfile();

  static Future<Map<String, dynamic>> getDealerProfile(String dealerPublicId) =>
      _ApiServiceAuth.getDealerProfile(dealerPublicId);

  static Future<Map<String, dynamic>> searchDealers({
    String? q,
    int page = 1,
    int perPage = 20,
  }) => _ApiServiceAuth.searchDealers(q: q, page: page, perPage: perPage);

  static Future<Map<String, dynamic>> updateDealerProfile(
    Map<String, dynamic> dealerData,
  ) => _ApiServiceAuth.updateDealerProfile(dealerData);

  static Future<Map<String, dynamic>> sendDealerPhoneVerification(
    String phoneNumber,
  ) => _ApiServiceAuth.sendDealerPhoneVerification(phoneNumber);

  static Future<Map<String, dynamic>> verifyDealerPhone(
    String phoneNumber,
    String code,
  ) => _ApiServiceAuth.verifyDealerPhone(phoneNumber, code);

  static Future<Map<String, dynamic>> sendDealerEmailVerification(
    String email,
  ) => _ApiServiceAuth.sendDealerEmailVerification(email);

  static Future<Map<String, dynamic>> verifyDealerEmail(
    String email,
    String code,
  ) => _ApiServiceAuth.verifyDealerEmail(email, code);

  static Future<Map<String, dynamic>> sendAccountEmailChangeCode(
    String email,
  ) => _ApiServiceAuth.sendAccountEmailChangeCode(email);

  static Future<Map<String, dynamic>> verifyAccountEmailChange(
    String email,
    String code,
  ) => _ApiServiceAuth.verifyAccountEmailChange(email, code);

  static Future<Map<String, dynamic>> sendContactPhoneVerification(
    String phoneNumber,
  ) => _ApiServiceAuth.sendContactPhoneVerification(phoneNumber);

  static Future<Map<String, dynamic>> verifyContactPhone(
    String phoneNumber,
    String code,
  ) => _ApiServiceAuth.verifyContactPhone(phoneNumber, code);

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profileData,
  ) => _ApiServiceAuth.updateProfile(profileData);

  static Future<Map<String, dynamic>> uploadProfilePicture(XFile imageFile) =>
      _ApiServiceAuth.uploadProfilePicture(imageFile);

  static Future<Map<String, dynamic>> uploadDealerCoverPicture(
    XFile imageFile,
  ) => _ApiServiceAuth.uploadDealerCoverPicture(imageFile);

  static Future<Map<String, dynamic>> uploadDealerVerificationPhoto(
    XFile imageFile,
  ) => _ApiServiceAuth.uploadDealerVerificationPhoto(imageFile);

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
  }) => _ApiServiceListings.getCars(
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

  static Future<Map<String, dynamic>?> getCarDetail(String carId) =>
      _ApiServiceListings.getCarDetail(carId);

  static Future<List<String>> getCarContactPhones(String carId) =>
      _ApiServiceListings.getCarContactPhones(carId);

  static Future<Map<String, dynamic>> createCar(
    Map<String, dynamic> carData, {
    String? idempotencyKey,
  }) => _ApiServiceListings.createCar(carData, idempotencyKey: idempotencyKey);

  static Future<Map<String, dynamic>> updateCar(
    String carId,
    Map<String, dynamic> carData,
  ) => _ApiServiceListings.updateCar(carId, carData);

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
  }) => _ApiServiceListings.uploadCarImages(
    carId,
    imageFiles,
    blurPlates: blurPlates,
    imageKind: imageKind,
  );

  static Future<Map<String, dynamic>> attachCarImages(
    String carId,
    List<String> paths, {
    String kind = 'listing',
  }) => _ApiServiceListings.attachCarImages(carId, paths, kind: kind);

  static Future<Map<String, dynamic>> setCarPrimaryImage(
    String carId,
    String imageUrl,
  ) => _ApiServiceListings.setCarPrimaryImage(carId, imageUrl);

  static Future<Map<String, dynamic>> updateCarImageLayout(
    String carId,
    List<Map<String, dynamic>> images,
  ) => _ApiServiceListings.updateCarImageLayout(carId, images);

  static Future<Map<String, dynamic>> signR2ImageUpload({
    required int contentLength,
    String? filename,
    String? contentType,
  }) => _ApiServiceListings.signR2ImageUpload(
    contentLength: contentLength,
    filename: filename,
    contentType: contentType,
  );

  static Future<void> uploadToSignedUpload(String uploadUrl, XFile file) =>
      _ApiServiceListings.uploadToSignedUpload(uploadUrl, file);

  static Future<Map<String, dynamic>> attachCarImageUrls(
    String carId,
    List<String> urls, {
    String kind = 'listing',
  }) => _ApiServiceListings.attachCarImageUrls(carId, urls, kind: kind);

  static List<String>? getLastProcessedServerPaths() =>
      _ApiServiceListings.getLastProcessedServerPaths();

  static Future<Map<String, dynamic>> uploadCarVideos(
    String carId,
    List<XFile> videoFiles, {
    Future<http.MultipartFile> Function(XFile file)? multipartFileBuilder,
  }) => _ApiServiceListings.uploadCarVideos(
    carId,
    videoFiles,
    multipartFileBuilder: multipartFileBuilder,
  );

  static Future<Map<String, dynamic>> getFavorites({
    int page = 1,
    int perPage = 20,
  }) => _ApiServiceListings.getFavorites(page: page, perPage: perPage);

  static Future<Map<String, dynamic>> toggleFavorite(String carId) =>
      _ApiServiceListings.toggleFavorite(carId);

  static Future<bool> isCarFavorited(String carId) =>
      _ApiServiceListings.isCarFavorited(carId);

  static Future<Map<String, dynamic>> getSavedSearches() =>
      _ApiServiceListings.getSavedSearches();

  static Future<Map<String, dynamic>> syncSavedSearches(
    List<Map<String, dynamic>> items,
  ) => _ApiServiceListings.syncSavedSearches(items);

  static Future<Map<String, dynamic>> createSavedSearch({
    required String name,
    required Map<String, dynamic> filters,
    bool notify = true,
    bool autoSaved = false,
  }) => _ApiServiceListings.createSavedSearch(
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
  }) => _ApiServiceListings.updateSavedSearch(
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
  }) => _ApiServiceListings.getRecentlyViewed(page: page, perPage: perPage);

  static Future<void> recordListingView(String listingId) =>
      _ApiServiceListings.recordListingView(listingId);

  static Future<void> clearRecentlyViewed() =>
      _ApiServiceListings.clearRecentlyViewed();

  static Future<void> deleteRecentlyViewedListing(String listingId) =>
      _ApiServiceListings.deleteRecentlyViewedListing(listingId);

  static Future<Map<String, dynamic>> getMyListings({
    int page = 1,
    int perPage = 20,
    String? status,
  }) => _ApiServiceListings.getMyListings(
    page: page,
    perPage: perPage,
    status: status,
  );

  static Future<List<Map<String, dynamic>>> getMyListingsCompat() =>
      _ApiServiceListings.getMyListingsCompat();

  static Future<http.Response> getCarsRaw(
    Map<String, String> queryParams, {
    Duration? timeout,
    Map<String, String>? extraHeaders,
  }) => _ApiServiceListings.getCarsRaw(
    queryParams,
    timeout: timeout,
    extraHeaders: extraHeaders,
  );

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
  }) => _ApiServiceChat.sendChatMessageByConversation(
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
  }) => _ApiServiceChat.getChatMessagesByConversation(
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
  }) => _ApiServiceChat.sendChatImage(
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
  }) => _ApiServiceChat.sendChatVideo(
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
  }) => _ApiServiceChat.sendChatAudio(
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
  }) => _ApiServiceChat.sendChatMediaGroup(
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
  }) => _ApiServiceChat.editChatMessage(
    messageId: messageId,
    content: content,
    attachments: attachments,
  );

  static Future<Map<String, dynamic>> deleteChatMessage({
    required String messageId,
  }) => _ApiServiceChat.deleteChatMessage(messageId: messageId);

  static Future<List<Map<String, dynamic>>> getChats() =>
      _ApiServiceChat.getChats();

  // Push, moderation, reports, blocks (api/api_admin.dart)
  static Future<void> registerPushToken(String token, {bool enabled = true}) =>
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
  }) => _ApiServiceAdmin.reportUser(userId, reason: reason, details: details);

  static Future<void> reportListing(
    String listingId, {
    required String reason,
    String? details,
  }) => _ApiServiceAdmin.reportListing(
    listingId,
    reason: reason,
    details: details,
  );

  static Future<List<String>> getBlockedUsers() =>
      _ApiServiceAdmin.getBlockedUsers();
}

class _ApiGetCacheEntry {
  _ApiGetCacheEntry(this.response, this.savedAt);

  final http.Response response;
  final DateTime savedAt;

  bool get isUsable =>
      DateTime.now().difference(savedAt) <= ApiService._getSwrTtl;
}
