// Regression tests for the foreground chat-notification decision
// ([decideForegroundNotification]) and the conversation-presence registry.
//
// The rule under test: a banner is suppressed ONLY when every signal says the
// user is looking at the matching conversation right now; anything missing,
// stale or ambiguous shows it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/foreground_notification_policy.dart';

const _chat = {'type': 'chat_message', 'car_id': 'car_1', 'sender_id': 'peer_1'};

ChatConversationSnapshot convo({
  String carId = 'car_1',
  String? peerId = 'peer_1',
  String? ownerId = 'me',
  bool visible = true,
  bool realtimeLive = true,
}) => ChatConversationSnapshot(
  carId: carId,
  peerId: peerId,
  ownerId: ownerId,
  visible: visible,
  realtimeLive: realtimeLive,
);

ForegroundNotificationDecision decide({
  Map<String, dynamic> data = _chat,
  AppLifecycleState? lifecycle = AppLifecycleState.resumed,
  String? me = 'me',
  List<ChatConversationSnapshot>? conversations,
}) => decideForegroundNotification(
  data: data,
  lifecycle: lifecycle,
  currentAccountId: me,
  conversations: conversations ?? [convo()],
);

void expectShown(
  ForegroundNotificationDecision d,
  ForegroundNotificationReason reason,
) {
  expect(d.suppress, isFalse, reason: '$d');
  expect(d.show, isTrue);
  expect(d.reason, reason);
}

