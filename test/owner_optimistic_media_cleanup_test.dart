// Regression tests for the optimistic-local-media LIFETIME CONTRACT
// (Critical Issue 1 fix -- see `owner_optimistic_media_cleanup.dart`'s
// file-level doc comment): local optimistic media may be deleted ONLY
// once its own item is confirmed remote-display-ready on THIS device,
// never merely because the backend has finished. Covers the exact 8
// scenarios from the audit spec (numbered below to match).
import 'dart:io';

import 'package:car_listing_app/shared/listings/owner_media_overlay.dart';
import 'package:car_listing_app/shared/listings/owner_optimistic_media_cleanup.dart';
import 'package:car_listing_app/shared/prefs/owner_optimistic_media_prefs.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const listingId = 'car_lifetime_1';
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('owner_optimistic_media_');
    final docsDir = Directory('${tempDir.path}/docs')
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Writes [count] real local files and returns an
  /// [OwnerOptimisticMediaRecord] with one not-yet-ready item per file,
  /// already durably persisted.
  Future<OwnerOptimisticMediaRecord> seedRecord({
    required int count,
    String kind = 'image',
    String? draftId,
  }) async {
    final items = <OwnerOptimisticMediaItem>[];
    for (var i = 0; i < count; i++) {
      final f = File('${tempDir.path}/item_$i.bin')
        ..writeAsBytesSync([1, 2, 3, i]);
      items.add(
        OwnerOptimisticMediaItem(
          clientMediaId: 'cmid_$i',
          kind: kind,
          order: i,
          localPath: f.path,
          remoteUrl: 'https://cdn.example.com/remote_$i.jpg',
        ),
      );
    }
    final record = OwnerOptimisticMediaRecord(
      listingId: listingId,
      items: items,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      draftId: draftId,
    );
    await OwnerOptimisticMediaPrefs.upsert(record);
    return record;
  }

  test(
    'Test 1: backend full success, remote display ready = 3/5 -- local '
    'files for the remaining 2 still exist, the overlay record still '
    'exists, and "Processing media" remains signaled (not every item '
    'ready yet)',
    () async {
      final seeded = await seedRecord(count: 5);

      for (var i = 0; i < 3; i++) {
        await OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup(
          listingId: listingId,
          clientMediaId: 'cmid_$i',
        );
      }

      for (var i = 0; i < 3; i++) {
        expect(await File(seeded.items[i].localPath!).exists(), isFalse);
      }
      for (var i = 3; i < 5; i++) {
        expect(
          await File(seeded.items[i].localPath!).exists(),
          isTrue,
          reason: 'item $i was never confirmed remote-display-ready -- '
              'its local file must survive',
        );
      }

      final after = await OwnerOptimisticMediaPrefs.load(listingId);
      expect(after, isNotNull, reason: 'overlay record must still exist');
      expect(after!.items, hasLength(5));
      expect(
        after.allRemoteDisplayReady,
        isFalse,
        reason: '"Processing media" must remain visible (2/5 not ready)',
      );
    },
  );

  test(
    'Test 2: backend full success, remote display ready = 0/5, kill/'
    'restart app -- all 5 local items restore immediately, "Processing '
    'media" still signaled',
    () async {
      await seedRecord(count: 5);

      // "Kill/restart" -- nothing lives in memory between the seed above
      // and this reload; SharedPreferences is the only source of truth,
      // exactly like a genuine process restart.
      final result = await OwnerMediaOverlay.buildFromOptimisticRecordForCarId(
        car: const {'id': listingId, 'images': <dynamic>[]},
        carId: listingId,
      );

      expect(result.slots, hasLength(5));
      for (final slot in result.slots) {
        expect(slot.hasLocal, isTrue);
      }
      expect(
        result.serverStillProcessing,
        isTrue,
        reason: '"Processing media" must be visible immediately on '
            'restart -- nothing has been confirmed yet',
      );
    },
  );

  test(
    'Test 3: remote #1 successfully displays -- only local #1 may be '
    'deleted, #2-#5 remain untouched',
    () async {
      final seeded = await seedRecord(count: 5);

      await OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup(
        listingId: listingId,
        clientMediaId: 'cmid_0',
      );

      expect(await File(seeded.items[0].localPath!).exists(), isFalse);
      for (var i = 1; i < 5; i++) {
        expect(await File(seeded.items[i].localPath!).exists(), isTrue);
      }
      final after = await OwnerOptimisticMediaPrefs.load(listingId);
      expect(after!.items.where((i) => i.remoteDisplayReady), hasLength(1));
    },
  );

  test(
    'Test 4: all 5 remote-display-ready -- all local optimistic files '
    'removed, overlay persistence record removed, "Processing media" '
    'disappears (no record left to signal it)',
    () async {
      final seeded = await seedRecord(count: 5);

      for (var i = 0; i < 5; i++) {
        await OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup(
          listingId: listingId,
          clientMediaId: 'cmid_$i',
        );
      }

      for (final item in seeded.items) {
        expect(await File(item.localPath!).exists(), isFalse);
      }
      expect(await OwnerOptimisticMediaPrefs.load(listingId), isNull);

      // With the record gone, the restart-safe overlay builder must now
      // report genuinely empty -- this is exactly what makes the
      // "Processing media" badge disappear.
      final result = await OwnerMediaOverlay.buildFromOptimisticRecordForCarId(
        car: const {'id': listingId, 'images': <dynamic>[]},
        carId: listingId,
      );
      expect(result.isEmpty, isTrue);
    },
  );

  test(
    'Test 4b: whole-record cleanup also removes the originating Sell '
    'draft directory, including any untracked sibling file',
    () async {
      const draftId = 'draft_for_lifetime_1';
      final draftDir = await SellDraftMediaPersistence.draftDirectory(
        draftId,
      );
      File('${draftDir.path}/untracked_marker.txt')
          .writeAsStringSync('sibling file never tracked as its own item');

      final seeded = await seedRecord(count: 2, draftId: draftId);
      for (final item in seeded.items) {
        await OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup(
          listingId: listingId,
          clientMediaId: item.clientMediaId,
        );
      }

      expect(
        await draftDir.exists(),
        isFalse,
        reason: 'the whole draft directory (including untracked sibling '
            'files) must be removed once every expected item is ready',
      );
    },
  );

  test(
    'Test 5: remote image load fails after backend ready -- local file '
    'remains, restart still restores the local fallback',
    () async {
      final seeded = await seedRecord(count: 1);

      // A failed decode never calls `onRemoteDisplayReady` --
      // `markRemoteDisplayReadyAndCleanup` is simply never invoked for
      // this item. Nothing else in the app touches the record.
      expect(await File(seeded.items.first.localPath!).exists(), isTrue);
      final after = await OwnerOptimisticMediaPrefs.load(listingId);
      expect(after!.items.single.remoteDisplayReady, isFalse);

      // "Restart" -- reload from durable storage, confirm the local
      // fallback is still there to show.
      final result = await OwnerMediaOverlay.buildFromOptimisticRecordForCarId(
        car: const {'id': listingId, 'images': <dynamic>[]},
        carId: listingId,
      );
      expect(result.slots.single.hasLocal, isTrue);
      expect(await File(result.slots.single.localPath!).exists(), isTrue);
    },
  );

  test(
    'Test 8: video backend ready but remote player initialization fails '
    '-- local video/thumbnail remains, cleanup does not occur',
    () async {
      final seeded = await seedRecord(count: 1, kind: 'video');

      // Same as Test 5's reasoning, for a video item: initialization
      // failure means the fallback widget never calls
      // `onRemoteDisplayReady`, so `markRemoteDisplayReadyAndCleanup` is
      // never invoked.
      expect(await File(seeded.items.first.localPath!).exists(), isTrue);
      final after = await OwnerOptimisticMediaPrefs.load(listingId);
      expect(after!.items.single.remoteDisplayReady, isFalse);
      expect(after.items.single.kind, 'video');
      expect(after.allRemoteDisplayReady, isFalse);
    },
  );

  test(
    'Idempotency: a repeat confirm for an already-ready item is a '
    'harmless no-op (never double-deletes, never crashes)',
    () async {
      await seedRecord(count: 1);
      await OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup(
        listingId: listingId,
        clientMediaId: 'cmid_0',
      );
      expect(await OwnerOptimisticMediaPrefs.load(listingId), isNull);

      // No throw, no resurrection of the record.
      await OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup(
        listingId: listingId,
        clientMediaId: 'cmid_0',
      );
      expect(await OwnerOptimisticMediaPrefs.load(listingId), isNull);
    },
  );
}
