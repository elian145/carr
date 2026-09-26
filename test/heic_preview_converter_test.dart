// HEIC/HEIF Sell-photo preview fix (real-device evidence): a picked Samsung
// photo can be HEIC/HEIF (durably copied as e.g.
// `listing_orig_125689253.heif`), and Flutter's own Skia decoders --
// `Image.file`/`Image.memory`/`ui.instantiateImageCodec` -- cannot decode
// HEIC/HEIF at all:
//
//   Image.file failed: Exception: Could not decompress image
//   XFile.readAsBytes() succeeds: 1758621 bytes loaded
//   Image.memory also fails: Exception: Could not decompress image
//   image/vnd.android.heic ... Format is not supported
//   FlutterImageDecoderImplDefault: Failed to decode image
//
// Fix: `_pickedImageMedia` (sell_step4_logic.dart) generates a JPEG
// preview copy for HEIC/HEIF originals via `HeicPreviewConverter`, which
// now calls a small NATIVE Android decoder (`HeifPreviewDecoder.kt`, via
// the `carzo/heif_preview` MethodChannel) built on
// `io.github.awxkee:avif-coder:2.2.1` -- chosen specifically because it
// bundles its own libheif/libde265 and never touches
// `BitmapFactory`/`ImageDecoder`, unlike every maintained Flutter plugin
// audited (including a first attempt with `flutter_image_compress`, which
// real-device logs proved ALSO fails on this exact file because its
// Android decode path is `BitmapFactory`-based). The result is stored as a
// new, purely-additive `preview_source` field via
// `ListingImageMedia.map(..., previewSource: ...)`. The original
// HEIC/HEIF `source`/`localFile()` are never touched -- upload/submission
// keeps reading those directly, unaffected.
//
// These tests cover the 4 originally-requested properties (1-4, pure Dart
// logic against `ListingImageMedia`) PLUS `MethodChannel` mocking for the
// new native call (5), covering success and failure -- these do NOT (and
// cannot, under `flutter test`) prove the native Kotlin/avif-coder code
// actually decodes a real Samsung HEIF file; they only prove
// `HeicPreviewConverter.ensureJpegPreview` calls the channel correctly and
// handles both a successful native reply and a thrown `PlatformException`
// without crashing:
//   1. HEIF original source keeps its original upload path.
//   2. The JPEG preview path is what's used for local rendering.
//   3. A normal JPEG/PNG does not get unnecessarily converted.
//   4. The blur-choice "Original photos" preview uses previewSource, while
//      submission code still uses originalSource.
//   5. `ensureJpegPreview` invokes `carzo/heif_preview#decodeHeifToJpeg`
//      with the right arguments, persists a successful reply, and returns
//      `null` (never throws) when the native side errors.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:car_listing_app/shared/listings/heic_preview_converter.dart';
import 'package:car_listing_app/shared/listings/listing_image_media.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  group('HeicPreviewConverter.isHeic', () {
    test('flags .heic and .heif (case-insensitive) as needing conversion', () {
      expect(HeicPreviewConverter.isHeic('/tmp/listing_orig_1.heic'), isTrue);
      expect(HeicPreviewConverter.isHeic('/tmp/listing_orig_1.heif'), isTrue);
      expect(HeicPreviewConverter.isHeic('/tmp/listing_orig_1.HEIC'), isTrue);
      expect(HeicPreviewConverter.isHeic('/tmp/listing_orig_1.HEIF'), isTrue);
      expect(
        HeicPreviewConverter.isHeic(
          '/data/sell_draft_media/default/listing_orig_125689253.heif',
        ),
        isTrue,
        reason: 'must match the exact real-device filename shape',
      );
    });

    test(
      '(3) never flags JPEG/PNG/etc -- normal photos must not get run '
      'through conversion at all',
      () {
        expect(HeicPreviewConverter.isHeic('/tmp/photo.jpg'), isFalse);
        expect(HeicPreviewConverter.isHeic('/tmp/photo.jpeg'), isFalse);
        expect(HeicPreviewConverter.isHeic('/tmp/photo.png'), isFalse);
        expect(HeicPreviewConverter.isHeic('/tmp/photo.webp'), isFalse);
        expect(HeicPreviewConverter.isHeic(''), isFalse);
      },
    );
  });

  group('ListingImageMedia previewSource / previewLocalFile', () {
    test(
      '(1) HEIF original source() / localFile() keep pointing at the '
      'original .heif path even after a JPEG preview is generated -- '
      'upload/submission is unaffected',
      () {
        const originalHeif =
            '/data/sell_draft_media/default/listing_orig_125689253.heif';
        const jpegPreview =
            '/data/sell_draft_media/default/listing_preview_9001.jpg';

        final media = ListingImageMedia.map(
          XFile(originalHeif),
          previewSource: jpegPreview,
        );

        expect(ListingImageMedia.source(media), originalHeif);
        expect(ListingImageMedia.localFile(media)?.path, originalHeif);
        expect(p.extension(ListingImageMedia.source(media)), '.heif');
      },
    );

    test(
      '(2) previewLocalFile()/previewSource() resolve to the generated '
      'JPEG preview when one exists -- this is what local rendering '
      '(Step4 grid, blur-choice grid) must use',
      () {
        const originalHeif =
            '/data/sell_draft_media/default/listing_orig_125689253.heif';
        const jpegPreview =
            '/data/sell_draft_media/default/listing_preview_9001.jpg';

        final media = ListingImageMedia.map(
          XFile(originalHeif),
          previewSource: jpegPreview,
        );

        expect(ListingImageMedia.previewSource(media), jpegPreview);
        expect(ListingImageMedia.previewLocalFile(media)?.path, jpegPreview);
        expect(
          ListingImageMedia.previewLocalFile(media)?.path,
          isNot(ListingImageMedia.source(media)),
          reason: 'the preview path must be a DIFFERENT file from the '
              'original -- the original is never replaced',
        );
      },
    );

    test(
      '(3) a normal JPEG with no preview_source falls back to '
      'localFile()/source() unchanged -- previewLocalFile() must never '
      'invent a conversion for a format that already renders fine',
      () {
        final media = ListingImageMedia.map(XFile('/tmp/photo.jpg'));

        expect(ListingImageMedia.previewSource(media), isNull);
        expect(
          ListingImageMedia.previewLocalFile(media)?.path,
          ListingImageMedia.localFile(media)?.path,
        );
        expect(ListingImageMedia.previewLocalFile(media)?.path, '/tmp/photo.jpg');
      },
    );

    test(
      'previewLocalFile() falls back to localFile() for a HEIC entry that '
      'has no preview yet (conversion still running or failed) -- must not '
      'crash or return null just because no preview exists',
      () {
        const originalHeif = '/tmp/listing_orig_125689253.heif';
        final media = ListingImageMedia.map(XFile(originalHeif));

        expect(ListingImageMedia.previewSource(media), isNull);
        expect(ListingImageMedia.previewLocalFile(media)?.path, originalHeif);
      },
    );

    test(
      'map() preserves an existing preview_source across an unrelated '
      'update (e.g. the durable-copy step rewriting source) when '
      'previewSource is not explicitly passed again',
      () {
        final withPreview = ListingImageMedia.map(
          XFile('/tmp/listing_orig_1.heif'),
          previewSource: '/tmp/listing_preview_1.jpg',
        );
        // Simulates SellDraftMediaPersistence rewriting `source` after a
        // durable copy, without touching previewSource.
        final afterDurableCopy = ListingImageMedia.map(
          withPreview,
          source: '/data/sell_draft_media/default/listing_orig_abc123.heif',
        );

        expect(
          ListingImageMedia.source(afterDurableCopy),
          '/data/sell_draft_media/default/listing_orig_abc123.heif',
        );
        expect(
          ListingImageMedia.previewSource(afterDurableCopy),
          '/tmp/listing_preview_1.jpg',
          reason: 'preview_source must survive a source-only update -- it '
              'is an independent, separately-persisted file',
        );
      },
    );
  });

  group(
    '(4) static wiring: blur-choice "Original photos" preview uses '
    'previewSource; submission/upload code still uses originalSource',
    () {
      late String blurChoiceContent;
      late String step4Content;
      late String uploadContent;

      setUpAll(() {
        blurChoiceContent = File(
          p.join('lib', 'features', 'sell', 'sell_step_blur_choice_build.dart'),
        ).readAsStringSync();
        step4Content = File(
          p.join('lib', 'features', 'sell', 'sell_step4_build_photos.dart'),
        ).readAsStringSync();
        uploadContent = File(
          p.join('lib', 'features', 'sell', 'sell_listing_media_upload.dart'),
        ).readAsStringSync();
      });

      test(
        '_blurPreviewGrid (shared by the "Original photos" AND "Blurred" '
        'grids on the blur-choice screen) resolves local files via '
        'previewLocalFile, not the raw localFile',
        () {
          expect(
            blurChoiceContent.contains('ListingImageMedia.previewLocalFile('),
            isTrue,
          );
          expect(
            blurChoiceContent.contains('ListingImageMedia.localFile('),
            isFalse,
            reason: '_blurPreviewGrid must not fall back to raw localFile() '
                'directly -- previewLocalFile() already does that '
                'internally for every case with no preview',
          );
        },
      );

      test(
        'Step4 selected-photo grid resolves local files via '
        'previewLocalFile, not the raw localFile',
        () {
          expect(
            step4Content.contains('ListingImageMedia.previewLocalFile('),
            isTrue,
          );
        },
      );

      test(
        'submission/upload code never reads previewSource/previewLocalFile '
        '-- it must keep using source()/localFile() (the real original) '
        'exclusively',
        () {
          expect(uploadContent.contains('previewLocalFile'), isFalse);
          expect(uploadContent.contains('previewSource'), isFalse);
          expect(uploadContent.contains('ListingImageMedia.source('), isTrue);
          expect(uploadContent.contains('ListingImageMedia.localFile('), isTrue);
        },
      );
    },
  );

  group('(5) ensureJpegPreview <-> carzo/heif_preview MethodChannel', () {
    // NOTE: these mock the CHANNEL, not the native Kotlin/avif-coder code.
    // They prove the Dart plumbing (arguments sent, success reply handled,
    // failure reply handled without throwing) -- they do NOT, and cannot,
    // prove the real HeifPreviewDecoder.kt/avif-coder decode actually
    // works on a real Samsung HEIF file. That can only be confirmed on a
    // real device.
    const channel = MethodChannel('carzo/heif_preview');
    late Directory tempDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = Directory.systemTemp.createTempSync('heic_preview_test_');
      final docsDir = Directory('${tempDir.path}/docs')
        ..createSync(recursive: true);
      PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort cleanup; a leftover temp dir must never fail a test.
      }
    });

    test(
      'success: invokes decodeHeifToJpeg with bytes/maxDimension/quality '
      'and persists the returned JPEG bytes under the draft, returning a '
      '.jpg path',
      () async {
        Map<Object?, Object?>? capturedArgs;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'decodeHeifToJpeg');
          capturedArgs = call.arguments as Map<Object?, Object?>;
          return Uint8List.fromList(List<int>.filled(64, 0xFF));
        });

        final heicBytes = Uint8List.fromList(List<int>.filled(128, 0x01));
        final path = await HeicPreviewConverter.ensureJpegPreview(
          heicBytes,
          draftId: 'draft-1',
        );

        expect(capturedArgs, isNotNull);
        expect(capturedArgs!['bytes'], orderedEquals(heicBytes));
        expect(capturedArgs!['maxDimension'], 2048);
        expect(capturedArgs!['quality'], 90);

        expect(path, isNotNull);
        expect(p.extension(path!), '.jpg');
        expect(File(path).existsSync(), isTrue);
        expect(File(path).readAsBytesSync().length, 64);
      },
    );

    test(
      'failure: a thrown PlatformException (native decode error) is '
      'caught -- ensureJpegPreview returns null, never throws',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'heif_preview_decode_failed',
            message: 'native decode error (simulated)',
          );
        });

        final heicBytes = Uint8List.fromList(List<int>.filled(128, 0x02));
        final path = await HeicPreviewConverter.ensureJpegPreview(
          heicBytes,
          draftId: 'draft-2',
        );

        expect(path, isNull);
      },
    );

    test(
      'failure: a null/empty reply (decode produced nothing) is treated '
      'the same as failure -- returns null, does not persist an empty file',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => null);

        final heicBytes = Uint8List.fromList(List<int>.filled(128, 0x03));
        final path = await HeicPreviewConverter.ensureJpegPreview(
          heicBytes,
          draftId: 'draft-3',
        );

        expect(path, isNull);
      },
    );

    test(
      'empty input bytes short-circuit without ever invoking the channel',
      () async {
        var invoked = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          invoked = true;
          return Uint8List(0);
        });

        final path = await HeicPreviewConverter.ensureJpegPreview(
          Uint8List(0),
          draftId: 'draft-4',
        );

        expect(path, isNull);
        expect(invoked, isFalse);
      },
    );
  });
}
