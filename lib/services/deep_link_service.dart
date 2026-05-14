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
  String? _lastHandledUriString;
  DateTime? _lastHandledAt;

  /// Initialize with the [MaterialApp] navigator key. Call once after [MaterialApp] is built.
  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _linkSub?.cancel();
    _linkSub = null;
    _lastHandledUriString = null;
    _lastHandledAt = null;

    // Consume the launch URI first, then subscribe — reduces duplicate delivery on some platforms.
    _appLinks.getInitialLink().then((Uri? initial) {
      if (_navigatorKey != navigatorKey) return;
      _linkSub = _appLinks.uriLinkStream.listen(_handleLink);
      if (initial != null) _handleLink(initial);
    });
  }

  bool _isDuplicateDelivery(Uri uri) {
    final now = DateTime.now();
    final s = uri.toString();
    if (_lastHandledUriString == s &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < _kDuplicateLinkWindow) {
      return true;
    }
    _lastHandledUriString = s;
    _lastHandledAt = now;
    return false;
  }

  void _handleLink(Uri uri) {
    final key = _navigatorKey;
    if (key?.currentContext == null) return;
    if (_isDuplicateDelivery(uri)) return;
    // carzo://auth/reset-password?token=xxx
    final path = uri.path;
    final token = uri.queryParameters['token']?.trim();
    if (path.endsWith('reset-password') && token != null && token.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (key?.currentContext != null && key!.currentState != null) {
          key.currentState!.pushNamed('/reset-password', arguments: <String, String>{'token': token});
        }
      });
      return;
    }
    if (path.endsWith('verify-email') && token != null && token.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (key?.currentContext != null && key!.currentState != null) {
          key.currentState!.pushNamed('/verify-email', arguments: <String, dynamic>{'token': token});
        }
      });
      return;
    }
    if (path.endsWith('confirm-signup') && token != null && token.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (key?.currentContext != null && key!.currentState != null) {
          key.currentState!.pushNamed(
            '/verify-email',
            arguments: <String, dynamic>{'token': token, 'mode': 'signup'},
          );
        }
      });
      return;
    }
    // https://<api-or-share-host>/listing/<id> (Universal / App Links)
    final httpsListingId = listingIdFromSharedHttpsUri(uri);
    if (httpsListingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (key?.currentContext != null && key!.currentState != null) {
          key.currentState!.pushNamed(
            '/car_detail',
            arguments: <String, dynamic>{'carId': httpsListingId},
          );
        }
      });
      return;
    }
    // carzo://listing?id=<public_id>
    if (uri.scheme == 'carzo' && uri.host == 'listing') {
      final carId = (uri.queryParameters['id'] ??
              uri.queryParameters['carId'] ??
              '')
          .trim();
      if (carId.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (key?.currentContext != null && key!.currentState != null) {
          key.currentState!.pushNamed(
            '/car_detail',
            arguments: <String, dynamic>{'carId': carId},
          );
        }
      });
      return;
    }
  }

  void dispose() {
    _linkSub?.cancel();
    _linkSub = null;
    _navigatorKey = null;
    _lastHandledUriString = null;
    _lastHandledAt = null;
  }
}
