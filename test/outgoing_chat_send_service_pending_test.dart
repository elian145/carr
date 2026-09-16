import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/connectivity_service.dart';
import 'package:car_listing_app/services/outgoing_chat_send_service.dart';
import 'package:car_listing_app/shared/prefs/chat_pending_send_prefs.dart';

import 'fake_api_server.dart';

/// F-11 focused coverage for `OutgoingChatSendService`'s durable
/// pending-send persistence and bounded retry behavior, using
/// deterministic gates (`FakeApiServer.chatSendOverride` + manual
/// backoff-window aging) instead of real sleeps/timers.
void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
    FakeApiServer.chatSendIdempotencyKeys.clear();
    FakeApiServer.chatSendCallCount = 0;
    FakeApiServer.chatSendOverride = null;
  });

  tearDown(() async {
    await ApiService.clearTokens();
    FakeApiServer.chatSendOverride = null;
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  /// Simulates time passing since the last attempt without any real
  /// sleeping, so `OutgoingChatSendService.minAutoRetryInterval` no longer
  /// blocks the next `recoverPendingSends()` call from retrying [id].
  Future<void> ageOutBackoff(String conversationId, String id) async {
    final all = await ChatPendingSendPrefs.loadForConversation(conversationId);
    final rec = all.firstWhere((r) => r.id == id);
    await ChatPendingSendPrefs.upsert(
      rec.copyWith(
        lastAttemptAt: DateTime.now()
            .subtract(const Duration(seconds: 30))
            .millisecondsSinceEpoch,
      ),
    );
  }

  group('retryable vs. definitive failure classification', () {
    test(
      '1) a transient (500) failure on the first attempt persists a '
      'retryable pending record with the send\'s idempotency key',
      () async {
        FakeApiServer.chatSendOverride =
            (request, callIndex) => http.Response('', 500);
        final events = <OutgoingChatSendEvent>[];
        final sub = OutgoingChatSendService.instance.events.listen(events.add);
        addTearDown(sub.cancel);

        OutgoingChatSendService.instance.startTextMessageSend(
          conversationId: 'car_pending_1',
          content: 'hello there',
          tempMessageId: 'temp_p1',
        );
        await pumpEventQueue();

        expect(events, hasLength(1));
        expect(events.single.success, isFalse);
        expect(events.single.pendingRetry, isTrue);

        final pending =
            await ChatPendingSendPrefs.loadForConversation('car_pending_1');
        expect(pending, hasLength(1));
        expect(pending.single.kind, 'text');
        expect(pending.single.content, 'hello there');
        expect(pending.single.attempts, 1);
        expect(pending.single.idempotencyKey, isNotEmpty);
        expect(
          pending.single.idempotencyKey,
          FakeApiServer.chatSendIdempotencyKeys.single,
        );
      },
    );

    test(
      'a definitive (400) failure is NOT persisted and is reported with '
      'pendingRetry=false / restoredPlainText set (pre-existing behavior '
      'unchanged, existing successful/definitive-failure sends are not '
      'affected by F-11)',
      () async {
        FakeApiServer.chatSendOverride =
            (request, callIndex) => http.Response('{}', 400);
        final events = <OutgoingChatSendEvent>[];
        final sub = OutgoingChatSendService.instance.events.listen(events.add);
        addTearDown(sub.cancel);

        OutgoingChatSendService.instance.startTextMessageSend(
          conversationId: 'car_pending_2',
          content: 'will not retry',
          tempMessageId: 'temp_p2',
        );
        await pumpEventQueue();

        expect(events.single.pendingRetry, isFalse);
        expect(events.single.restoredPlainText, 'will not retry');
        expect(
          await ChatPendingSendPrefs.loadForConversation('car_pending_2'),
          isEmpty,
        );
      },
    );

    test(
      '8) an ordinary successful send is completely unaffected: no pending '
      'record is ever created for it',
      () async {
        final events = <OutgoingChatSendEvent>[];
        final sub = OutgoingChatSendService.instance.events.listen(events.add);
        addTearDown(sub.cancel);

        OutgoingChatSendService.instance.startTextMessageSend(
          conversationId: 'car_pending_3',
          content: 'a normal message',
          tempMessageId: 'temp_p3',
        );
        await pumpEventQueue();

        expect(events.single.success, isTrue);
        expect(
          await ChatPendingSendPrefs.loadForConversation('car_pending_3'),
          isEmpty,
        );
      },
    );
  });

  group('recoverPendingSends', () {
    test(
      '4) + 5) a durable retry reuses the exact same idempotency key, and '
      'removes the pending record exactly once on success',
      () async {
        FakeApiServer.chatSendOverride = (request, callIndex) {
          if (callIndex == 0) return http.Response('', 503);
          return null; // 2nd call falls through to the default success stub.
        };

        OutgoingChatSendService.instance.startTextMessageSend(
          conversationId: 'car_retry_1',
          content: 'retry me',
          tempMessageId: 'temp_retry_1',
        );
        await pumpEventQueue();

        final firstKey = FakeApiServer.chatSendIdempotencyKeys[0];
        expect(firstKey, isNotEmpty);
        expect(
          await ChatPendingSendPrefs.loadForConversation('car_retry_1'),
          hasLength(1),
        );

        await ageOutBackoff('car_retry_1', 'temp_retry_1');
        final events = <OutgoingChatSendEvent>[];
        final sub = OutgoingChatSendService.instance.events.listen(events.add);
        addTearDown(sub.cancel);

        await OutgoingChatSendService.instance
            .recoverPendingSends(conversationId: 'car_retry_1');
        await pumpEventQueue();

        expect(FakeApiServer.chatSendIdempotencyKeys.length, 2);
        expect(
          FakeApiServer.chatSendIdempotencyKeys[1],
          firstKey,
          reason: 'the durable retry must reuse the exact same key',
        );
        expect(events.single.success, isTrue);
        expect(
          await ChatPendingSendPrefs.loadForConversation('car_retry_1'),
          isEmpty,
          reason: 'a successful retry must remove the pending record',
        );
      },
    );

    test(
      '3) a pending record written with no in-memory service state behind '
      'it at all (simulating recovery after an app restart) is retried '
      'using its own stored data/key',
      () async {
        await ChatPendingSendPrefs.upsert(
          ChatPendingSendRecord(
            id: 'temp_restart_1',
            conversationId: 'car_restart_1',
            kind: 'text',
            idempotencyKey: 'chat-send-restart-key-1',
            content: 'from a previous app session',
            createdAt: DateTime.now()
                .subtract(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
            attempts: 1,
            lastAttemptAt: DateTime.now()
                .subtract(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
          ),
        );

        final events = <OutgoingChatSendEvent>[];
        final sub = OutgoingChatSendService.instance.events.listen(events.add);
        addTearDown(sub.cancel);

        await OutgoingChatSendService.instance.recoverPendingSends();
        await pumpEventQueue();

        expect(FakeApiServer.chatSendIdempotencyKeys, [
          'chat-send-restart-key-1',
        ]);
        final ev =
            events.singleWhere((e) => e.tempMessageId == 'temp_restart_1');
        expect(ev.success, isTrue);
        expect(
          await ChatPendingSendPrefs.loadForConversation('car_restart_1'),
          isEmpty,
        );
      },
    );

    test(
      '6) calling recoverPendingSends twice back-to-back only dispatches '
      'one retry attempt for the same pending send (reentrancy guard — no '
      'duplicate enqueue)',
      () async {
        FakeApiServer.chatSendOverride =
            (request, callIndex) => http.Response('', 503);
        OutgoingChatSendService.instance.startTextMessageSend(
          conversationId: 'car_dedupe_1',
          content: 'dedupe me',
          tempMessageId: 'temp_dedupe_1',
        );
        await pumpEventQueue();
        await ageOutBackoff('car_dedupe_1', 'temp_dedupe_1');

        final before = FakeApiServer.chatSendCallCount;
        final f1 = OutgoingChatSendService.instance
            .recoverPendingSends(conversationId: 'car_dedupe_1');
        final f2 = OutgoingChatSendService.instance
            .recoverPendingSends(conversationId: 'car_dedupe_1');
        await Future.wait([f1, f2]);
        await pumpEventQueue();

        expect(FakeApiServer.chatSendCallCount - before, 1);
        final pending =
            await ChatPendingSendPrefs.loadForConversation('car_dedupe_1');
        expect(pending, hasLength(1));
      },
    );

    test(
      '7) a send that keeps failing remains persisted/visible up to '
      'maxAutoRetryAttempts, then stops auto-retrying WITHOUT being '
      'removed (still retryable manually)',
      () async {
        FakeApiServer.chatSendOverride =
            (request, callIndex) => http.Response('', 503);
        OutgoingChatSendService.instance.startTextMessageSend(
          conversationId: 'car_exhaust_1',
          content: 'never lands',
          tempMessageId: 'temp_exhaust_1',
        );
        await pumpEventQueue();

        // Drive well past the auto-retry budget — each iteration ages out
        // the backoff window deterministically instead of sleeping.
        for (var i = 0;
            i < OutgoingChatSendService.maxAutoRetryAttempts + 2;
            i++) {
          await ageOutBackoff('car_exhaust_1', 'temp_exhaust_1');
          await OutgoingChatSendService.instance
              .recoverPendingSends(conversationId: 'car_exhaust_1');
          await pumpEventQueue();
        }

        final pending =
            await ChatPendingSendPrefs.loadForConversation('car_exhaust_1');
        expect(
          pending,
          hasLength(1),
          reason: 'must remain visible/retryable, not silently disappear',
        );
        expect(pending.single.attempts, OutgoingChatSendService.maxAutoRetryAttempts);
        expect(
          FakeApiServer.chatSendCallCount,
          OutgoingChatSendService.maxAutoRetryAttempts,
          reason: 'the bounded retry budget must not be exceeded even '
              'though recovery was requested more times than that',
        );
      },
    );

    test(
      '9) a durable media-group pending record recovered for retry never '
      'duplicates the original local media file on disk',
      () async {
        // Seeded directly (rather than produced by an actual failed
        // `startMediaGroupSend` call): `ApiService.sendChatMediaGroup`
        // builds its own `MultipartRequest` and calls `BaseRequest.send()`
        // directly, which (pre-existing, unrelated to F-11) always opens a
        // fresh real `http.Client` instead of going through
        // `ApiService.testHttpClient` — Flutter's test binding then
        // intercepts that with a fixed 400, which is a *definitive*
        // failure, not a transient one. Seeding the record directly tests
        // the guarantee this case actually cares about — that recovering
        // a persisted media record never creates a second/copied file —
        // independent of that unrelated HTTP-mocking limitation.
        final tmpDir = Directory.systemTemp.createTempSync('f11_chat_media_');
        addTearDown(() {
          try {
            tmpDir.deleteSync(recursive: true);
          } catch (_) {}
        });
        final file =
            File('${tmpDir.path}${Platform.pathSeparator}photo.jpg')
              ..writeAsBytesSync([1, 2, 3, 4]);

        await ChatPendingSendPrefs.upsert(
          ChatPendingSendRecord(
            id: 'temp_media_1',
            conversationId: 'car_media_1',
            kind: 'mediaGroup',
            idempotencyKey: 'chat-send-media-key-1',
            filePaths: [file.path],
            createdAt: DateTime.now()
                .subtract(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
            attempts: 1,
            lastAttemptAt: DateTime.now()
                .subtract(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
          ),
        );

        await OutgoingChatSendService.instance
            .recoverPendingSends(conversationId: 'car_media_1');
        await pumpEventQueue();

        // Regardless of the retry's HTTP outcome (not under test here),
        // recovering a media pending record must never create a second or
        // renamed copy of the original file — it always reuses the exact
        // original path.
        final remaining = tmpDir.listSync().map((e) => e.path).toList();
        expect(remaining, hasLength(1));
        expect(
          File(remaining.single).absolute.path,
          File(file.path).absolute.path,
          reason: 'no second/copied media file should exist on disk',
        );
      },
    );

    test(
      '10) connectivity-triggered recovery is bounded by the same backoff '
      'window: rapid offline/online flapping does not spin retries',
      () async {
        FakeApiServer.chatSendOverride =
            (request, callIndex) => http.Response('', 503);
        OutgoingChatSendService.instance.startTextMessageSend(
          conversationId: 'car_conn_1',
          content: 'conn retry',
          tempMessageId: 'temp_conn_1',
        );
        await pumpEventQueue();

        OutgoingChatSendService.instance.hookConnectivityRecovery();
        await ageOutBackoff('car_conn_1', 'temp_conn_1');

        final before = FakeApiServer.chatSendCallCount;
        // Flap offline -> online twice in a row with no real waiting
        // between. Only genuine offline->online transitions call
        // recoverPendingSends, and the per-record backoff window (aged
        // out exactly once above) must let through at most one retry
        // across all of this flapping, not one per toggle.
        ConnectivityService.instance.isOnline.value = false;
        ConnectivityService.instance.isOnline.value = true;
        await pumpEventQueue();
        ConnectivityService.instance.isOnline.value = false;
        ConnectivityService.instance.isOnline.value = true;
        await pumpEventQueue();

        expect(FakeApiServer.chatSendCallCount - before, 1);
      },
    );
  });

  group('discardPendingSend', () {
    test(
      'discarding a pending send removes its durable record so recovery '
      'can never resurrect it',
      () async {
        FakeApiServer.chatSendOverride =
            (request, callIndex) => http.Response('', 500);
        OutgoingChatSendService.instance.startTextMessageSend(
          conversationId: 'car_discard_1',
          content: 'to be recalled',
          tempMessageId: 'temp_discard_1',
        );
        await pumpEventQueue();
        expect(
          await ChatPendingSendPrefs.loadForConversation('car_discard_1'),
          hasLength(1),
        );

        OutgoingChatSendService.instance.discardPendingSend('temp_discard_1');
        // discardPendingSend's prefs removal is fire-and-forget; give it a
        // tick to complete before asserting.
        await pumpEventQueue();

        expect(
          await ChatPendingSendPrefs.loadForConversation('car_discard_1'),
          isEmpty,
        );

        final before = FakeApiServer.chatSendCallCount;
        await OutgoingChatSendService.instance
            .recoverPendingSends(conversationId: 'car_discard_1');
        await pumpEventQueue();
        expect(FakeApiServer.chatSendCallCount, before);
      },
    );
  });
}
