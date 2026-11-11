import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/media/remote_video_thumbnail.dart';

void main() {
  const url = 'https://cdn.example.com/v/clip.mp4';
  final jpeg = Uint8List.fromList(const [0xFF, 0xD8, 1, 2, 3]);
  late DateTime now;

  setUp(() {
    now = DateTime(2030, 1, 1, 12);
    RemoteVideoThumbnail.debugReset();
    RemoteVideoThumbnail.debugNow = () => now;
  });

  tearDown(RemoteVideoThumbnail.debugReset);

  test('800 ms throws MissingPluginException, 0 ms succeeds -> ok via 0 ms',
      () async {
    final calls = <int>[];
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      calls.add(t);
      if (t == 800) throw MissingPluginException('data');
      return jpeg;
    };
    final r = await RemoteVideoThumbnail.generate(url);
    expect(r.ok, isTrue);
    expect(r.bytes, jpeg);
    expect(r.timeMsUsed, 0);
    expect(calls, [800, 0]);
    expect(RemoteVideoThumbnail.debugFailureCount(url), 0);
  });

  test('800 ms succeeds -> 0 ms is never attempted', () async {
    final calls = <int>[];
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      calls.add(t);
      return jpeg;
    };
    final r = await RemoteVideoThumbnail.generate(url);
    expect(r.ok, isTrue);
    expect(r.timeMsUsed, 800);
    expect(calls, [800]);
  });

  test('800 ms returns null/empty, 0 ms succeeds -> falls back too', () async {
    final calls = <int>[];
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      calls.add(t);
      return t == 800 ? Uint8List(0) : jpeg;
    };
    final r = await RemoteVideoThumbnail.generate(url);
    expect(r.timeMsUsed, 0);
    expect(calls, [800, 0]);
  });

  test('preferredTimeMs 0 only tries 0 ms once', () async {
    final calls = <int>[];
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      calls.add(t);
      return jpeg;
    };
    await RemoteVideoThumbnail.generate(url, preferredTimeMs: 0);
    expect(calls, [0]);
  });

  test('both attempts fail -> not ok, never throws, any exception type',
      () async {
    final calls = <int>[];
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      calls.add(t);
      if (t == 800) throw MissingPluginException('data');
      throw StateError('boom');
    };
    final r = await RemoteVideoThumbnail.generate(url);
    expect(r.ok, isFalse);
    expect(r.bytes, isNull);
    expect(r.throttled, isFalse);
    expect(calls, [800, 0]);
    expect(RemoteVideoThumbnail.debugFailureCount(url), 1);
  });

  test('remote failure is throttled with growing backoff, then retried',
      () async {
    var calls = 0;
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      calls++;
      throw MissingPluginException('data');
    };
    await RemoteVideoThumbnail.generate(url);
    expect(calls, 2);

    // Poll ticks every 2 s inside the 15 s window: no plugin calls.
    for (var i = 0; i < 5; i++) {
      now = now.add(const Duration(seconds: 2));
      final r = await RemoteVideoThumbnail.generate(url);
      expect(r.ok, isFalse);
      expect(r.throttled, isTrue);
    }
    expect(calls, 2);

    // Backoff elapsed -> one more full attempt chain; window doubles.
    now = now.add(const Duration(seconds: 10));
    final r2 = await RemoteVideoThumbnail.generate(url);
    expect(r2.throttled, isFalse);
    expect(calls, 4);
    expect(RemoteVideoThumbnail.debugFailureCount(url), 2);

    now = now.add(const Duration(seconds: 20)); // < 30 s second window
    expect((await RemoteVideoThumbnail.generate(url)).throttled, isTrue);
    expect(calls, 4);
    now = now.add(const Duration(seconds: 11));
    await RemoteVideoThumbnail.generate(url);
    expect(calls, 6);
  });

  test('backoffFor schedule: 15s,30s,60s,120s,240s then capped at 300s', () {
    expect(
      [for (var n = 1; n <= 8; n++) RemoteVideoThumbnail.backoffFor(n).inSeconds],
      [15, 30, 60, 120, 240, 300, 300, 300],
    );
    expect(RemoteVideoThumbnail.backoffFor(0), Duration.zero);
  });

  test('a later success clears the failure state', () async {
    var fail = true;
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      if (fail) throw MissingPluginException('data');
      return jpeg;
    };
    await RemoteVideoThumbnail.generate(url);
    expect(RemoteVideoThumbnail.debugFailureCount(url), 1);
    fail = false;
    now = now.add(const Duration(seconds: 16));
    expect((await RemoteVideoThumbnail.generate(url)).ok, isTrue);
    expect(RemoteVideoThumbnail.debugFailureCount(url), 0);
  });

  test('success is cached for remote URLs (no second plugin call)', () async {
    var calls = 0;
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      calls++;
      return jpeg;
    };
    await RemoteVideoThumbnail.generate(url);
    final again = await RemoteVideoThumbnail.generate(url);
    expect(again.ok, isTrue);
    expect(again.fromCache, isTrue);
    expect(calls, 1);
  });

  test('concurrent callers for one URL share a single attempt chain',
      () async {
    var calls = 0;
    final gate = Completer<void>();
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      calls++;
      await gate.future;
      return jpeg;
    };
    final a = RemoteVideoThumbnail.generate(url);
    final b = RemoteVideoThumbnail.generate(url);
    final c = RemoteVideoThumbnail.generate(url);
    gate.complete();
    final rs = await Future.wait([a, b, c]);
    expect(rs.every((r) => r.ok), isTrue);
    expect(calls, 1);
  });

  test('local paths are never cached or throttled (file may appear later)',
      () async {
    var calls = 0;
    var exists = false;
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      calls++;
      if (!exists) throw MissingPluginException('data');
      return jpeg;
    };
    const path = '/data/user/0/app/cache/video.mp4';
    expect((await RemoteVideoThumbnail.generate(path)).ok, isFalse);
    expect(calls, 2);
    exists = true;
    expect((await RemoteVideoThumbnail.generate(path)).ok, isTrue);
    expect((await RemoteVideoThumbnail.generate(path)).fromCache, isFalse);
  });

  test('empty url -> failure without any plugin call', () async {
    var calls = 0;
    RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
      calls++;
      return jpeg;
    };
    expect((await RemoteVideoThumbnail.generate('  ')).ok, isFalse);
    expect(calls, 0);
  });
}
