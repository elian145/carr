// Damage-photo counterpart to `heic_preview_converter_test.dart` /
// `sell_step4_immediate_photo_preview_test.dart`.
//
// Root cause (confirmed by reading `sell_step4_logic.dart` /
// `sell_step4_build_damage.dart`): `_pickDamageImages` was explicitly left
// untouched when the HEIC/HEIF preview fix first shipped for listing
// photos -- it inserted the raw picked `XFile`s directly into
// `_damageImages` and never routed them through `_pickedImageMedia`/
// `HeicPreviewConverter` at all, so no `preview_source` was ever generated
// for a damage photo. On top of that, `sell_step4_build_damage.dart`'s own
// grid read `ListingImageMedia.localFile(image)` directly instead of
// `previewLocalFile(image)`, so even a `preview_source` that existed would
// never have been rendered there. Together these are why a HEIF damage
// photo (unlike a HEIF listing photo, already fixed) still failed to
// display on a real device.
//
// Fix reuses the EXISTING utilities -- no new HEIF-decoding code was
// added:
//   - `_backfillDamageImagePreviews` (new, mirrors the existing
//     `_backfillImageDimensions`) calls the EXISTING `_pickedImageMedia`,
//     which already calls the EXISTING `HeicPreviewConverter.
//     ensureJpegPreview` (same native `carzo/heif_preview` decoder used
//     for listing photos).
//   - `sell_step4_build_damage.dart` now calls the EXISTING
//     `ListingImageMedia.previewLocalFile()` instead of `localFile()`.
//
// These tests cover the 6 requested properties:
//   1. HEIF damage image keeps originalSource.
//   2. HEIF damage image gets a JPEG previewSource via the shared pipeline.
//   3. Damage UI (previewLocalFile) renders previewSource when available.
//   4. A JPEG damage image is not unnecessarily converted.
//   5. Durable-copy/state update preserves previewSource for a damage item.
//   6. Damage submission/upload code still uses originalSource, never the
//      preview.
//
// As with `sell_step4_immediate_photo_preview_test.dart`, the wiring
// checks (does `_pickDamageImages` actually call the new backfill, in the
// right order, without duplicating the HEIC-conversion logic) are static
// source-shape assertions rather than a full widget test, because driving
// `image_picker` end-to-end through a widget test would only prove this
// ONE call site stays fixed, not guard against the ordering regressing
// again inside a future edit to the same method. The behavioral
// properties (1-6) are proven against the real, shared
// `HeicPreviewConverter`/`ListingImageMedia`/`SellDraftMediaPersistence`
// utilities with a mocked native channel -- NOT against a reimplemented
// copy of the pipeline.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:car_listing_app/shared/listings/heic_preview_converter.dart';
import 'package:car_listing_app/shared/listings/listing_image_media.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

String _stripDartComments(String source) {
  final buffer = StringBuffer();
  for (final line in source.split('\n')) {
    final idx = line.indexOf('//');
    buffer.writeln(idx == -1 ? line : line.substring(0, idx));
  }
  return buffer.toString();
}

