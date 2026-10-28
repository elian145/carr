import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/outgoing_chat_send_service.dart';
import 'package:car_listing_app/shared/prefs/chat_pending_send_prefs.dart';

import 'fake_api_server.dart';
import 'support/test_jwt.dart';

/// F-05 fail-closed recovery: a pending send whose RECIPIENT IS UNKNOWN
/// (null / blank `receiverId`) must never be retried automatically. A listing
/// seller talks to several buyers about one listing, and the backend's
/// "single counterpart" inference does not prove which buyer an old message
/// was meant for. Such records are quarantined: kept on disk, untouched,
/// never sent and never deleted. Known-recipient records retry as before.
void main() {
  late Directory dir;
  late String mediaPath;
  late String audioPath;

  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.setTokens(
      accessToken: testJwt('owner_test'),
      refreshToken: 'test_refresh_token',
    );
    FakeApiServer.chatSendIdempotencyKeys.clear();
    FakeApiServer.chatSendCallCount = 0;
    FakeApiServer.chatSendOverride = null;
    dir = await Directory.systemTemp.createTemp('quarantine_');
    final m = File('${dir.path}/photo.jpg')..writeAsBytesSync([1, 2, 3, 4]);
    final a = File('${dir.path}/voice.m4a')..writeAsBytesSync([5, 6, 7, 8]);
    mediaPath = m.path;
    audioPath = a.path;
  });

  tearDown(() async {
    await ApiService.clearTokens();
    FakeApiServer.chatSendOverride = null;
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  final aged = DateTime.now()
      .subtract(const Duration(minutes: 5))
      .millisecondsSinceEpoch;

  ChatPendingSendRecord rec(
    String id, {
    required String kind,
    String owner = 'owner_test',
    String conversation = 'car_q',
    String? receiverId,
    String? content,
    List<String> files = const <String>[],
  }) =>
      ChatPendingSendRecord(
        ownerUserId: owner,
        id: id,
        conversationId: conversation,
        kind: kind,
        idempotencyKey: 'key-$id',
        content: content,
        receiverId: receiverId,
        filePaths: files,
        createdAt: aged,
        attempts: 1,
        lastAttemptAt: aged,
      );

  Future<Map<String, Map<String, dynamic>>> stored() async => {
        for (final r in await ChatPendingSendPrefs.loadAll()) r.id: r.toJson(),
      };

  test('recipient-unknown text / audio / media-group records are never sent '
      'and stay stored, byte-for-byte', () async {
    final unknown = <ChatPendingSendRecord>[
      rec('t_null', kind: 'text', content: 'old text'),
      rec('t_blank', kind: 'text', content: 'old text 2', receiverId: '   '),
      rec('a_null', kind: 'audio', files: [audioPath]),
      rec('a_blank', kind: 'audio', receiverId: '', files: [audioPath]),
      rec('m_null', kind: 'mediaGroup', content: 'cap', files: [mediaPath]),
      rec('m_blank',
          kind: 'mediaGroup', receiverId: ' ', files: [mediaPath]),
    ];
    for (final r in unknown) {
      await ChatPendingSendPrefs.upsert(r);
    }
    final before = await stored();
    expect(before.keys, unknown.map((r) => r.id).toSet());

    // Global scan, conversation-scoped scan, and repeated scans.
    await OutgoingChatSendService.instance.recoverPendingSends();
    await pumpEventQueue();
    await OutgoingChatSendService.instance
        .recoverPendingSends(conversationId: 'car_q');
    await pumpEventQueue();
    await OutgoingChatSendService.instance.recoverPendingSends();
    await pumpEventQueue();

    expect(FakeApiServer.chatSendCallCount, 0,
        reason: 'an unknown-recipient message must NEVER be auto-sent');
    expect(FakeApiServer.chatSendIdempotencyKeys, isEmpty);
    expect(await stored(), before,
        reason: 'quarantined records are preserved untouched '
            '(not deleted, no attempt counted)');
    expect(unknown.every((r) => !r.hasKnownRecipient), isTrue);
  });

  test('a known-recipient record still retries normally next to quarantined '
      'ones, with its original idempotency key, and is then removed',
      () async {
    await ChatPendingSendPrefs.upsert(
        rec('q_text', kind: 'text', content: 'who is this for?'));
    await ChatPendingSendPrefs.upsert(
        rec('q_audio', kind: 'audio', files: [audioPath]));
    await ChatPendingSendPrefs.upsert(
        rec('q_media', kind: 'mediaGroup', files: [mediaPath]));
    await ChatPendingSendPrefs.upsert(rec('k_text',
        kind: 'text', content: 'for buyer 1', receiverId: 'buyer_1'));
    final quarantinedBefore = {
      for (final e in (await stored()).entries)
        if (e.key.startsWith('q_')) e.key: e.value,
    };

    await OutgoingChatSendService.instance.recoverPendingSends();
    await pumpEventQueue();

    expect(FakeApiServer.chatSendCallCount, 1,
        reason: 'only the known-recipient record is retried');
    expect(FakeApiServer.chatSendIdempotencyKeys, ['key-k_text'],
        reason: 'the retry reuses the record\'s own idempotency key');

    final after = await stored();
    expect(after.containsKey('k_text'), isFalse,
        reason: 'a successful retry removes the pending record');
    expect({
      for (final e in after.entries)
        if (e.key.startsWith('q_')) e.key: e.value,
    }, quarantinedBefore);
  });

  test('known-recipient audio and media-group records retry normally',
      () async {
    await ChatPendingSendPrefs.upsert(rec('k_audio',
        kind: 'audio', receiverId: 'buyer_2', files: [audioPath]));
    await ChatPendingSendPrefs.upsert(rec('k_media',
        kind: 'mediaGroup', receiverId: 'buyer_2', files: [mediaPath]));

    await OutgoingChatSendService.instance.recoverPendingSends();
    // Multipart bodies stream from disk (real IO): wait until both arrived.
    for (var i = 0;
        i < 200 && FakeApiServer.chatSendCallCount < 2;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await pumpEventQueue();

    expect(FakeApiServer.chatSendCallCount, 2);
    expect(FakeApiServer.chatSendIdempotencyKeys.toSet(),
        {'key-k_audio', 'key-k_media'});
  });

  test('account ownership still gates recovery: another account\'s '
      'known-recipient record is neither sent nor removed', () async {
    await ChatPendingSendPrefs.upsert(rec('other_known',
        kind: 'text',
        owner: 'someone_else',
        content: 'not yours',
        receiverId: 'buyer_1'));
    await ChatPendingSendPrefs.upsert(rec('other_unknown',
        kind: 'text', owner: 'someone_else', content: 'not yours either'));
    final before = await stored();

    await OutgoingChatSendService.instance.recoverPendingSends();
    await pumpEventQueue();

    expect(FakeApiServer.chatSendCallCount, 0);
    expect(await stored(), before);
  });
}