void main() {
  group('iOS native foreground presentation', () {
    test('is fully off so only the app\'s single local banner is shown', () {
      // Dart shows exactly one banner per foreground push; the OS must not add
      // a second one (the old `alert: true` produced two identical banners).
      expect(kIosNativeForegroundPresentation.alert, isFalse);
      expect(kIosNativeForegroundPresentation.badge, isFalse);
      expect(kIosNativeForegroundPresentation.sound, isFalse);
    });
  });

  group('suppression: only for the conversation being viewed', () {
    test('matching listing + sender, resumed, visible, live => suppressed', () {
      final d = decide();
      expect(d.suppress, isTrue);
      expect(d.reason, ForegroundNotificationReason.activeConversation);
    });

    test('ids are compared trimmed', () {
      final d = decide(
        data: {..._chat, 'car_id': ' car_1 ', 'sender_id': 'peer_1\n'},
        conversations: [convo(carId: 'car_1 ', peerId: ' peer_1')],
        me: ' me ',
      );
      expect(d.suppress, isTrue);
    });

    test('a different listing is shown', () {
      expectShown(
        decide(data: {..._chat, 'car_id': 'car_2'}),
        ForegroundNotificationReason.noConversation,
      );
    });

    test('same listing, different sender (seller with several buyers) is shown',
        () {
      expectShown(
        decide(data: {..._chat, 'sender_id': 'peer_2'}),
        ForegroundNotificationReason.otherConversation,
      );
    });

    test('no conversation open is shown', () {
      expectShown(
        decide(conversations: const []),
        ForegroundNotificationReason.noConversation,
      );
    });

    test('suppressed when ANY registered screen matches', () {
      final d = decide(
        conversations: [
          convo(carId: 'car_9'),
          convo(peerId: 'peer_2'),
          convo(),
        ],
      );
      expect(d.suppress, isTrue);
    });

    test('a hidden match plus a visible non-match still shows', () {
      final d = decide(
        conversations: [convo(visible: false), convo(peerId: 'peer_2')],
      );
      expectShown(d, ForegroundNotificationReason.otherConversation);
    });
  });

  group('app lifecycle', () {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
      null,
    ]) {
      test('$state is never "actively viewing" => shown', () {
        expectShown(
          decide(lifecycle: state),
          ForegroundNotificationReason.appNotResumed,
        );
      });
    }
  });

  group('route visibility', () {
    test('a conversation covered by another page/dialog is shown', () {
      expectShown(
        decide(conversations: [convo(visible: false)]),
        ForegroundNotificationReason.conversationHidden,
      );
    });
  });

  group('missing or ambiguous identity never silently suppresses', () {
    test('missing car_id', () {
      expectShown(
        decide(data: {'type': 'chat_message', 'sender_id': 'peer_1'}),
        ForegroundNotificationReason.missingIdentity,
      );
    });

    test('missing sender_id', () {
      expectShown(
        decide(data: {'type': 'chat_message', 'car_id': 'car_1'}),
        ForegroundNotificationReason.missingIdentity,
      );
    });

    test('blank ids', () {
      expectShown(
        decide(data: {..._chat, 'car_id': '  ', 'sender_id': ''}),
        ForegroundNotificationReason.missingIdentity,
      );
    });

    test('server-stringified None/null ids (str(None) on the backend)', () {
      for (final bad in ['None', 'none', 'null', 'NULL']) {
        expectShown(
          decide(
            data: {..._chat, 'car_id': bad},
            conversations: [convo(carId: bad)],
          ),
          ForegroundNotificationReason.missingIdentity,
        );
        expectShown(
          decide(
            data: {..._chat, 'sender_id': bad},
            conversations: [convo(peerId: bad)],
          ),
          ForegroundNotificationReason.missingIdentity,
        );
      }
    });

    test('open conversation with unknown counterpart', () {
      for (final unknown in [null, '', '  ']) {
        expectShown(
          decide(conversations: [convo(peerId: unknown)]),
          ForegroundNotificationReason.peerUnknown,
        );
      }
    });

    test('screen of another account than the signed-in one', () {
      expectShown(
        decide(conversations: [convo(ownerId: 'someone_else')]),
        ForegroundNotificationReason.accountMismatch,
      );
    });

    test('unknown owner or unknown signed-in account', () {
      expectShown(
        decide(conversations: [convo(ownerId: null)]),
        ForegroundNotificationReason.accountMismatch,
      );
      expectShown(
        decide(me: null),
        ForegroundNotificationReason.accountMismatch,
      );
      expectShown(
        decide(me: ''),
        ForegroundNotificationReason.accountMismatch,
      );
    });

    test('realtime socket down: the banner is the only signal => shown', () {
      expectShown(
        decide(conversations: [convo(realtimeLive: false)]),
        ForegroundNotificationReason.realtimeDown,
      );
    });
  });

  group('unrelated notification types are never suppressed', () {
    final cases = <String, Map<String, dynamic>>{
      'saved search (no type)': {'car_id': 'car_1'},
      'price drop': {'type': 'price_drop', 'car_id': 'car_1'},
      'dealer application': {'type': 'dealer_application'},
      'legacy chat (no type)': {'car_id': 'car_1', 'sender_id': 'peer_1'},
      'unknown type': {
        'type': 'something_new',
        'car_id': 'car_1',
        'sender_id': 'peer_1',
      },
      'empty data': <String, dynamic>{},
    };
    cases.forEach((name, data) {
      test(name, () {
        expectShown(
          decide(data: data),
          ForegroundNotificationReason.notChatMessage,
        );
      });
    });
  });

  group('ChatConversationPresence registry', () {
    late ChatConversationPresence registry;
    setUp(() => registry = ChatConversationPresence());

    ChatConversationPresenceHandle add({
      String car = 'car_1',
      String? peer = 'peer_1',
      bool Function()? visible,
    }) => registry.register(
      carId: () => car,
      peerId: () => peer,
      ownerId: () => 'me',
      isVisible: visible ?? () => true,
      isRealtimeLive: () => true,
    );

    test('register / unregister keeps an exact count; unregister is idempotent',
        () {
      expect(registry.registeredCount, 0);
      final a = add();
      final b = add(car: 'car_2');
      expect(registry.registeredCount, 2);
      expect(a.isRegistered, isTrue);

      a.unregister();
      expect(registry.registeredCount, 1);
      expect(a.isRegistered, isFalse);
      a.unregister(); // second call must not remove b or throw
      expect(registry.registeredCount, 1);

      b.unregister();
      expect(registry.registeredCount, 0);
      expect(registry.snapshots(), isEmpty);
    });

    test('state is read lazily at snapshot time (nothing goes stale)', () {
      var visible = true;
      add(visible: () => visible);
      expect(registry.snapshots().single.visible, isTrue);
      visible = false;
      expect(registry.snapshots().single.visible, isFalse);
      visible = true;
      expect(registry.snapshots().single.visible, isTrue);
    });

    test('a throwing closure becomes a hidden, non-matching entry', () {
      registry.register(
        carId: () => throw StateError('element deactivated'),
        peerId: () => 'peer_1',
        ownerId: () => 'me',
        isVisible: () => true,
        isRealtimeLive: () => true,
      );
      final snap = registry.snapshots().single;
      expect(snap.visible, isFalse);
      final d = decide(conversations: registry.snapshots());
      expect(d.suppress, isFalse);
    });

    test('debugClear drops every entry', () {
      add();
      add();
      registry.debugClear();
      expect(registry.registeredCount, 0);
    });
  });
}