void main() {
  group(
    'static wiring: _pickDamageImages now routes through the shared HEIC '
    'preview pipeline',
    () {
      late String logicContent;
      late String buildDamageContent;
      late String uploadContent;

      setUpAll(() {
        logicContent = _stripDartComments(
          File(
            p.join('lib', 'features', 'sell', 'sell_step4_logic.dart'),
          ).readAsStringSync(),
        );
        buildDamageContent = File(
          p.join('lib', 'features', 'sell', 'sell_step4_build_damage.dart'),
        ).readAsStringSync();
        uploadContent = File(
          p.join('lib', 'features', 'sell', 'sell_listing_media_upload.dart'),
        ).readAsStringSync();
      });

      test(
        '_pickDamageImages inserts the original picked photo immediately, '
        'then generates HEIC previews via _backfillDamageImagePreviews, '
        'strictly BEFORE the durable-copy sync',
        () {
          final pickStart = logicContent.indexOf(
            'Future<void> _pickDamageImages()',
          );
          final pickEnd = logicContent.indexOf(
            'Future<void> _pickVideos()',
            pickStart,
          );
          expect(pickStart, greaterThanOrEqualTo(0));
          expect(pickEnd, greaterThan(pickStart));
          final body = logicContent.substring(pickStart, pickEnd);

          final setStateIdx = body.indexOf(
            '_damageImages = [..._damageImages, ...additions];',
          );
          final backfillIdx = body.indexOf(
            'await _backfillDamageImagePreviews(additions',
          );
          final syncIdx = body.indexOf('await _syncMediaDraftToParent();');

          expect(setStateIdx, greaterThanOrEqualTo(0));
          expect(
            backfillIdx,
            greaterThanOrEqualTo(0),
            reason: '_pickDamageImages must generate HEIC previews via the '
                'shared pipeline, not leave damage photos unconverted',
          );
          expect(
            syncIdx,
            greaterThan(backfillIdx),
            reason: 'the durable-copy sync (which rewrites `source`) must '
                'run AFTER the preview backfill finishes -- otherwise the '
                "backfill's by-path match against _damageImages would "
                'already be stale, the exact bug previously found and '
                'fixed for _pickImages/_backfillImageDimensions',
          );
          expect(
            backfillIdx,
            greaterThan(setStateIdx),
            reason: 'the original picked photo must still render '
                'immediately -- the preview backfill must never run before '
                'that setState',
          );
        },
      );

      test(
        '_backfillDamageImagePreviews reuses the EXISTING _pickedImageMedia '
        '/ HeicPreviewConverter pipeline -- no duplicated HEIF-conversion '
        'logic',
        () {
          final start = logicContent.indexOf(
            'Future<void> _backfillDamageImagePreviews(',
          );
          expect(start, greaterThanOrEqualTo(0));
          var end = logicContent.indexOf(
            '\n  Future<void> _removePhotoAt(',
            start,
          );
          if (end == -1) end = logicContent.length;
          final body = logicContent.substring(start, end);

          expect(
            body.contains('_pickedImageMedia('),
            isTrue,
            reason: 'must reuse the existing _pickedImageMedia helper '
                'instead of reimplementing HEIC detection/conversion',
          );
          expect(body.contains("logContext: '[DAMAGE]'"), isTrue);
          expect(
            body.contains('ListingImageMedia.source(item) == file.path'),
            isTrue,
            reason: 'must match results back onto _damageImages BY PATH, '
                'the same safe-under-reorder mechanism already used for '
                'listing photos',
          );
          expect(body.contains('_damageImages[idx] = enriched'), isTrue);

          // Exactly ONE call site for the actual HEIC conversion in this
          // file -- proves damage reuses the shared implementation rather
          // than duplicating it.
          expect(
            RegExp(
              r'HeicPreviewConverter\.ensureJpegPreview',
            ).allMatches(logicContent).length,
            1,
            reason: 'HeicPreviewConverter.ensureJpegPreview must be called '
                'from exactly one place (_pickedImageMedia); damage photos '
                'must reuse that call, not add a second one',
          );
        },
      );

      test(
        'damage grid (Step4) renders previewLocalFile(), not the raw '
        'localFile() -- same fix already applied to the listing-photo grid',
        () {
          expect(
            buildDamageContent.contains(
              'ListingImageMedia.previewLocalFile(',
            ),
            isTrue,
          );
          expect(
            buildDamageContent.contains('ListingImageMedia.localFile('),
            isFalse,
            reason: 'the damage grid must not fall back to raw localFile() '
                'directly -- previewLocalFile() already does that '
                'internally for every case with no preview',
          );
        },
      );

      test(
        'damage submission/upload code never reads previewSource/'
        'previewLocalFile -- it must keep using source()/localFile() (the '
        'real original HEIF/HEIC) exclusively',
        () {
          expect(uploadContent.contains('previewLocalFile'), isFalse);
          expect(uploadContent.contains('previewSource'), isFalse);
          expect(
            uploadContent.contains('ListingImageMedia.localFile(img)'),
            isTrue,
          );
        },
      );
    },
  );

  group(
    'shared pipeline behavior (identical utilities for damage or listing '
    'photos)',
    () {
      const channel = MethodChannel('carzo/heif_preview');
      late Directory tempDir;

      setUp(() async {
        TestWidgetsFlutterBinding.ensureInitialized();
        tempDir = Directory.systemTemp.createTempSync(
          'damage_heic_preview_test_',
        );
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
        '(1)+(2) a HEIF damage photo keeps its original source AND gets a '
        'JPEG previewSource, produced via the shared '
        'HeicPreviewConverter/native-channel pipeline',
        () async {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'decodeHeifToJpeg');
            return Uint8List.fromList(List<int>.filled(32, 0xAB));
          });

          const originalHeif =
              '/data/sell_draft_media/default/damage_orig_9001.heif';
          final bytes = Uint8List.fromList(List<int>.filled(64, 0x01));
          final previewPath = await HeicPreviewConverter.ensureJpegPreview(
            bytes,
            draftId: 'draft-damage-1',
          );

          final damageMedia = ListingImageMedia.map(
            XFile(originalHeif),
            previewSource: previewPath,
          );

          // (1) original source untouched.
          expect(ListingImageMedia.source(damageMedia), originalHeif);
          expect(ListingImageMedia.localFile(damageMedia)?.path, originalHeif);
          expect(p.extension(ListingImageMedia.source(damageMedia)), '.heif');

          // (2) a JPEG previewSource was produced.
          expect(previewPath, isNotNull);
          expect(p.extension(previewPath!), '.jpg');
          expect(ListingImageMedia.previewSource(damageMedia), previewPath);
        },
      );

      test(
        '(3) damage UI (previewLocalFile) resolves to the generated JPEG '
        'preview when one exists, and it differs from the original file',
        () {
          const originalHeif =
              '/data/sell_draft_media/default/damage_orig_9001.heif';
          const jpegPreview =
              '/data/sell_draft_media/default/listing_preview_9001.jpg';
          final damageMedia = ListingImageMedia.map(
            XFile(originalHeif),
            previewSource: jpegPreview,
          );

          expect(
            ListingImageMedia.previewLocalFile(damageMedia)?.path,
            jpegPreview,
          );
          expect(
            ListingImageMedia.previewLocalFile(damageMedia)?.path,
            isNot(ListingImageMedia.source(damageMedia)),
            reason: 'the preview path must be a DIFFERENT file from the '
                'original -- the original is never replaced',
          );
        },
      );

      test(
        '(4) a normal JPEG damage photo is never converted -- isHeic is '
        'false and previewLocalFile falls back to localFile unchanged',
        () {
          expect(
            HeicPreviewConverter.isHeic('/tmp/damage_photo.jpg'),
            isFalse,
          );
          final damageMedia = ListingImageMedia.map(
            XFile('/tmp/damage_photo.jpg'),
          );
          expect(ListingImageMedia.previewSource(damageMedia), isNull);
          expect(
            ListingImageMedia.previewLocalFile(damageMedia)?.path,
            ListingImageMedia.localFile(damageMedia)?.path,
          );
          expect(
            ListingImageMedia.previewLocalFile(damageMedia)?.path,
            '/tmp/damage_photo.jpg',
          );
        },
      );

      test(
        '(5a) map()-level durable-copy/state update (source-only rewrite) '
        'preserves an existing damage previewSource',
        () {
          final withPreview = ListingImageMedia.map(
            XFile('/tmp/damage_orig_1.heif'),
            previewSource: '/tmp/damage_preview_1.jpg',
          );
          // Simulates the durable-copy step (`_persistDynamicMediaListImpl`)
          // rewriting `source` after copying into sell_draft_media, without
          // touching previewSource.
          final afterDurableCopy = ListingImageMedia.map(
            withPreview,
            source: '/data/sell_draft_media/default/damage_abc123.heif',
          );

          expect(
            ListingImageMedia.source(afterDurableCopy),
            '/data/sell_draft_media/default/damage_abc123.heif',
          );
          expect(
            ListingImageMedia.previewSource(afterDurableCopy),
            '/tmp/damage_preview_1.jpg',
            reason: 'preview_source must survive a source-only update for '
                'damage photos too -- same guarantee already proven for '
                'listing photos',
          );
        },
      );

      test(
        '(5b) SellDraftMediaPersistence.persistDynamicMediaList -- the '
        'REAL durable-copy call _syncMediaDraftToParent/_saveDraft make for '
        '_damageImages -- preserves previewSource end-to-end',
        () async {
          final srcDir = Directory('${tempDir.path}/picked')
            ..createSync(recursive: true);
          final srcFile = File(p.join(srcDir.path, 'damage_orig_1.heif'))
            ..writeAsBytesSync(List<int>.filled(100, 0x02));
          final previewFile = File(
            p.join(srcDir.path, 'damage_preview_1.jpg'),
          )..writeAsBytesSync(List<int>.filled(20, 0x03));

          final damageEntry = ListingImageMedia.map(
            XFile(srcFile.path),
            previewSource: previewFile.path,
          );

          final persisted =
              await SellDraftMediaPersistence.persistDynamicMediaList(
            [damageEntry],
            draftId: 'draft-damage-5b',
            namePrefix: 'damage',
          );

          expect(persisted, hasLength(1));
          final persistedSource = ListingImageMedia.source(persisted.first);
          expect(
            persistedSource,
            isNot(srcFile.path),
            reason: 'the durable copy must rewrite source into '
                'sell_draft_media, exactly like it does for listing photos',
          );
          expect(
            ListingImageMedia.previewSource(persisted.first),
            previewFile.path,
            reason: 'previewSource must survive the exact durable-copy call '
                '_syncMediaDraftToParent uses for _damageImages -- this is '
                'the same path-rewrite/backfill hazard previously found '
                'and fixed for _pickImages',
          );
        },
      );

      test(
        '(6) damage submission reads (source()/localFile()) never return '
        'the preview -- upload must use the original HEIF/HEIC',
        () {
          const originalHeif = '/tmp/damage_orig_1.heif';
          const jpegPreview = '/tmp/damage_preview_1.jpg';
          final damageMedia = ListingImageMedia.map(
            XFile(originalHeif),
            previewSource: jpegPreview,
          );

          // This is exactly what sell_listing_media_upload.dart calls for
          // damage uploads (`ListingImageMedia.localFile(img)` /
          // `ListingImageMedia.source(img)`) -- never previewLocalFile()/
          // previewSource().
          expect(ListingImageMedia.source(damageMedia), originalHeif);
          expect(ListingImageMedia.localFile(damageMedia)?.path, originalHeif);
          expect(
            ListingImageMedia.localFile(damageMedia)?.path,
            isNot(jpegPreview),
          );
        },
      );
    },
  );
}
