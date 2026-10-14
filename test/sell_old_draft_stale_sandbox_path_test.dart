// Reopen-old-draft: iOS container UUID change leaves absolute
// listing_orig paths in the saved snapshot. Recover files that still
// exist under the current Documents directory; mark genuinely missing
// photos as replace-only (no blur/upload, no Sentry ENOENT spam); never
// auto-delete the draft or drop car information.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:car_listing_app/features/sell/sell_draft_helpers.dart';
import 'package:car_listing_app/shared/debug/app_log.dart';
import 'package:car_listing_app/shared/debug/expected_client_noise.dart';
import 'package:car_listing_app/shared/listings/listing_image_media.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsRoot;
  late PathProviderPlatform previousProvider;

  setUp(() async {
    previousProvider = PathProviderPlatform.instance;
    docsRoot = await Directory.systemTemp.createTemp('old_draft_sandbox_');
    PathProviderPlatform.instance = _FakeDocsPathProvider(docsRoot.path);
    SellDraftMediaPersistence.debugBeforeCopyOverride = null;
  });

  tearDown(() async {
    debugLogNonFatalOverride = null;
    SellDraftMediaPersistence.debugBeforeCopyOverride = null;
    await SellDraftMediaPersistence.debugAwaitPendingFolderDeletes();
    SellDraftMediaPersistence.debugResetMediaLifecycleForTest();
    PathProviderPlatform.instance = previousProvider;
    if (await docsRoot.exists()) {
      await docsRoot.delete(recursive: true);
    }
  });

  String staleIosPath(String draftId, String fileName) {
    return p.join(
      '/var/mobile/Containers/Data/Application',
      'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE',
      'Documents',
      'sell_draft_media',
      draftId,
      fileName,
    ).replaceAll(r'\', '/');
  }

  test(
    'reopen old draft: remaps stale iOS sandbox paths onto current '
    'Documents, keeps missing photos as replace slots, skips them from '
    'upload/blur, preserves car info, no Sentry ENOENT',
    () async {
      const draftId = '1791818348089061';
      await SellDraftMediaPersistence.ensureDocumentsPathCached();

      final recoveredName = 'listing_orig_99529487.png';
      final missingName = 'listing_orig_280574444.jpg';
      final currentDir = await SellDraftMediaPersistence.draftDirectory(draftId);
      final recoveredFile = File(p.join(currentDir.path, recoveredName))
        ..writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);

      final staleRecovered = staleIosPath(draftId, recoveredName);
      final staleMissing = staleIosPath(draftId, missingName);
      expect(File(staleRecovered).existsSync(), isFalse);

      final logged = <Object>[];
      debugLogNonFatalOverride = (error, stackTrace, context) {
        logged.add(error);
      };

      final carData = <String, dynamic>{
        'brand': 'toyota',
        'model': 'camry',
        'year': 2020,
        'city': 'Baghdad',
        'original_images': [
          {'source': staleRecovered},
          {'source': staleMissing},
        ],
        'images': [
          {'source': staleRecovered},
          {'source': staleMissing},
        ],
      };

      final resolved = SellDraftMediaPersistence.resolveDynamicMediaList(
        carData['original_images'] as List,
        includeMissingLocalPaths: true,
      );

      expect(resolved, hasLength(2));
      expect(ListingImageMedia.source(resolved[0]), recoveredFile.path);
      expect(ListingImageMedia.isLocalMissing(resolved[0]), isFalse);
      expect(ListingImageMedia.localFile(resolved[0]), isNotNull);

      expect(ListingImageMedia.isLocalMissing(resolved[1]), isTrue);
      expect(ListingImageMedia.localFile(resolved[1]), isNull);
      expect(
        ListingImageMedia.source(resolved[1]).replaceAll(r'\', '/'),
        contains(missingName),
      );

      final forUpload = SellDraftMediaPersistence.xFilesForUpload(resolved);
      expect(forUpload.map((f) => f.path).toList(), [recoveredFile.path]);

      final persisted = await SellDraftMediaPersistence.persistDynamicMediaList(
        resolved,
        draftId: draftId,
        namePrefix: 'listing_orig',
      );
      expect(persisted, hasLength(2));
      expect(ListingImageMedia.source(persisted[0]), recoveredFile.path);
      expect(ListingImageMedia.isLocalMissing(persisted[1]), isTrue);

      expect(hasMeaningfulSellDraftValue(carData), isTrue);
      expect(carDataHasMeaningfulNonMediaContent(carData), isTrue);

      expect(
        logged.where(
          (e) =>
              e.toString().contains('PathNotFound') ||
              e.toString().contains('No such file') ||
              e.toString().contains('Cannot retrieve length'),
        ),
        isEmpty,
      );

      expect(
        isExpectedMissingDraftMediaError(
          PathNotFoundException(
            staleMissing,
            const OSError('No such file or directory', 2),
            'Cannot retrieve length of file',
          ),
        ),
        isTrue,
      );
      expect(
        isExpectedClientNoise(
          FileSystemException(
            'Cannot retrieve length of file',
            '/var/mobile/Containers/Data/Application/ABC/Documents/'
                'sell_draft_media/$draftId/$missingName',
            const OSError('No such file or directory', 2),
          ),
        ),
        isTrue,
      );
      expect(
        isExpectedClientNoise(
          PathNotFoundException(
            '/tmp/unrelated-config.json',
            const OSError('No such file or directory', 2),
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'reopen old draft does not auto-discard when every photo is missing',
    () async {
      const draftId = 'old_draft_all_missing';
      await SellDraftMediaPersistence.ensureDocumentsPathCached();

      final stale = staleIosPath(draftId, 'listing_orig_gone.png');
      final carData = <String, dynamic>{
        'brand': 'kia',
        'model': 'cerato',
        'original_images': [
          {'source': stale},
        ],
      };

      final resolved = SellDraftMediaPersistence.resolveDynamicMediaList(
        carData['original_images'] as List,
      );
      expect(resolved, hasLength(1));
      expect(ListingImageMedia.isLocalMissing(resolved.single), isTrue);
      expect(SellDraftMediaPersistence.xFilesForUpload(resolved), isEmpty);
      expect(hasMeaningfulSellDraftValue(carData), isTrue);
      expect(carDataHasMeaningfulNonMediaContent(carData), isTrue);
    },
  );
}
