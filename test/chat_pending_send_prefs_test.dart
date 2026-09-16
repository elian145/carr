import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/shared/prefs/chat_pending_send_prefs.dart';

/// F-11: unit coverage for the durable pending-chat-send store itself,
/// independent of any network/service behavior.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ChatPendingSendRecord buildRecord({
    String id = 'temp-1',
    String conversationId = 'car_1',
    String kind = 'text',
    String idempotencyKey = 'chat-send-key-1',
    String? content = 'hello',
    int attempts = 1,
    int? lastAttemptAt,
    List<String> filePaths = const <String>[],
  }) {
    return ChatPendingSendRecord(
      id: id,
      conversationId: conversationId,
      kind: kind,
      idempotencyKey: idempotencyKey,
      content: content,
      filePaths: filePaths,
      createdAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      attempts: attempts,
      lastAttemptAt: lastAttemptAt,
    );
  }

  test('upsert then loadAll round-trips every field', () async {
    await ChatPendingSendPrefs.upsert(buildRecord(
      lastAttemptAt: 1234,
      filePaths: const ['/tmp/a.jpg', '/tmp/b.jpg'],
    ));

    final all = await ChatPendingSendPrefs.loadAll();
    expect(all, hasLength(1));
    final rec = all.single;
    expect(rec.id, 'temp-1');
    expect(rec.conversationId, 'car_1');
    expect(rec.kind, 'text');
    expect(rec.idempotencyKey, 'chat-send-key-1');
    expect(rec.content, 'hello');
    expect(rec.attempts, 1);
    expect(rec.lastAttemptAt, 1234);
    expect(rec.filePaths, ['/tmp/a.jpg', '/tmp/b.jpg']);
  });

  test('loadForConversation only returns matching conversation ids', () async {
    await ChatPendingSendPrefs.upsert(buildRecord(id: 't1', conversationId: 'car_1'));
    await ChatPendingSendPrefs.upsert(buildRecord(id: 't2', conversationId: 'car_2'));

    final forCar1 = await ChatPendingSendPrefs.loadForConversation('car_1');
    expect(forCar1.map((r) => r.id), ['t1']);
  });

  test('upsert with an existing id updates in place (no duplicate entries)', () async {
    await ChatPendingSendPrefs.upsert(buildRecord(id: 't1', attempts: 1));
    await ChatPendingSendPrefs.upsert(buildRecord(id: 't1', attempts: 2));

    final all = await ChatPendingSendPrefs.loadAll();
    expect(all, hasLength(1));
    expect(all.single.attempts, 2);
  });

  test('remove deletes exactly the matching record and is idempotent', () async {
    await ChatPendingSendPrefs.upsert(buildRecord(id: 't1'));
    await ChatPendingSendPrefs.upsert(buildRecord(id: 't2'));

    await ChatPendingSendPrefs.remove('t1');
    var all = await ChatPendingSendPrefs.loadAll();
    expect(all.map((r) => r.id), ['t2']);

    // Removing again (or an id that was never persisted) must not throw
    // and must not affect the remaining record.
    await ChatPendingSendPrefs.remove('t1');
    await ChatPendingSendPrefs.remove('never-existed');
    all = await ChatPendingSendPrefs.loadAll();
    expect(all.map((r) => r.id), ['t2']);
  });

  test('removing the last record clears the underlying prefs key entirely', () async {
    await ChatPendingSendPrefs.upsert(buildRecord(id: 't1'));
    await ChatPendingSendPrefs.remove('t1');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(ChatPendingSendPrefs.prefsKey), isNull);
    expect(await ChatPendingSendPrefs.loadAll(), isEmpty);
  });

  test('a record with a missing idempotencyKey/conversationId/id/kind is dropped on load '
      '(defensive against corrupt/partial prefs data)', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      ChatPendingSendPrefs.prefsKey,
      '[{"id":"t1","conversationId":"car_1","kind":"text"}]', // no idempotencyKey
    );
    expect(await ChatPendingSendPrefs.loadAll(), isEmpty);
  });

  test('toJson never includes anything resembling an auth token/header', () async {
    final rec = buildRecord(content: 'hello world');
    final json = rec.toJson();
    // Only expected keys are present — nothing token/auth/header shaped.
    expect(
      json.keys,
      containsAll(<String>['id', 'conversationId', 'kind', 'idempotencyKey']),
    );
    expect(json.keys.any((k) => k.toLowerCase().contains('token')), isFalse);
    expect(json.keys.any((k) => k.toLowerCase().contains('auth')), isFalse);
  });
}
