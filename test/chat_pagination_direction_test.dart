// CarNet V1 release-candidate fix 2 -- chat pagination direction.
//
// Bug: the chat REST transport always requested `page=1` to open a
// conversation and `page+1` on scroll-up, while the backend sorted
// ascending and paginated forward -- so `page=1` was always the OLDEST
// messages. For a conversation with more than one page of history, this
// meant opening a chat showed the oldest messages (not the latest) and
// scrolling up to see older history actually loaded newer messages.
//
// Fix: `kk/routes/chat.py::get_messages` now has a single pagination
// contract (a `before` cursor; no `page`/offset scheme) -- no cursor means
// "give me the newest page", `before=<oldest loaded message's created_at>`
// means "give me the next-older page". `ApiService.getChatMessagesByConversation`
// / `_loadHistory()` / `_loadOlderMessages()` (lib/features/chat/) were
// updated to match.
//
// This file drives the real `ChatConversationPage` against a 70-message
// fake conversation (more than one 50-message page) and proves:
//   * opening the conversation requests no `before` cursor and shows the
//     NEWEST messages, scrolled to the bottom.
//   * scrolling to the top loads the next-older page via `before`, with no
//     duplicates, and the full history is reachable in the correct
//     chronological order.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/carzo_shared.dart' show AuthGuard;
import 'package:car_listing_app/features/chat/chat_pages.dart' as carzo_chat;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'fake_api_server.dart';

/// [count] messages, oldest-first (index 0 is the oldest), alternating
/// sender/receiver, one minute apart -- content `msg-0000` .. `msg-NNNN`
/// makes chronological order trivially assertable.
List<Map<String, dynamic>> _conversation(int count) => List.generate(count, (
  i,
) {
  final isSeller = i.isEven;
  return {
    'id': 'm$i',
    'content': 'msg-${i.toString().padLeft(4, '0')}',
    'message_type': 'text',
    'sender_id': isSeller ? 'seller_1' : 'buyer_1',
    'receiver_id': isSeller ? 'buyer_1' : 'seller_1',
    'is_read': true,
    // Explicit UTC (trailing `Z`) so the fixture's absolute instant is
    // unambiguous regardless of the test runner's local timezone --
    // matches what `parseApiDateTime`/the `before`-cursor round-trip
    // through `ChatMessage.createdAt.toUtc()` actually produce.
    'created_at': DateTime.utc(2026, 1, 1)
        .add(Duration(minutes: i))
        .toIso8601String(),
  };
});

Finder _messageListFinder() => find.byWidgetPredicate((w) => w is ListView);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
    await ApiService.clearTokens();
    await AuthService().adoptTestSession(
      user: {
        'id': 1,
        'username': 'seller',
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.chatMessagesAllItems = null;
    FakeApiServer.chatMessagesRequestedBefore.clear();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Widget harness(Widget child) {
    return ChangeNotifierProvider<AuthService>.value(
      value: AuthService(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  Future<void> openConversation(WidgetTester tester, String carId) async {
    await tester.pumpWidget(
      harness(
        AuthGuard(
          child: carzo_chat.ChatConversationPage(
            carId: carId,
            receiverId: 'buyer_1',
            carTitle: 'Toyota Camry 2020',
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();
      if (_messageListFinder().evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'opening a 70-message conversation requests no `before` cursor and '
    'shows the NEWEST messages, scrolled to the bottom',
    (tester) async {
      FakeApiServer.chatMessagesAllItems = _conversation(70);
      await openConversation(tester, 'pg_car_1');

      expect(FakeApiServer.chatMessagesRequestedBefore, ['']);

      final listView = tester.widget<ListView>(_messageListFinder());
      final delegate = listView.childrenDelegate;
      expect(delegate, isA<SliverChildBuilderDelegate>());
      // 50 real messages (msg-0020..msg-0069) + 1 "load more" slot at the
      // top (has_more is true: 70 total > 50 returned) -- proves the data
      // loaded is the newest 50, not the oldest 50.
      expect((delegate as SliverChildBuilderDelegate).childCount, 51);

      // Scrolled at/near the bottom by default -- the newest message is
      // reachable by scrolling forward a little further (lazily built).
      await tester.dragUntilVisible(
        find.text('msg-0069'),
        _messageListFinder(),
        const Offset(0, -80),
      );
      expect(find.text('msg-0069'), findsOneWidget);
      // The oldest overall message must NOT have been fetched at all yet
      // (it's not in the 51-item delegate no matter how far we scroll).
      expect(find.text('msg-0000'), findsNothing);
    },
  );

  testWidgets(
    'scrolling to the top loads the next-older page via `before`, with no '
    'duplicates, reaching the true oldest message',
    (tester) async {
      FakeApiServer.chatMessagesAllItems = _conversation(70);
      await openConversation(tester, 'pg_car_2');
      expect(FakeApiServer.chatMessagesRequestedBefore, ['']);

      final scrollController = tester
          .widget<ListView>(_messageListFinder())
          .controller!;

      // Scroll to the top -- triggers `_loadOlderMessages()`, which must
      // request `before=<oldest loaded message's created_at>` (msg-0020),
      // NOT a `page` param.
      scrollController.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(FakeApiServer.chatMessagesRequestedBefore.length, 2);
      expect(FakeApiServer.chatMessagesRequestedBefore[1], isNotEmpty);

      final delegateAfter =
          tester.widget<ListView>(_messageListFinder()).childrenDelegate;
      // All 70 messages, no more "load more" slot (has_more is false).
      expect((delegateAfter as SliverChildBuilderDelegate).childCount, 70);

      // The next-older page (msg-0000..msg-0019) is now loaded, merged with
      // no duplicates -- reachable by scrolling all the way back up to the
      // top (the load-older UX deliberately keeps the viewport anchored on
      // what was already visible rather than jumping, so we scroll there
      // ourselves to prove the data is really there). Checked one at a
      // time (rather than all simultaneously visible) since the viewport
      // is far shorter than 20 stacked message bubbles.
      await tester.dragUntilVisible(
        find.text('msg-0000'),
        _messageListFinder(),
        const Offset(0, 80),
      );
      expect(find.text('msg-0000'), findsOneWidget, reason: 'true oldest message must be reachable');

      await tester.dragUntilVisible(
        find.text('msg-0019'),
        _messageListFinder(),
        const Offset(0, -80),
      );
      // Exactly one copy each -- no duplicate rendering across the merge.
      expect(find.text('msg-0019'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('msg-0020'),
        _messageListFinder(),
        const Offset(0, -80),
      );
      expect(find.text('msg-0020'), findsOneWidget);
    },
  );

  testWidgets(
    'a conversation with fewer than one page of messages has no `before` '
    'requests and no load-more slot',
    (tester) async {
      FakeApiServer.chatMessagesAllItems = _conversation(5);
      await openConversation(tester, 'pg_car_3');

      expect(FakeApiServer.chatMessagesRequestedBefore, ['']);
      expect(find.text('msg-0000'), findsOneWidget);
      expect(find.text('msg-0004'), findsOneWidget);

      final delegate =
          tester.widget<ListView>(_messageListFinder()).childrenDelegate;
      expect((delegate as SliverChildBuilderDelegate).childCount, 5);
    },
  );
}
