// Unit tests for `ServerTranscodeVideoSpec` / `ServerTranscodeVideoState`
// (see `lib/features/sell/sell_server_transcode_video.dart`) -- pure
// JSON round-trip / model-shape tests, plus a check that neither type
// ever accidentally grows a presigned-URL field (task section 3: "Do NOT
// persist presigned URLs").
import 'package:car_listing_app/features/sell/sell_server_transcode_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerTranscodeVideoSpec', () {
    test('toJson/fromJson round-trips every field', () {
      const spec = ServerTranscodeVideoSpec(
        draftMediaId: 'vst_123_456',
        localSourcePath: '/data/app/sell_draft_media/d1/video_src_abc.mov',
        sourceByteSize: 123456789,
        sourceMimeType: 'video/quicktime',
      );

      final decoded = ServerTranscodeVideoSpec.fromJson(spec.toJson())!;

      expect(decoded.draftMediaId, spec.draftMediaId);
      expect(decoded.localSourcePath, spec.localSourcePath);
      expect(decoded.sourceByteSize, spec.sourceByteSize);
      expect(decoded.sourceMimeType, spec.sourceMimeType);
    });

    test('fromJson returns null for a missing draft_media_id/local_source_path', () {
      expect(ServerTranscodeVideoSpec.fromJson({'source_byte_size': 1}), isNull);
      expect(ServerTranscodeVideoSpec.fromJson('not a map'), isNull);
      expect(ServerTranscodeVideoSpec.fromJson(null), isNull);
    });

    test('listFromJson/listToJson round-trips a list, skipping malformed entries', () {
      const a = ServerTranscodeVideoSpec(
        draftMediaId: 'v1',
        localSourcePath: '/tmp/a.mov',
        sourceByteSize: 10,
        sourceMimeType: 'video/quicktime',
      );
      const b = ServerTranscodeVideoSpec(
        draftMediaId: 'v2',
        localSourcePath: '/tmp/b.mp4',
        sourceByteSize: 20,
        sourceMimeType: 'video/mp4',
      );
      final raw = [
        ...ServerTranscodeVideoSpec.listToJson([a, b]),
        {'garbage': true},
      ];

      final decoded = ServerTranscodeVideoSpec.listFromJson(raw);

      expect(decoded.length, 2);
      expect(decoded[0].draftMediaId, 'v1');
      expect(decoded[1].draftMediaId, 'v2');
    });

    test('listFromJson returns empty for non-list input', () {
      expect(ServerTranscodeVideoSpec.listFromJson(null), isEmpty);
      expect(ServerTranscodeVideoSpec.listFromJson('nope'), isEmpty);
    });
  });

  group('ServerTranscodeVideoState', () {
    test('initial() starts at requiresServerTranscode with no task/attach state', () {
      final state = ServerTranscodeVideoState.initial('v1');

      expect(state.status, ServerTranscodeVideoStatus.requiresServerTranscode);
      expect(state.taskId, isNull);
      expect(state.putConfirmed, isFalse);
      expect(state.transcodeConfirmed, isFalse);
      expect(state.attachedVideo, isNull);
      expect(state.featureDisabled, isFalse);
      expect(state.isTerminal, isFalse);
    });

    test('toJson never includes any key that could hold a presigned URL', () {
      final state = ServerTranscodeVideoState.initial('v1').copyWith(
        status: ServerTranscodeVideoStatus.sourceStaged,
        putConfirmed: true,
      );
      final json = state.toJson();

      for (final key in json.keys) {
        expect(
          key.toLowerCase().contains('url'),
          isFalse,
          reason: 'no persisted field may ever hold a presigned URL '
              '(found key "$key")',
        );
      }
    });

    test('toJson/fromJson round-trips every field, including attachedVideo', () {
      final state = ServerTranscodeVideoState(
        draftMediaId: 'v1',
        status: ServerTranscodeVideoStatus.attached,
        taskId: 'task-abc',
        putConfirmed: true,
        transcodeConfirmed: true,
        attachedVideo: const {'id': 42, 'video_url': 'https://x/y.mp4'},
        featureDisabled: false,
        lastErrorMessage: null,
        attempts: 0,
        updatedAt: 1234567890,
      );

      final decoded = ServerTranscodeVideoState.fromJson(state.toJson())!;

      expect(decoded.draftMediaId, 'v1');
      expect(decoded.status, ServerTranscodeVideoStatus.attached);
      expect(decoded.taskId, 'task-abc');
      expect(decoded.putConfirmed, isTrue);
      expect(decoded.transcodeConfirmed, isTrue);
      expect(decoded.attachedVideo, {'id': 42, 'video_url': 'https://x/y.mp4'});
      expect(decoded.isTerminal, isTrue);
    });

    test('failedPermanent and attached are terminal; every other status is not', () {
      for (final s in ServerTranscodeVideoStatus.values) {
        final state = ServerTranscodeVideoState.initial('v1').copyWith(status: s);
        final expected = s == ServerTranscodeVideoStatus.attached ||
            s == ServerTranscodeVideoStatus.failedPermanent;
        expect(state.isTerminal, expected, reason: 'status=$s');
      }
    });

    test('copyWith(clearTaskId: true) clears taskId; clearLastError clears the message', () {
      final withTask = ServerTranscodeVideoState.initial('v1').copyWith(
        taskId: 'abc',
        lastErrorMessage: 'boom',
      );
      expect(withTask.taskId, 'abc');
      expect(withTask.lastErrorMessage, 'boom');

      final cleared = withTask.copyWith(clearTaskId: true, clearLastError: true);
      expect(cleared.taskId, isNull);
      expect(cleared.lastErrorMessage, isNull);
    });

    test('mapFromJson/mapToJson round-trips a keyed map, skipping malformed entries', () {
      final a = ServerTranscodeVideoState.initial('v1');
      final b = ServerTranscodeVideoState.initial('v2').copyWith(
        status: ServerTranscodeVideoStatus.attached,
        attachedVideo: const {},
      );
      final raw = {
        ...ServerTranscodeVideoState.mapToJson({'v1': a, 'v2': b}),
        'garbage': {'not': 'valid'},
      };

      final decoded = ServerTranscodeVideoState.mapFromJson(raw);

      expect(decoded.length, 2);
      expect(decoded['v1']!.status, ServerTranscodeVideoStatus.requiresServerTranscode);
      expect(decoded['v2']!.status, ServerTranscodeVideoStatus.attached);
    });

    test('every task-section-3 state name exists on the enum verbatim', () {
      const expectedNames = {
        'localPending',
        'requiresServerTranscode',
        'sourceUploadSigning',
        'sourceUploading',
        'sourceStaged',
        'transcodeQueued',
        'transcodeProcessing',
        'transcodeSucceeded',
        'attaching',
        'attached',
        'failedRecoverable',
        'failedPermanent',
      };
      final actualNames =
          ServerTranscodeVideoStatus.values.map((e) => e.name).toSet();
      expect(actualNames, expectedNames);
    });
  });
}
