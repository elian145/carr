// Data-durability regression tests for the real-device report's Bug 2/3
// investigation: every local source persisted into a
// `PendingSellSubmissionRecord` must point to a DURABLE app-private copy
// (under `getApplicationDocumentsDirectory()/sell_draft_media/<draftId>/`)
// -- never an `image_picker` cache path, the OS temp dir, a revocable
// `content://` permission, or a temp video path -- so a killed/resumed
// process can't lose media the user already picked, and a resume can
// never mistake "the original cache file is gone" for "delete this from
// the server" (Bug 3).
//
// Confirmed by reading `pending_sell_submission_service.dart`:
// `submit()` calls `SellDraftMediaPersistence.prepareCarDataForStorage()`
// (which durably copies every local media reference) BEFORE creating or
// persisting the `SellSubmissionRecord` -- this is the sole entry point
// for creating a pending record, so every local reference inside a
// persisted record's `carData` is guaranteed durable.
import 'dart:io';

import 'package:car_listing_app/shared/listings/listing_image_media.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('static wiring: submit() durably copies media before persisting '
      'the pending record', () {
    test(
      'PendingSellSubmissionService.submit() calls '
      'SellDraftMediaPersistence.prepareCarDataForStorage() BEFORE the '
      'first SellSubmissionStatePrefs.upsert() call',
      () {
        final content = File(
          p.join(
            'lib',
            'features',
            'sell',
            'pending_sell_submission_service.dart',
          ),
        ).readAsStringSync();

        final submitStart = content.indexOf(
          'Future<SellListingSubmitResult?> submit({',
        );
        expect(submitStart, greaterThanOrEqualTo(0));
        // Bounded to just this method's body (next top-level method).
        final submitEnd = content.indexOf(
          '\n  Future<bool> resumeAll()',
          submitStart,
        );
        expect(submitEnd, greaterThan(submitStart));
        final body = content.substring(submitStart, submitEnd);

        final prepareIdx = body.indexOf(
          'SellDraftMediaPersistence\n        .prepareCarDataForStorage(',
        );
        final prepareIdxAlt = prepareIdx >= 0
            ? prepareIdx
            : body.indexOf('.prepareCarDataForStorage(');
        expect(
          prepareIdxAlt,
          greaterThanOrEqualTo(0),
          reason: 'submit() must durably copy media via '
              'prepareCarDataForStorage()',
        );
        final firstUpsertIdx = body.indexOf('SellSubmissionStatePrefs.upsert(');
        expect(
          firstUpsertIdx,
          greaterThan(prepareIdxAlt),
          reason: 'the durable copy must happen strictly BEFORE the first '
              'persisted record write -- otherwise a kill between "record '
              'persisted" and "media copied" could durably record a '
              'cache/temp path that disappears later',
        );
      },
    );
  });

  group('SellDraftMediaPersistence.prepareCarDataForStorage rewrites '
      'cache/temp local sources into a durable app-private copy', () {
    late Directory tempDir;
    late Directory cacheLikeDir;
    late Directory docsDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sell_durability_');
      // Simulates an image_picker cache dir / OS temp dir -- NOT under app
      // documents, and NOT under sell_draft_media.
      cacheLikeDir = Directory(p.join(tempDir.path, 'image_picker_cache'))
        ..createSync(recursive: true);
      docsDir = Directory(p.join(tempDir.path, 'docs'))
        ..createSync(recursive: true);
      PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort cleanup; a leftover temp dir must never fail a test.
      }
    });

    test(
      'a listing photo picked from a cache-like temp path is copied into '
      'getApplicationDocumentsDirectory()/sell_draft_media/<draftId>/, '
      'with matching bytes, and the returned source is no longer under '
      'the original cache dir',
      () async {
        final cacheFile = File(p.join(cacheLikeDir.path, 'IMG_0001.jpg'))
          ..writeAsBytesSync(List<int>.filled(128, 0x11));

        final result = await SellDraftMediaPersistence.prepareCarDataForStorage(
          {
            'images': [XFile(cacheFile.path)],
          },
          draftId: 'draft_durability_1',
        );

        final images = result['images'] as List;
        expect(images, hasLength(1));
        final durableSource = ListingImageMedia.source(images.first);

        expect(
          durableSource.startsWith(cacheLikeDir.path),
          isFalse,
          reason: 'the durable copy must NOT still point at the '
              'image_picker/cache-like original',
        );
        expect(
          p.normalize(durableSource).contains(
            p.normalize(p.join('sell_draft_media', 'draft_durability_1')),
          ),
          isTrue,
          reason: 'the durable copy must live under this draft\'s '
              'sell_draft_media directory',
        );
        expect(File(durableSource).existsSync(), isTrue);
        expect(
          File(durableSource).readAsBytesSync(),
          List<int>.filled(128, 0x11),
          reason: 'the durable copy must be byte-identical to the original',
        );
      },
    );

    test(
      'a damage photo and a video from cache-like temp paths are BOTH '
      'durably copied (not just listing images)',
      () async {
        final damageCache = File(p.join(cacheLikeDir.path, 'damage_1.jpg'))
          ..writeAsBytesSync(List<int>.filled(64, 0x22));
        final videoCache = File(p.join(cacheLikeDir.path, 'clip_1.mp4'))
          ..writeAsBytesSync(List<int>.filled(256, 0x33));

        final result = await SellDraftMediaPersistence.prepareCarDataForStorage(
          {
            'damage_images': [XFile(damageCache.path)],
            'videos': [XFile(videoCache.path)],
          },
          draftId: 'draft_durability_2',
        );

        final damageSource = ListingImageMedia.source(
          (result['damage_images'] as List).first,
        );
        final videoSource = ListingImageMedia.source(
          (result['videos'] as List).first,
        );

        for (final durableSource in [damageSource, videoSource]) {
          expect(durableSource.startsWith(cacheLikeDir.path), isFalse);
          expect(
            p.normalize(durableSource).contains(
              p.normalize(p.join('sell_draft_media', 'draft_durability_2')),
            ),
            isTrue,
          );
          expect(File(durableSource).existsSync(), isTrue);
        }
      },
    );

    test(
      'a server-side reference (uploads/... path or full http(s) URL) is '
      'left completely unchanged -- durability copying only applies to '
      'genuinely-local device paths, never to already-durable server '
      'media',
      () async {
        final result = await SellDraftMediaPersistence.prepareCarDataForStorage(
          {
            'images': [
              'uploads/car_photos/already_on_server.jpg',
              'https://cdn.example.com/car_photos/remote.jpg',
            ],
          },
          draftId: 'draft_durability_3',
        );

        final sources =
            (result['images'] as List).map(ListingImageMedia.source).toList();
        expect(
          sources,
          containsAll([
            'uploads/car_photos/already_on_server.jpg',
            'https://cdn.example.com/car_photos/remote.jpg',
          ]),
        );
      },
    );

    test(
      'a local source already inside THIS draft\'s sell_draft_media '
      'directory (e.g. a second prepareCarDataForStorage pass after an '
      'earlier resume) is left in place, not re-copied into a new file',
      () async {
        final cacheFile = File(p.join(cacheLikeDir.path, 'IMG_0002.jpg'))
          ..writeAsBytesSync(List<int>.filled(32, 0x44));

        final firstPass = await SellDraftMediaPersistence.prepareCarDataForStorage(
          {
            'images': [XFile(cacheFile.path)],
          },
          draftId: 'draft_durability_4',
        );
        final firstDurableSource = ListingImageMedia.source(
          (firstPass['images'] as List).first,
        );

        // Simulate a later resume re-running prepareCarDataForStorage on
        // carData that already describes the durable path (exactly what
        // happens if submit() were ever called again for the same draft
        // before the record clears).
        final secondPass = await SellDraftMediaPersistence.prepareCarDataForStorage(
          {
            'images': [firstDurableSource],
          },
          draftId: 'draft_durability_4',
        );
        final secondDurableSource = ListingImageMedia.source(
          (secondPass['images'] as List).first,
        );

        expect(
          secondDurableSource,
          firstDurableSource,
          reason: 're-processing an already-durable path must not create '
              'a second copy under a new filename',
        );
      },
    );
  });
}
