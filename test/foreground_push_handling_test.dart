// Regression tests for foreground push handling in [PushNotificationService]:
//
//   * iOS must NOT also present a foreground FCM push natively (the app shows
//     its own local notification) -- the duplicate-banner bug;
//   * Android keeps working unchanged (no iOS-only setup);
//   * a foreground push produces EXACTLY ONE local notification, also when the
//     foreground listener is attached more than once;
//   * the banner is skipped only for the actively viewed conversation, and
//     shown for other screens, other conversations, inactive/paused app state,
//     covered conversations, missing ids and unrelated notification types;
//   * notification taps / deep links still resolve as before.
//
// No Firebase/native plugins: the real Firebase platform class is used with its
// native calls injected.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/foreground_notification_policy.dart';
import 'package:car_listing_app/services/push_notification_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/debug/app_log.dart';

import 'support/test_jwt.dart';

RemoteMessage chatPush({
  String car = 'car_1',
  String sender = 'peer_1',
  String id = 'm1',
}) => RemoteMessage(
  messageId: id,
  notification: RemoteNotification(title: 'New message', body: 'hi'),
  data: {'type': 'chat_message', 'car_id': car, 'sender_id': sender},
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<RemoteMessage> incoming;
  late List<RemoteMessage> shown;
  late List<({bool alert, bool badge, bool sound})> presentationCalls;
  late ChatConversationPresence registry;

  PushMessagingPlatform buildPlatform({required bool isIOS}) =>
      PushNotificationService.debugFirebasePlatform(
        isIOS: isIOS,
        setForegroundPresentation:
            ({required alert, required badge, required sound}) async {
              presentationCalls.add((alert: alert, badge: badge, sound: sound));
            },
        onMessage: incoming.stream,
      );

  Future<void> flush() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Registers an open conversation screen in the app-wide registry.
  ChatConversationPresenceHandle openConversation({
    String car = 'car_1',
    String? peer = 'peer_1',
    bool Function()? visible,
    bool Function()? live,
    String? owner = 'me',
  }) => ChatConversationPresence.instance.register(
    carId: () => car,
    peerId: () => peer,
    ownerId: () => owner,
    isVisible: visible ?? () => true,
    isRealtimeLive: live ?? () => true,
  );

  Future<void> signInAs(String id) async {
    await ApiService.setTokens(
      accessToken: testJwt(id, nonce: 'fg'),
      refreshToken: testJwt(id, type: 'refresh'),
    );
  }

  setUp(() async {
    debugLogNonFatalOverride = (error, stackTrace, context) {};
    TokenStore.testMode = true;
    TokenStore.resetForTests();
    AuthService().resetTestSession();
    await ApiService.clearTokens();
    await signInAs('me');
    PushNotificationService.debugResetForTests();
    ChatConversationPresence.instance.debugClear();
    registry = ChatConversationPresence.instance;
    incoming = StreamController<RemoteMessage>.broadcast();
    shown = [];
    presentationCalls = [];
    PushNotificationService.debugLocalNotificationPresenter = (m) async {
      shown.add(m);
    };
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDown(() async {
    await incoming.close();
    registry.debugClear();
    PushNotificationService.debugResetForTests();
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    TokenStore.resetForTests();
    TokenStore.testMode = false;
    debugLogNonFatalOverride = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  group('iOS duplicate foreground notification', () {
    test('iOS: native foreground presentation is switched fully OFF', () async {
      await buildPlatform(isIOS: true).prepareForToken();

      expect(presentationCalls, hasLength(1));
      expect(presentationCalls.single.alert, isFalse);
      expect(presentationCalls.single.badge, isFalse);
      expect(presentationCalls.single.sound, isFalse);
    });

    test('Android: no iOS presentation setup is performed', () async {
      await buildPlatform(isIOS: false).prepareForToken();
      expect(presentationCalls, isEmpty);
    });

    for (final ios in [true, false]) {
      test('${ios ? 'iOS' : 'Android'}: one foreground push => exactly ONE '
          'local notification', () async {
        final platform = buildPlatform(isIOS: ios);
        await platform.prepareForToken();
        platform.attachForegroundDisplay();

        incoming.add(chatPush());
        await flush();

        expect(shown, hasLength(1));
        expect(shown.single.messageId, 'm1');
      });
    }

    test('attaching the foreground listener twice never doubles the banner',
        () async {
      final platform = buildPlatform(isIOS: true);
      platform.attachForegroundDisplay();
      platform.attachForegroundDisplay();

      incoming.add(chatPush());
      await flush();

      expect(shown, hasLength(1));
    });

    test('each distinct push gets its own single banner; a failing presenter '
        'does not kill the listener', () async {
      final platform = buildPlatform(isIOS: true);
      platform.attachForegroundDisplay();
      var first = true;
      PushNotificationService.debugLocalNotificationPresenter = (m) async {
        if (first) {
          first = false;
          throw StateError('plugin failure');
        }
        shown.add(m);
      };

      incoming.add(chatPush(id: 'm1'));
      incoming.add(chatPush(id: 'm2'));
      incoming.add(chatPush(id: 'm3'));
      await flush();

      expect(shown.map((m) => m.messageId), ['m2', 'm3']);
    });
  });

  group('conversation suppression (Android and iOS foreground path)', () {
    for (final ios in [true, false]) {
      final os = ios ? 'iOS' : 'Android';

      test('$os: actively viewed conversation => no banner', () async {
        buildPlatform(isIOS: ios).attachForegroundDisplay();
        openConversation();

        incoming.add(chatPush());
        await flush();

        expect(shown, isEmpty);
      });

      test('$os: another screen (no conversation open) => exactly one banner',
          () async {
        buildPlatform(isIOS: ios).attachForegroundDisplay();

        incoming.add(chatPush());
        await flush();

        expect(shown, hasLength(1));
      });

      test('$os: a different conversation is open => one banner', () async {
        buildPlatform(isIOS: ios).attachForegroundDisplay();
        openConversation(peer: 'peer_2');

        incoming.add(chatPush());
        await flush();

        expect(shown, hasLength(1));
      });
    }

    test('suppression follows the registration: cleared on unregister',
        () async {
      buildPlatform(isIOS: true).attachForegroundDisplay();
      final handle = openConversation();

      incoming.add(chatPush(id: 'while_open'));
      await flush();
      expect(shown, isEmpty);

      handle.unregister();
      incoming.add(chatPush(id: 'after_close'));
      await flush();
      expect(shown.map((m) => m.messageId), ['after_close']);
      expect(registry.registeredCount, 0);
    });

    test('route visibility: a covered conversation is not "being viewed"',
        () async {
      buildPlatform(isIOS: true).attachForegroundDisplay();
      var visible = true;
      openConversation(visible: () => visible);

      incoming.add(chatPush(id: 'visible'));
      await flush();
      expect(shown, isEmpty);

      visible = false; // another page / dialog pushed on top
      incoming.add(chatPush(id: 'covered'));
      await flush();
      expect(shown.map((m) => m.messageId), ['covered']);

      visible = true; // popped back
      incoming.add(chatPush(id: 'visible_again'));
      await flush();
      expect(shown.map((m) => m.messageId), ['covered']);
    });

    test('realtime socket down => banner is kept', () async {
      buildPlatform(isIOS: false).attachForegroundDisplay();
      var live = false;
      openConversation(live: () => live);

      incoming.add(chatPush(id: 'down'));
      await flush();
      expect(shown.map((m) => m.messageId), ['down']);

      live = true;
      incoming.add(chatPush(id: 'up'));
      await flush();
      expect(shown.map((m) => m.messageId), ['down']);
    });

    test('screen of a different account never suppresses', () async {
      buildPlatform(isIOS: false).attachForegroundDisplay();
      openConversation(owner: 'previous_account');

      incoming.add(chatPush());
      await flush();

      expect(shown, hasLength(1));
    });
  });

  group('app lifecycle', () {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
    ]) {
      test('$state => banner is shown even for the open conversation',
          () async {
        buildPlatform(isIOS: true).attachForegroundDisplay();
        openConversation();

        binding.handleAppLifecycleStateChanged(state);
        incoming.add(chatPush());
        await flush();

        expect(shown, hasLength(1));
      });
    }

    test('back to resumed suppresses again', () async {
      buildPlatform(isIOS: true).attachForegroundDisplay();
      openConversation();

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      incoming.add(chatPush(id: 'inactive'));
      await flush();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      incoming.add(chatPush(id: 'resumed'));
      await flush();

      expect(shown.map((m) => m.messageId), ['inactive']);
    });
  });

  group('background behaviour is untouched', () {
    test('the foreground policy is never consulted for background delivery: '
        'only handleForegroundMessage decides, and it needs a foreground '
        'onMessage event', () async {
      // Background / terminated pushes are shown by the OS (and the Dart
      // background handler only initializes Firebase). With no foreground
      // event nothing is presented or suppressed by this code.
      buildPlatform(isIOS: true).attachForegroundDisplay();
      openConversation();
      await flush();
      expect(shown, isEmpty);
      expect(presentationCalls, isEmpty);
    });
  });

  group('never silently suppress when identity is missing or ambiguous', () {
    Future<void> expectBanner(RemoteMessage m) async {
      buildPlatform(isIOS: true).attachForegroundDisplay();
      openConversation();
      incoming.add(m);
      await flush();
      expect(shown, hasLength(1), reason: '${m.data}');
    }

    RemoteMessage push(Map<String, String> data) => RemoteMessage(
      notification: RemoteNotification(title: 't', body: 'b'),
      data: data,
    );

    test('missing car_id', () async {
      await expectBanner(
        push({'type': 'chat_message', 'sender_id': 'peer_1'}),
      );
    });
    test('missing sender_id', () async {
      await expectBanner(push({'type': 'chat_message', 'car_id': 'car_1'}));
    });
    test('"None" ids from the backend', () async {
      await expectBanner(
        push({
          'type': 'chat_message',
          'car_id': 'None',
          'sender_id': 'peer_1',
        }),
      );
    });
    test('open conversation with an unknown counterpart', () async {
      buildPlatform(isIOS: true).attachForegroundDisplay();
      openConversation(peer: null);
      incoming.add(chatPush());
      await flush();
      expect(shown, hasLength(1));
    });
  });

  group('unrelated notification types and deep links are preserved', () {
    test('non-chat types always show a banner, even with that car open',
        () async {
      buildPlatform(isIOS: true).attachForegroundDisplay();
      openConversation();

      for (final data in <Map<String, String>>[
        {'car_id': 'car_1'}, // saved search
        {'type': 'price_drop', 'car_id': 'car_1'},
        {'type': 'dealer_application'},
      ]) {
        incoming.add(
          RemoteMessage(
            notification: RemoteNotification(title: 't', body: 'b'),
            data: data,
          ),
        );
      }
      await flush();

      expect(shown, hasLength(3));
    });

    test('data-only pushes (no notification block) still reach the presenter '
        'path unchanged', () async {
      buildPlatform(isIOS: true).attachForegroundDisplay();
      incoming.add(RemoteMessage(data: {'type': 'dealer_application'}));
      await flush();
      expect(shown, hasLength(1)); // presenter decides (real one ignores it)
    });

    test('notification taps still resolve to the same destinations', () {
      final chat = PushNotificationService.debugResolveNotificationDestination(
        {'type': 'chat_message', 'car_id': 'car_1', 'sender_id': 'peer_1'},
      );
      expect(chat?.route, '/chat/conversation');
      expect(chat?.arguments, {'carId': 'car_1', 'receiverId': 'peer_1'});

      final listing =
          PushNotificationService.debugResolveNotificationDestination({
            'car_id': 'car_1',
          });
      expect(listing?.route, '/car_detail');

      final dealer =
          PushNotificationService.debugResolveNotificationDestination({
            'type': 'dealer_application',
          });
      expect(dealer?.route, '/profile');
    });
  });
}
