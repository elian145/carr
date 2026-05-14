import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../shared/listings/listing_share_urls.dart';

/// Handles app deep links (e.g. carzo://auth/reset-password?token=xxx).
/// Call [init] with the app's [NavigatorState] key after [MaterialApp] is built.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService _instance = DeepLinkService._();
  static DeepLinkService get instance => _instance;

  final AppLinks _appLinks = AppLinks();
  GlobalKey<NavigatorState>? _navigatorKey;
  StreamSubscription<Uri>? _linkSub;

  /// Same URI can arrive from both [AppLinks.getInitialLink] and [AppLinks.uriLinkStream]
  /// on cold start; ignore repeats within this window so we do not push twice.
  static const Duration _kDuplicateLinkWindow = Duration(seconds: 3);
  String? _lastScheduledUriString;
  DateTime? _lastScheduledAt;
  String? _lastCompletedUriString;
  DateTime? _lastCompletedAt;

  /// Initialize with the [MaterialApp] navigator key. Call once after [MaterialApp] is built.
  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _linkSub?.cancel();
    _linkSub = null;
    _lastScheduledUriString = null;
    _lastScheduledAt = null;
    _lastCompletedUriString = null;
    _lastCompletedAt = null;

    // Consume the launch URI first, then subscribe — reduces duplicate delivery on some platforms.
    _appLinks.getInitialLink().then((Uri? initial) {
      if (_navigatorKey != navigatorKey) return;
      _linkSub = _appLinks.uriLinkStream.listen(_handleLink);
      if (initial != null) _handleLink(initial);
    });
  }

  /// True if we already started handling this URI recently (drops parallel duplicate deliveries).
  bool _isDuplicateSchedule(Uri uri) {
    final now = DateTime.now();
    final s = uri.toString();
    if (_lastScheduledUriString == s &&
        _lastScheduledAt != null &&
        now.difference(_lastScheduledAt!) < _kDuplicateLinkWindow) {
      return true;
    }
    _lastScheduledUriString = s;
    _lastScheduledAt = now;
    return false;
  }

  /// True if we already navigated for this URI recently.
  bool _isDuplicateCompleted(Uri uri) {
    final now = DateTime.now();
    final s = uri.toString();
    return _lastCompletedUriString == s &&
        _lastCompletedAt != null &&
        now.difference(_lastCompletedAt!) < _kDuplicateLinkWindow;
  }

  void _markCompleted(Uri uri) {
    _lastCompletedUriString = uri.toString();
    _lastCompletedAt = DateTime.now();
  }

  bool _isCarzo(Uri uri) => uri.scheme == 'carzo';

  bool _isHttpsListing(Uri uri) => listingIdFromSharedHttpsUri(uri) != null;

  /// URIs this service knows how to open inside the app.
  bool _targetsThisApp(Uri uri) {
    if (_isCarzo(uri)) return true;
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      return _isHttpsListing(uri);
    }
    return false;
  }

  void _handleLink(Uri uri) {
    if (_navigatorKey == null) return;
    if (!_targetsThisApp(uri)) return;
    if (_isDuplicateSchedule(uri)) return;

    void tick(int frame) {
      final key = _navigatorKey;
      if (key?.currentContext == null || key?.currentState == null) {
        // Cold start / Universal Link: navigator may not exist for the first few frames.
        if (frame < 360) {
          WidgetsBinding.instance.addPostFrameCallback((_) => tick(frame + 1));
        }
        return;
      }
      if (_isDuplicateCompleted(uri)) return;
      final nav = key!.currentState!;
      final handled = _performNavigation(uri, nav);
      if (handled) _markCompleted(uri);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tick(0));
  }

  /// Returns true if this URI was recognized and a route was pushed.
  bool _performNavigation(Uri uri, NavigatorState nav) {
    final path = uri.path;
    final token = uri.queryParameters['token']?.trim();
    if (path.endsWith('reset-password') && token != null && token.isNotEmpty) {
      nav.pushNamed('/reset-password', arguments: <String, String>{'token': token});
      return true;
    }
    if (path.endsWith('verify-email') && token != null && token.isNotEmpty) {
      nav.pushNamed('/verify-email', arguments: <String, dynamic>{'token': token});
      return true;
    }
    if (path.endsWith('confirm-signup') && token != null && token.isNotEmpty) {
      nav.pushNamed(
        '/verify-email',
        arguments: <String, dynamic>{'token': token, 'mode': 'signup'},
      );
      return true;
    }
    // https://<api-or-share-host>/listing/<id> (Universal / App Links) → in-app listing
    final httpsListingId = listingIdFromSharedHttpsUri(uri);
    if (httpsListingId != null) {
      nav.pushNamed(
        '/car_detail',
        arguments: <String, dynamic>{'carId': httpsListingId},
      );
      return true;
    }
    // carzo://listing?id=<public_id>
    if (uri.scheme == 'carzo' && uri.host == 'listing') {
      final carId = (uri.queryParameters['id'] ??
              uri.queryParameters['carId'] ??
              '')
          .trim();
      if (carId.isEmpty) return false;
      nav.pushNamed(
        '/car_detail',
        arguments: <String, dynamic>{'carId': carId},
      );
      return true;
    }
    return false;
  }

  void dispose() {
    _linkSub?.cancel();
    _linkSub = null;
    _navigatorKey = null;
    _lastScheduledUriString = null;
    _lastScheduledAt = null;
    _lastCompletedUriString = null;
    _lastCompletedAt = null;
  }
}
