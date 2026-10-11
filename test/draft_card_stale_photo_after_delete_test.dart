// Stale draft-card thumbnail after Sell photo delete.
//
// Root cause: `_removePhotoAt` synced `original_images` synchronously but
// left `carData['images']` on the pre-delete list until async
// `_syncMediaDraftToParent` finished — and that sync often aborted on
// `!mounted` when leaving Sell, so dispose persisted the deleted photo.
// My Listings then preferred stale `images` over the cleared originals.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/features/sell/sell_draft_helpers.dart';
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/listings/listing_image_media.dart';
import 'package:car_listing_app/shared/prefs/legacy_sell_draft_prefs.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;

  @override
  Future<String?> getTemporaryPath() async => _path;

  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

class FakeMultiImagePickerPlatform extends ImagePickerPlatform {
  final List<List<XFile>> queue = <List<XFile>>[];

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    if (queue.isEmpty) return <XFile>[];
    return queue.removeAt(0);
  }
}

void main() {
  late Directory tempDir;
  late FakeMultiImagePickerPlatform fakePicker;
  late ImagePickerPlatform originalPicker;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('draft_card_stale_');
    originalPicker = ImagePickerPlatform.instance;
    fakePicker = FakeMultiImagePickerPlatform();
    ImagePickerPlatform.instance = fakePicker;
    PathProviderPlatform.instance = _FakeDocsPathProvider(tempDir.path);

    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
    await ApiService.clearTokens();
    await AuthService().adoptTestSession(
      user: {
        'id': 1,
        'username': 'seller',
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );

    // DeepLinkService.init() rejects without a platform mock; heavier
    // runAsync settle loops surface that as a test failure.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/messages'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (call) async => null,
    );
  });

  tearDown(() async {
    SellDraftMediaPersistence.debugBeforeCopyOverride = null;
    ImagePickerPlatform.instance = originalPicker;
    ApiService.testHttpClient = null;
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Future<void> settleUi(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpToDraftTab(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await settleUi(tester);

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/my_listings');
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.drag(
      find.byKey(const ValueKey<String>('my-listings-filter-list')),
      const Offset(-300, 0),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('my-listings-filter-draft')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  List<XFile> fixtureFiles(String label, int count) {
    return List.generate(count, (i) {
      final path = p.join(tempDir.path, '${label}_$i.jpg');
      File(path).writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9, i]);
      return XFile(path);
    });
  }

  Future<void> tapAddPhotos(WidgetTester tester) async {
    final finder = find.widgetWithText(ElevatedButton, 'Add Photos');
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> deletePhotoAt(WidgetTester tester, int index) async {
    final closeButtons = find.byIcon(Icons.close);
    expect(closeButtons.evaluate().length, greaterThan(index));
    await tester.tap(closeButtons.at(index));
    await tester.pump();
  }

  Map<String, dynamic> carDataOf(WidgetTester tester) {
    return Map<String, dynamic>.from(
      (tester.state(find.byType(SellCarPage)) as dynamic).carData as Map,
    );
  }

  Future<void> settleMedia(WidgetTester tester) async {
    for (var round = 0; round < 60; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('sellDraftCardRawImages / cover index', () {
    test('empty original_images wins over stale images (delete-all)', () {
      final raw = sellDraftCardRawImages({
        'original_images': <dynamic>[],
        'images': <dynamic>['/stale/deleted.jpg'],
        'image_paths': <dynamic>['/stale/deleted.jpg'],
      });
      expect(raw, isEmpty);
    });

    test('original_images preferred when present and non-empty', () {
      final raw = sellDraftCardRawImages({
        'original_images': <dynamic>['b.jpg', 'c.jpg'],
        'images': <dynamic>['a.jpg', 'b.jpg', 'c.jpg'],
      });
      expect(raw, <dynamic>['b.jpg', 'c.jpg']);
    });

    test('falls back to images when original_images key absent', () {
      final raw = sellDraftCardRawImages({
        'images': <dynamic>['only.jpg'],
      });
      expect(raw, <dynamic>['only.jpg']);
    });

    test('primary index clamps and selects cover', () {
      expect(
        sellDraftCardPrimaryImageIndex(
          {'primary_image_index': 2},
          length: 3,
        ),
        2,
      );
      expect(
        sellDraftCardPrimaryImageIndex(
          {'primary_image_index': 9},
          length: 2,
        ),
        0,
      );
    });
  });

  group('My Listings draft card thumbnail source', () {
    testWidgets(
      'E: stale images + empty original_images -> empty-draft design',
      (tester) async {
        final stalePath = p.join(tempDir.path, 'stale_deleted.jpg');
        File(stalePath).writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9]);

        SharedPreferences.setMockInitialValues({
          'push_enabled': false,
          'app_locale': 'en',
          LegacySellDraftPrefs.archiveKey: jsonEncode([
            {
              'draftId': 'stale_thumb_after_delete',
              'currentStep': 0,
              'carData': {
                'brand': 'toyota',
                'model': 'camry',
                // Authoritative post-delete list (empty).
                'original_images': <dynamic>[],
                // Pre-delete leftover that must NOT win.
                'images': <dynamic>[stalePath],
              },
              'isPlaceholder': false,
              'updatedAt': 1700000000000,
            },
          ]),
        });

        await pumpToDraftTab(tester);

        expect(find.text('Add photos to continue'), findsOneWidget);
        expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
        expect(find.byIcon(Icons.broken_image), findsNothing);
      },
    );

    testWidgets(
      'C: after cover removed, card uses next remaining original',
      (tester) async {
        final a = p.join(tempDir.path, 'cover_a.jpg');
        final b = p.join(tempDir.path, 'next_b.jpg');
        File(a).writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9, 1]);
        File(b).writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9, 2]);

        SharedPreferences.setMockInitialValues({
          'push_enabled': false,
          'app_locale': 'en',
          LegacySellDraftPrefs.archiveKey: jsonEncode([
            {
              'draftId': 'cover_next_after_delete',
              'currentStep': 0,
              'carData': {
                'brand': 'honda',
                'model': 'civic',
                'original_images': <dynamic>[b],
                'images': <dynamic>[a, b], // stale still includes deleted cover
                'primary_image_index': 0,
              },
              'isPlaceholder': false,
              'updatedAt': 1700000000000,
            },
          ]),
        });

        await pumpToDraftTab(tester);

        expect(find.text('Add photos to continue'), findsNothing);
        expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);
        expect(
          find.byKey(const ValueKey('draft-card-cover_next_after_delete')),
          findsOneWidget,
        );
      },
    );
  });

  group('Sell delete synchronizes active images list', () {
    testWidgets(
      'A/B: delete sole photo clears carData images immediately',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final files = fixtureFiles('solo', 1);
        fakePicker.queue.add(files);
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        var carData = carDataOf(tester);
        expect(carData['images'], isNotEmpty);
        expect(carData['original_images'], isNotEmpty);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);
        // Photo-only draft: last-photo delete auto-discards the whole draft
        // (clears in-memory carData + prefs). Empty lists are not left behind.
        carData = carDataOf(tester);
        expect(hasMeaningfulSellDraftValue(carData), isFalse);
        final sp = await SharedPreferences.getInstance();
        expect(sp.getString(LegacySellDraftPrefs.snapshotKey), isNull);
      },
    );

    testWidgets(
      'C/D: delete first of three keeps remaining in images + originals',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final files = fixtureFiles('triple', 3);
        fakePicker.queue.add(files);
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        await deletePhotoAt(tester, 0);
        final carData = carDataOf(tester);
        final images = carData['images'] as List? ?? [];
        final originals = carData['original_images'] as List? ?? [];
        expect(images, hasLength(2));
        expect(originals, hasLength(2));
        expect(
          images.map(ListingImageMedia.source).any(
                (s) => s.contains(files[0].path),
              ),
          isFalse,
        );
        expect(
          originals.map(ListingImageMedia.source).any(
                (s) => s.contains(files[0].path),
              ),
          isFalse,
        );
      },
    );

    testWidgets(
      'I: delayed durable copy after delete cannot restore images',
      (tester) async {
        final gate = <Completer<void>>[];
        SellDraftMediaPersistence.debugBeforeCopyOverride = (_) {
          final c = Completer<void>();
          gate.add(c);
          return c.future;
        };

        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final files = fixtureFiles('race', 1);
        fakePicker.queue.add(files);
        await tapAddPhotos(tester);
        await tester.pump();
        // Let the pick enqueue a durable sync, then delete before it copies.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();

        await deletePhotoAt(tester, 0);
        var carData = carDataOf(tester);
        // Immediate sync clears media; empty photo-only draft may already
        // be mid-discard.
        expect(
          carData['images'] == null || (carData['images'] as List).isEmpty,
          isTrue,
        );
        expect(
          carData['original_images'] == null ||
              (carData['original_images'] as List).isEmpty,
          isTrue,
        );

        // Release any blocked copies (pick + delete syncs).
        for (final c in List<Completer<void>>.from(gate)) {
          if (!c.isCompleted) c.complete();
        }
        await settleMedia(tester);

        carData = carDataOf(tester);
        expect(hasMeaningfulSellDraftValue(carData), isFalse);
        final sp = await SharedPreferences.getInstance();
        expect(sp.getString(LegacySellDraftPrefs.snapshotKey), isNull);
      },
    );
  });

  group('source guards', () {
    test('removePhotoAt publishes images synchronously before sync', () {
      final body = File('lib/features/sell/sell_step4_logic.dart').readAsStringSync();
      final removeIdx = body.indexOf('Future<void> _removePhotoAt(int index)');
      expect(removeIdx, greaterThanOrEqualTo(0));
      final nextFn = body.indexOf('void _removeDamagePhotoAt', removeIdx + 1);
      final slice = body.substring(removeIdx, nextFn);
      expect(
        slice.contains("carData['images'] = List<dynamic>.from(_selectedImages)"),
        isTrue,
        reason: 'delete must sync active images list before async persist',
      );
      expect(
        slice.contains('_saveSellDraftSnapshot()'),
        isTrue,
        reason: 'delete must persist draft snapshot immediately',
      );
    });

    test('syncMediaDraftToParent writes parent even when Step4 unmounted', () {
      final body = File('lib/features/sell/sell_step4_logic.dart').readAsStringSync();
      final syncIdx = body.indexOf('Future<void> _syncMediaDraftToParent()');
      expect(syncIdx, greaterThanOrEqualTo(0));
      final nextFn = body.indexOf('String _imagePathKey', syncIdx + 1);
      final slice = body.substring(syncIdx, nextFn);
      // Must not early-return on !mounted before _writeMediaListsToParent.
      final writeIdx = slice.indexOf('_writeMediaListsToParent');
      expect(writeIdx, greaterThanOrEqualTo(0));
      final beforeWrite = slice.substring(0, writeIdx);
      expect(
        beforeWrite.contains('if (!mounted) return;'),
        isFalse,
        reason: 'unmount must not skip writing cleared images to parent carData',
      );
    });

    test('empty live media list wins over persisted (no resurrection)', () {
      final body = File('lib/features/sell/sell_step4_logic.dart').readAsStringSync();
      final idx = body.indexOf('List<dynamic> _persistedOrLiveMedia(');
      expect(idx, greaterThanOrEqualTo(0));
      final slice = body.substring(idx, idx + 400);
      expect(slice.contains('if (live.isEmpty) return live;'), isTrue);
    });
  });
}
