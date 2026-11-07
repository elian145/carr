// F-45: Android must declare every carzo:// host the app handles, and a
// local notification tapped while the app was killed must be routed.
import 'dart:io';

import 'package:car_listing_app/services/deep_link_navigation.dart';
import 'package:car_listing_app/services/push_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationAppLaunchDetails _details({
  required bool launched,
  String? payload,
  bool withResponse = true,
}) => NotificationAppLaunchDetails(
  launched,
  notificationResponse: withResponse
      ? NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: payload,
        )
      : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AndroidManifest carzo:// hosts', () {
    late String manifest;
    setUpAll(() {
      manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
    });

    bool declares(String host) => RegExp(
      'android:scheme="carzo"\\s+android:host="$host"',
    ).hasMatch(manifest);

    test('declares saved-searches (handled by deep_link_navigation)', () {
      expect(
        resolveDeepLinkTarget(Uri.parse('carzo://saved-searches'))?.route,
        '/saved-searches',
        reason: 'precondition: the Dart handler supports this link',
      );
      expect(declares('saved-searches'), isTrue);
    });

    test('negative control: previously declared hosts are still present', () {
      expect(declares('auth'), isTrue);
      expect(declares('listing'), isTrue);
      expect(declares('not-a-real-host'), isFalse);
    });
  });

  group('cold-start local notification launch', () {
    final navKey = GlobalKey<NavigatorState>();
    final pushed = <String>[];
    final args = <Object?>[];

    Widget app() => MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('home')),
      onGenerateRoute: (settings) {
        pushed.add(settings.name ?? '');
        args.add(settings.arguments);
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('route ${settings.name}')),
        );
      },
    );

    setUp(() {
      pushed.clear();
      args.clear();
    });

    testWidgets('launch by notification opens its destination', (tester) async {
      await tester.pumpWidget(app());
      PushNotificationService.attachNavigator(navKey);
      PushNotificationService.handleLocalLaunchDetails(
        _details(
          launched: true,
          payload: '{"type":"chat_message","car_id":"c9","sender_id":"u2"}',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(pushed, contains('/chat/conversation'));
      expect((args.last as Map)['carId'], 'c9');
    });

    testWidgets('negative control: normal launch / no response => nothing',
        (tester) async {
      await tester.pumpWidget(app());
      PushNotificationService.attachNavigator(navKey);
      PushNotificationService.handleLocalLaunchDetails(null);
      PushNotificationService.handleLocalLaunchDetails(
        _details(launched: false, payload: '{"type":"chat_message"}'),
      );
      PushNotificationService.handleLocalLaunchDetails(
        _details(launched: true, withResponse: false),
      );
      await tester.pump();
      await tester.pump();
      expect(pushed, isEmpty);
    });
  });
}
