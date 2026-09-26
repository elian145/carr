// Unit tests for `SellVideoCompression` (see
// `lib/features/sell/sell_video_compression.dart`), covering the
// real-device regression this file exists for: a 6-second `.mov` at
// 112,329,351 bytes rejected by the backend's exact 100MB hard limit
// (`kk/routes/media.py::upload_car_videos` -> `validate_file_upload(...,
// max_size_mb=100)`).
//
// The native compressor/prober are both stubbed via
// `SellVideoCompression.debugCompressorOverride` /
// `debugProberOverride` -- real native codec calls cannot run under
// `flutter test` (no device/platform channel), so every test here proves
// the DECISION logic (compress vs. skip, success vs. failure vs.
// still-too-large) and the file bookkeeping around it, not the actual
// encode.
import 'dart:io';

import 'package:car_listing_app/features/sell/sell_video_compression.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

/// Creates a file at [path] whose length() reports exactly [bytes] without
/// actually writing that many real bytes to disk (a sparse file via
/// `truncate`) -- fast even for a 100MB+ "size", which matters here since
/// several tests need to exercise the exact real-device 112,329,351-byte
/// scenario.
void _writeSizedFile(String path, int bytes) {
  final file = File(path)..createSync(recursive: true);
  final raf = file.openSync(mode: FileMode.write);
  try {
    if (bytes > 0) raf.truncateSync(bytes);
  } finally {
    raf.closeSync();
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    // Deliberately NOT `Directory.systemTemp` -- on this machine the OS
    // temp drive has very little free space, and several tests below
    // create real (non-sparse-on-this-filesystem) files up to a few
    // hundred MB to exercise the exact byte-threshold logic. The repo
    // checkout's own drive has ample free space.
    final base = Directory(
      p.join(Directory.current.path, '.dart_tool', 'test_tmp'),
    )..createSync(recursive: true);
    tempDir = base.createTempSync('sell_video_compress_');
  });

  tearDown(() {
    SellVideoCompression.debugProberOverride = null;
    SellVideoCompression.debugCompressorOverride = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup; a leftover temp dir must never fail a test.
    }
  });

  group('backend limit mirror (must never drift from kk/routes/media.py)', () {
    test(
      'kSellVideoBackendMaxBytes is EXACTLY 100MB, matching '
      'upload_car_videos\'s validate_file_upload(..., max_size_mb=100)',
      () {
        expect(kSellVideoBackendMaxBytes, 100 * 1024 * 1024);
      },
    );

    test(
      'the backend route source still enforces max_size_mb=100 for '
      'POST /api/cars/<id>/videos -- this task must not raise it, and '
      'this guards against silent drift between the two constants',
      () {
        final content = File(
          p.join('kk', 'routes', 'media.py'),
        ).readAsStringSync();
        final routeIdx = content.indexOf(
          'def upload_car_videos(car_id: str):',
        );
        expect(routeIdx, greaterThanOrEqualTo(0));
        final nextRouteIdx = content.indexOf('\n@bp.route(', routeIdx);
        final body = content.substring(
          routeIdx,
          nextRouteIdx > routeIdx ? nextRouteIdx : content.length,
        );
        expect(
          body.contains('max_size_mb=100'),
          isTrue,
          reason: 'backend hard limit must stay 100MB -- this task must '
              'not raise it',
        );
      },
    );
  });

  group('SellVideoCompression.prepare -- decision logic', () {
    test(
      '6-second real-device scenario: a 112,329,351-byte source over the '
      '100MB backend limit triggers compression, and the compressed '
      'output (under the limit) is what prepare() returns',
      () async {
        final sourcePath = p.join(tempDir.path, 'huge_6s.mov');
        _writeSizedFile(sourcePath, 112329351);
        final outputPath = p.join(tempDir.path, 'compressed_out.mp4');
        _writeSizedFile(outputPath, 8 * 1024 * 1024); // 8MB compressed

        // Path-aware: `prepare()` probes the SOURCE first (decision logic),
        // then -- since section 3 of the Dolby Vision/HDR follow-up task
        // requires verifying the ACTUAL output, never just the requested
        // encoder params -- re-probes its OWN compressed OUTPUT before
        // returning. Both must be handled; a real compressed 1920x1080/
        // 30fps output is exactly what should satisfy that verification.
        final probedPaths = <String>[];
        SellVideoCompression.debugProberOverride = (path) async {
          probedPaths.add(path);
          if (path == outputPath) {
            return const SellVideoProbe(
              sizeBytes: 8 * 1024 * 1024,
              width: 1920,
              height: 1080,
              bitrateBps: 10 * 1000 * 1000,
              frameRateFps: 30,
            );
          }
          return const SellVideoProbe(
            sizeBytes: 112329351,
            width: 1920,
            height: 1080,
            // ~150 Mbps for 6s of 112MB -- matches the real-device report.
            bitrateBps: 150000000,
            durationMs: 6000,
          );
        };

        SellVideoCompressRequest? capturedRequest;
        var compressCallCount = 0;
        SellVideoCompression.debugCompressorOverride = (request) async {
          compressCallCount++;
          capturedRequest = request;
          return SellVideoCompressOutput(outputPath);
        };

        final phases = <String>[];
        final result = await SellVideoCompression.prepare(
          XFile(sourcePath),
          onStatus: phases.add,
        );

        expect(compressCallCount, 1, reason: 'compression must be attempted');
        expect(result.status, SellVideoPrepareStatus.compressed);
        expect(result.didAttemptCompression, isTrue);
        expect(result.ok, isTrue);
        expect(result.file, isNotNull);
        expect(result.file!.path, outputPath);
        expect(result.outputBytes, 8 * 1024 * 1024);
        expect(phases, containsAllInOrder(['probing', 'compressing']));

        // 1920x1080's long edge (1920) is already exactly at the 1080p
        // cap, so no downscale is requested -- only bitrate/fps/codec are
        // re-targeted. This also proves aspect/orientation are preserved
        // (no forced resize away from the source's own dimensions).
        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.targetWidth, isNull);
        expect(capturedRequest!.targetHeight, isNull);
        expect(capturedRequest!.maxFrameRate, kSellVideoMaxFrameRate);
        expect(capturedRequest!.videoBitrateMbps, kSellVideoTargetBitrateMbps);
        expect(
          probedPaths,
          containsAllInOrder([sourcePath, outputPath]),
          reason: 'prepare() probes the source for the compress/skip '
              'decision, then re-probes its own output to verify the '
              'contract before reporting success',
        );
      },
    );

    test(
      'the resulting under-limit file REPLACES the source -- '
      'prepare() never returns the original oversized path once '
      'compression succeeds',
      () async {
        final sourcePath = p.join(tempDir.path, 'huge.mov');
        _writeSizedFile(sourcePath, 112329351);
        final outputPath = p.join(tempDir.path, 'compressed.mp4');
        _writeSizedFile(outputPath, 9 * 1024 * 1024);

        SellVideoCompression.debugProberOverride = (_) async =>
            const SellVideoProbe(sizeBytes: 112329351);
        SellVideoCompression.debugCompressorOverride = (_) async =>
            SellVideoCompressOutput(outputPath);

        final result = await SellVideoCompression.prepare(XFile(sourcePath));

        expect(result.ok, isTrue);
        expect(result.file!.path, isNot(sourcePath));
        expect(result.file!.path, outputPath);
      },
    );

    test(
      'a normal, already-reasonable 1080p/~6Mbps video under the backend '
      'limit is NOT recompressed -- prepare() returns the source '
      'untouched and the compressor is never invoked',
      () async {
        final sourcePath = p.join(tempDir.path, 'normal_1080p.mp4');
        _writeSizedFile(sourcePath, 20 * 1024 * 1024); // 20MB

        SellVideoCompression.debugProberOverride = (_) async =>
            const SellVideoProbe(
              sizeBytes: 20 * 1024 * 1024,
              width: 1920,
              height: 1080,
              bitrateBps: 6 * 1000 * 1000,
              durationMs: 27000,
            );
        var compressCallCount = 0;
        SellVideoCompression.debugCompressorOverride = (_) async {
          compressCallCount++;
          throw StateError('must not be called for a reasonable video');
        };

        final result = await SellVideoCompression.prepare(XFile(sourcePath));

        expect(result.status, SellVideoPrepareStatus.unchanged);
        expect(result.didAttemptCompression, isFalse);
        expect(result.file!.path, sourcePath);
        expect(compressCallCount, 0);
      },
    );

    test(
      'a 4K/high-bitrate video that is already UNDER the backend limit is '
      'still compressed proactively (task: "obviously excessive" videos '
      'compress even if they barely fit)',
      () async {
        final sourcePath = p.join(tempDir.path, '4k_under_limit.mp4');
        _writeSizedFile(sourcePath, 90 * 1024 * 1024); // under 100MB
        final outputPath = p.join(tempDir.path, '4k_compressed.mp4');
        _writeSizedFile(outputPath, 20 * 1024 * 1024);

        // Path-aware: the SOURCE probe reports the original 4K frame; the
        // OUTPUT probe (re-probed by `prepare()` itself after compression,
        // per the Dolby Vision/HDR follow-up's "verify the actual output"
        // contract check) reports what a real encode of this request would
        // actually produce -- the downscaled 1920x1080 frame.
        SellVideoCompression.debugProberOverride = (path) async {
          if (path == outputPath) {
            return const SellVideoProbe(
              sizeBytes: 20 * 1024 * 1024,
              width: 1920,
              height: 1080,
              bitrateBps: 10 * 1000 * 1000,
              frameRateFps: 30,
            );
          }
          return const SellVideoProbe(
            sizeBytes: 90 * 1024 * 1024,
            width: 3840,
            height: 2160,
            bitrateBps: 12 * 1000 * 1000,
            durationMs: 60000,
          );
        };
        SellVideoCompressRequest? capturedRequest;
        SellVideoCompression.debugCompressorOverride = (request) async {
          capturedRequest = request;
          return SellVideoCompressOutput(outputPath);
        };

        final result = await SellVideoCompression.prepare(XFile(sourcePath));

        expect(result.status, SellVideoPrepareStatus.compressed);
        expect(capturedRequest, isNotNull);
        // 3840x2160 downscaled to a 1920 long edge, aspect preserved
        // exactly (16:9 in, 16:9 out) and orientation preserved
        // (landscape in, landscape out).
        expect(capturedRequest!.targetWidth, 1920);
        expect(capturedRequest!.targetHeight, 1080);
      },
    );

    test(
      'a portrait 4K source is downscaled preserving PORTRAIT orientation '
      'and aspect ratio (width/height never swapped)',
      () async {
        final sourcePath = p.join(tempDir.path, 'portrait_4k.mp4');
        _writeSizedFile(sourcePath, 95 * 1024 * 1024);
        final outputPath = p.join(tempDir.path, 'portrait_compressed.mp4');
        _writeSizedFile(outputPath, 15 * 1024 * 1024);

        // Path-aware for the same reason as the landscape 4K test above --
        // the OUTPUT probe must reflect the actual (portrait) downscaled
        // frame, not the 4K source frame.
        SellVideoCompression.debugProberOverride = (path) async {
          if (path == outputPath) {
            return const SellVideoProbe(
              sizeBytes: 15 * 1024 * 1024,
              width: 1080,
              height: 1920,
              bitrateBps: 10 * 1000 * 1000,
              frameRateFps: 30,
            );
          }
          return const SellVideoProbe(
            sizeBytes: 95 * 1024 * 1024,
            width: 2160,
            height: 3840,
            bitrateBps: 14 * 1000 * 1000,
            durationMs: 30000,
          );
        };
        SellVideoCompressRequest? capturedRequest;
        SellVideoCompression.debugCompressorOverride = (request) async {
          capturedRequest = request;
          return SellVideoCompressOutput(outputPath);
        };

        await SellVideoCompression.prepare(XFile(sourcePath));

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.targetWidth, 1080);
        expect(capturedRequest!.targetHeight, 1920);
        expect(
          capturedRequest!.targetHeight! > capturedRequest!.targetWidth!,
          isTrue,
          reason: 'portrait orientation (taller than wide) must survive '
              'the downscale',
        );
      },
    );

    test(
      'compression failure (native throws) prevents the oversized upload: '
      'prepare() reports failed, returns no file, and leaves the '
      'original source completely untouched',
      () async {
        final sourcePath = p.join(tempDir.path, 'huge_fails.mov');
        final originalBytes = List<int>.filled(1024, 0x42);
        File(sourcePath).writeAsBytesSync(originalBytes);

        SellVideoCompression.debugProberOverride = (_) async =>
            const SellVideoProbe(sizeBytes: 150 * 1024 * 1024);
        SellVideoCompression.debugCompressorOverride = (_) async {
          throw SellVideoCompressorFailure('native encoder boom');
        };

        final result = await SellVideoCompression.prepare(XFile(sourcePath));

        expect(result.status, SellVideoPrepareStatus.failed);
        expect(result.ok, isFalse);
        expect(result.file, isNull);
        expect(result.didAttemptCompression, isTrue);
        // Original untouched: same bytes, same path, still on disk.
        expect(File(sourcePath).existsSync(), isTrue);
        expect(File(sourcePath).readAsBytesSync(), originalBytes);
      },
    );

    test(
      'compression "succeeding" with a missing/empty output file is '
      'treated as a failure, not a false success',
      () async {
        final sourcePath = p.join(tempDir.path, 'huge_empty_out.mov');
        _writeSizedFile(sourcePath, 110 * 1024 * 1024);
        final missingOutputPath = p.join(tempDir.path, 'never_written.mp4');

        SellVideoCompression.debugProberOverride = (_) async =>
            const SellVideoProbe(sizeBytes: 110 * 1024 * 1024);
        SellVideoCompression.debugCompressorOverride = (_) async =>
            SellVideoCompressOutput(missingOutputPath);

        final result = await SellVideoCompression.prepare(XFile(sourcePath));

        expect(result.status, SellVideoPrepareStatus.failed);
        expect(result.file, isNull);
      },
    );

    test(
      'a compressed output that is STILL above the backend limit reports '
      'stillTooLarge (actionable "choose a shorter video" error), never '
      'a false success, and best-effort deletes the oversized temp '
      'output',
      () async {
        final sourcePath = p.join(tempDir.path, 'huge_stays_huge.mov');
        _writeSizedFile(sourcePath, 300 * 1024 * 1024);
        final outputPath = p.join(tempDir.path, 'still_huge.mp4');
        _writeSizedFile(outputPath, 101 * 1024 * 1024); // still over 100MB

        SellVideoCompression.debugProberOverride = (_) async =>
            const SellVideoProbe(sizeBytes: 300 * 1024 * 1024);
        SellVideoCompression.debugCompressorOverride = (_) async =>
            SellVideoCompressOutput(outputPath);

        final result = await SellVideoCompression.prepare(XFile(sourcePath));

        expect(result.status, SellVideoPrepareStatus.stillTooLarge);
        expect(result.ok, isFalse);
        expect(result.file, isNull);
        expect(result.outputBytes, 101 * 1024 * 1024);
        expect(
          File(outputPath).existsSync(),
          isFalse,
          reason: 'the oversized temp output must be cleaned up, not left '
              'as an orphaned durable-looking file',
        );
        // Original source is a completely different path and must still
        // exist untouched.
        expect(File(sourcePath).existsSync(), isTrue);
      },
    );

    test(
      'a probe that throws still falls back to a size-only decision '
      '(never crashes the pick, never silently skips a >100MB source)',
      () async {
        final sourcePath = p.join(tempDir.path, 'probe_throws.mov');
        _writeSizedFile(sourcePath, 112329351);
        final outputPath = p.join(tempDir.path, 'probe_throws_out.mp4');
        _writeSizedFile(outputPath, 7 * 1024 * 1024);

        SellVideoCompression.debugProberOverride = (_) async {
          throw StateError('native getMediaInfo boom');
        };
        var compressCallCount = 0;
        SellVideoCompression.debugCompressorOverride = (_) async {
          compressCallCount++;
          return SellVideoCompressOutput(outputPath);
        };

        final result = await SellVideoCompression.prepare(XFile(sourcePath));

        expect(compressCallCount, 1);
        expect(result.status, SellVideoPrepareStatus.compressed);
      },
    );
  });

  group(
    'Phase 3B: SellVideoCompression.prepare -- requiresServerTranscode',
    () {
      test(
        'scenario B: the plugin reporting a TYPED UnsupportedVideoException '
        '(never a string match) is mapped to requiresServerTranscode, with '
        'the UNTOUCHED original source returned as `file` (never dropped, '
        'never routed through the old <=100MB endpoint)',
        () async {
          final sourcePath = p.join(tempDir.path, 'unsupported_codec.mov');
          final originalBytes = List<int>.filled(2048, 0x7);
          File(sourcePath).writeAsBytesSync(originalBytes);

          SellVideoCompression.debugProberOverride = (_) async =>
              const SellVideoProbe(sizeBytes: 150 * 1024 * 1024);
          SellVideoCompression.debugCompressorOverride = (_) async {
            throw SellVideoUnsupportedSourceException(
              'video/dolby-vision error 0xfffffffe (NAME_NOT_FOUND)',
            );
          };

          final result = await SellVideoCompression.prepare(
            XFile(sourcePath),
          );

          expect(
            result.status,
            SellVideoPrepareStatus.requiresServerTranscode,
          );
          expect(result.needsServerTranscode, isTrue);
          expect(result.ok, isFalse);
          expect(result.file, isNotNull);
          expect(result.file!.path, sourcePath);
          expect(result.didAttemptCompression, isTrue);
          // Original untouched: same bytes, same path, still on disk.
          expect(File(sourcePath).existsSync(), isTrue);
          expect(File(sourcePath).readAsBytesSync(), originalBytes);
        },
      );

      test(
        'an ordinary (non-unsupported) compressor failure still maps to '
        'the plain `failed` status, never requiresServerTranscode -- only '
        'the genuine unsupported-codec signal triggers the server '
        'fallback',
        () async {
          final sourcePath = p.join(tempDir.path, 'corrupt.mov');
          File(sourcePath).writeAsBytesSync(List<int>.filled(1024, 0x1));

          SellVideoCompression.debugProberOverride = (_) async =>
              const SellVideoProbe(sizeBytes: 150 * 1024 * 1024);
          SellVideoCompression.debugCompressorOverride = (_) async {
            throw SellVideoCompressorFailure('media info read failed');
          };

          final result = await SellVideoCompression.prepare(
            XFile(sourcePath),
          );

          expect(result.status, SellVideoPrepareStatus.failed);
          expect(result.needsServerTranscode, isFalse);
        },
      );
    },
  );

  group('SellVideoCompression.probe() -- general behavior', () {
    test(
      'probe() (the public helper `_pickVideos` uses for the 30-second '
      'duration cap) returns the exact same value the override supplies, '
      'including durationMs',
      () async {
        SellVideoCompression.debugProberOverride = (_) async =>
            const SellVideoProbe(sizeBytes: 500, durationMs: 45000);

        final probe = await SellVideoCompression.probe(
          XFile(p.join(tempDir.path, 'anything.mp4')),
        );

        expect(probe.durationMs, 45000);
      },
    );

    test(
      'probe() falls back to a size-only probe (never throws) when the '
      'override itself throws',
      () async {
        final sourcePath = p.join(tempDir.path, 'probe_fails.mp4');
        _writeSizedFile(sourcePath, 4096);
        SellVideoCompression.debugProberOverride = (_) async {
          throw Exception('probe boom');
        };

        final probe = await SellVideoCompression.probe(XFile(sourcePath));

        expect(probe.sizeBytes, 4096);
        expect(probe.durationMs, isNull);
      },
    );
  });

  group('isObviouslyExcessive', () {
    test('true for a 4K source even at a modest bitrate', () {
      expect(
        SellVideoCompression.isObviouslyExcessive(
          const SellVideoProbe(
            sizeBytes: 1,
            width: 3840,
            height: 2160,
            bitrateBps: 5 * 1000 * 1000,
          ),
        ),
        isTrue,
      );
    });

    test('true for a very-high-bitrate 1080p source', () {
      expect(
        SellVideoCompression.isObviouslyExcessive(
          const SellVideoProbe(
            sizeBytes: 1,
            width: 1920,
            height: 1080,
            bitrateBps: 20 * 1000 * 1000,
          ),
        ),
        isTrue,
      );
    });

    test('false for a reasonable 1080p/8Mbps source', () {
      expect(
        SellVideoCompression.isObviouslyExcessive(
          const SellVideoProbe(
            sizeBytes: 1,
            width: 1920,
            height: 1080,
            bitrateBps: 8 * 1000 * 1000,
          ),
        ),
        isFalse,
      );
    });

    test('false when resolution/bitrate could not be probed at all', () {
      expect(
        SellVideoCompression.isObviouslyExcessive(
          const SellVideoProbe(sizeBytes: 1),
        ),
        isFalse,
      );
    });
  });
}
