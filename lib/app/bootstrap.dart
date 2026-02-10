import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../state/locale_controller.dart';

// Firebase is optional for sideload builds.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Sideload build flag to disable services that require entitlements on iOS
const bool kSideloadBuild = bool.fromEnvironment(
  'SIDELOAD_BUILD',
  defaultValue: false,
);

Future<void> bootstrapAndRun(Widget app) async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) async {
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.setString('last_startup_error', details.exceptionAsString());
        } catch (_) {}
        FlutterError.presentError(details);
      };

      // Minimal pre-run init only (fast): load tokens if available.
      try {
        await ApiService.initializeTokens();
      } catch (_) {}

      runApp(app);

      // Defer heavy initializations to post-frame to avoid blocking first paint.
      Future.microtask(() async {
        if (!(kSideloadBuild && Platform.isIOS)) {
          try {
            await Firebase.initializeApp();
          } catch (_) {}
          try {
            await _initPushToken();
          } catch (_) {}
        }
        try {
          await LocaleController.loadSavedLocale();
        } catch (_) {}
        try {
          await AuthService().initialize();
        } catch (_) {}
      });
    },
    (error, stack) async {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('last_startup_error', error.toString());
      } catch (_) {}
      if (kDebugMode) {
        // ignore: avoid_print
        print('bootstrap error: $error');
      }
    },
  );
}

Future<void> _initPushToken() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final enabled = sp.getBool('push_enabled') ?? true;
    if (!enabled) return;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await sp.setString('push_token', token);
      }
    }
  } catch (_) {}
}
