import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

/// Handles app deep links (e.g. carzo://auth/reset-password?token=xxx).
/// Call [init] with the app's [NavigatorState] key after [MaterialApp] is built.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService _instance = DeepLinkService._();
  static DeepLinkService get instance => _instance;

  final AppLinks _appLinks = AppLinks();
  GlobalKey<NavigatorState>? _navigatorKey;
  StreamSubscription<Uri>? _linkSub;

  /// Initialize with the [MaterialApp] navigator key. Call once after app is built.
  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _linkSub?.cancel();
    _linkSub = _appLinks.uriLinkStream.listen(_handleLink);
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleLink(uri);
    });
  }

  void _handleLink(Uri uri) {
    final key = _navigatorKey;
    if (key?.currentContext == null) return;
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
    }
  }

  void dispose() {
    _linkSub?.cancel();
    _linkSub = null;
    _navigatorKey = null;
  }
}
