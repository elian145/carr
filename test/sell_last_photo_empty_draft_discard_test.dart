// Last-photo deletion + auto-discard empty drafts.
//
// Root cause of "last photo cannot be deleted": `_saveSellDraftSnapshot`
// returned early when carData became empty AFTER an existing snapshot,
// leaving the pre-delete photo snapshot in prefs / My Listings — so the
// delete looked blocked. Fix: purge empty drafts and auto-discard when
// the last media is removed with no other meaningful fields.
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
    tempDir = await Directory.systemTemp.createTemp('sell_last_photo_');
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
    LegacySellDraftPrefs.allowPersist();
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

  List<XFile> fixtureFiles(String label, int count) {
    return List.generate(count, (i) {
      final path = p.join(tempDir.path, '${label}_$i.jpg');
      File(path).writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9, i]);
      return XFile(path);
    });
  }

  Future<void> settleMedia(WidgetTester tester) async {
    for (var round = 0; round < 40; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
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

  Future<void> expectNoVisibleDraftInPrefs() async {
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(LegacySellDraftPrefs.snapshotKey), isNull);
    final archiveRaw = sp.getString(LegacySellDraftPrefs.archiveKey);
    if (archiveRaw != null && archiveRaw.isNotEmpty) {
      final archive = decodeSellDraftArchive(archiveRaw);
      expect(archive.where(isVisibleSellDraft), isEmpty);
    }
  }

  group('hasMeaningfulSellDraftValue / non-media content', () {
    test('meta + empty media are not meaningful', () {
      expect(
        hasMeaningfulSellDraftValue({
          'sell_wizard_v2': true,
          'images': <dynamic>[],
          'original_images': <dynamic>[],
          'primary_image_index': 0,
          'images_processed': false,
          'use_blurred_plates': false,
        }),
        isFalse,
      );
      expect(
        carDataHasMeaningfulNonMediaContent({
          'images': <dynamic>['a.jpg'],
          'sell_wizard_v2': true,
          'primary_image_index': 0,
        }),
        isFalse,
      );
    });

    test('Any placeholders and empty strings are not meaningful', () {
      expect(hasMeaningfulSellDraftValue('Any'), isFalse);
      expect(hasMeaningfulSellDraftValue(''), isFalse);
      expect(
        hasMeaningfulSellDraftValue({
          'condition': 'Any',
          'brand': '',
          'mileage': '  ',
        }),
        isFalse,
      );
    });

    test('all listed Sell fields count when user-entered', () {
      for (final field in <String, dynamic>{
        'brand': 'Toyota',
        'model': 'Camry',
        'trim': 'LE',
        'year': '2020',
        'mileage': '50000',
        'price': '15000',
        'transmission': 'Automatic',
        'fuel_type': 'Petrol',
        'color': 'White',
        'condition': 'Used',
        'location': 'Erbil',
        'description': 'One owner',
        'damage_details': 'Scratch on bumper',
        'city': 'Erbil',
        'phone': '07501234567',
      }.entries) {
        expect(
          carDataHasMeaningfulNonMediaContent({field.key: field.value}),
          isTrue,
          reason: '${field.key} should keep the draft',
        );
      }
    });
  });

  group('last photo deletion behavior', () {
    testWidgets(
      'A: sole photo, no other data -> draft purged from prefs',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        fakePicker.queue.add(fixtureFiles('solo', 1));
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        expect(carDataOf(tester)['images'], isNotEmpty);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);

        await expectNoVisibleDraftInPrefs();
        expect(hasMeaningfulSellDraftValue(carDataOf(tester)), isFalse);
      },
    );

    testWidgets(
      'B: sole photo + brand/model -> draft kept, photos empty',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final page = tester.state(find.byType(SellCarPage)) as dynamic;
        page.carData['brand'] = 'Toyota';
        page.carData['model'] = 'Camry';

        fakePicker.queue.add(fixtureFiles('with_brand', 1));
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);

        final carData = carDataOf(tester);
        expect(carData['brand'], 'Toyota');
        expect(carData['model'], 'Camry');
        expect(carData['images'], isEmpty);
        expect(carData['original_images'], isEmpty);
        expect(hasMeaningfulSellDraftValue(carData), isTrue);

        final sp = await SharedPreferences.getInstance();
        final snap = sp.getString(LegacySellDraftPrefs.snapshotKey);
        expect(snap, isNotNull);
        final decoded = jsonDecode(snap!) as Map<String, dynamic>;
        final stored = Map<String, dynamic>.from(decoded['carData'] as Map);
        expect(stored['brand'], 'Toyota');
        expect(
          stored['images'] == null || (stored['images'] as List).isEmpty,
          isTrue,
        );
      },
    );

    testWidgets(
      'C: sole photo + price only -> draft kept',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final page = tester.state(find.byType(SellCarPage)) as dynamic;
        page.carData['price'] = '15000';

        fakePicker.queue.add(fixtureFiles('price_only', 1));
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);

        final carData = carDataOf(tester);
        expect(carData['price'], '15000');
        expect(carData['images'], isEmpty);
        expect(hasMeaningfulSellDraftValue(carData), isTrue);
      },
    );

    testWidgets(
      'D: sole photo + description only -> draft kept',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final page = tester.state(find.byType(SellCarPage)) as dynamic;
        page.carData['description'] = 'Clean title, one owner';

        fakePicker.queue.add(fixtureFiles('desc_only', 1));
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);

        final carData = carDataOf(tester);
        expect(carData['description'], 'Clean title, one owner');
        expect(carData['images'], isEmpty);
      },
    );

    testWidgets(
      'E: three photos -> delete first keeps two and cover index valid',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        fakePicker.queue.add(fixtureFiles('triple', 3));
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);

        final carData = carDataOf(tester);
        final images = carData['images'] as List? ?? [];
        expect(images, hasLength(2));
        final cover = sellDraftCardPrimaryImageIndex(carData, length: 2);
        expect(cover, inInclusiveRange(0, 1));
        expect(hasMeaningfulSellDraftValue(carData), isTrue);
      },
    );

    testWidgets(
      'F: three photos delete all empty draft -> purged',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        fakePicker.queue.add(fixtureFiles('triple_all', 3));
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);
        expect((carDataOf(tester)['images'] as List?)?.length, 2);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);
        expect((carDataOf(tester)['images'] as List?)?.length, 1);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);

        await expectNoVisibleDraftInPrefs();
        expect(hasMeaningfulSellDraftValue(carDataOf(tester)), isFalse);
      },
    );

    testWidgets(
      'G: all photos deleted with other data -> empty-photo card fields',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final page = tester.state(find.byType(SellCarPage)) as dynamic;
        page.carData['brand'] = 'Honda';
        page.carData['mileage'] = '12000';

        fakePicker.queue.add(fixtureFiles('empty_card', 1));
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);

        final carData = carDataOf(tester);
        expect(carData['brand'], 'Honda');
        expect(sellDraftCardRawImages(carData), isEmpty);
        expect(hasMeaningfulSellDraftValue(carData), isTrue);
      },
    );

    testWidgets(
      'H/I: pending durable copy cannot resurrect discarded draft',
      (tester) async {
        final gate = <Completer<void>>[];
        SellDraftMediaPersistence.debugBeforeCopyOverride = (path) async {
          final c = Completer<void>();
          gate.add(c);
          await c.future;
        };

        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        fakePicker.queue.add(fixtureFiles('race', 1));
        await tapAddPhotos(tester);
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();

        await deletePhotoAt(tester, 0);
        await tester.pump();

        for (final c in List<Completer<void>>.from(gate)) {
          if (!c.isCompleted) c.complete();
        }
        await settleMedia(tester);

        await expectNoVisibleDraftInPrefs();
        expect(hasMeaningfulSellDraftValue(carDataOf(tester)), isFalse);
      },
    );

    testWidgets(
      'J: retained empty-photo draft can add photos again',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final page = tester.state(find.byType(SellCarPage)) as dynamic;
        page.carData['brand'] = 'Toyota';

        fakePicker.queue.add(fixtureFiles('readd_a', 1));
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        await deletePhotoAt(tester, 0);
        await settleMedia(tester);
        expect(carDataOf(tester)['images'], isEmpty);
        expect(carDataOf(tester)['brand'], 'Toyota');

        fakePicker.queue.add(fixtureFiles('readd_b', 1));
        await tapAddPhotos(tester);
        await tester.pump();
        await settleMedia(tester);

        final carData = carDataOf(tester);
        expect(carData['brand'], 'Toyota');
        expect(carData['images'], isNotEmpty);
      },
    );

    test(
      'K: photos step completion still requires at least one image',
      () {
        final body =
            File('lib/features/sell/sell_car_page.dart').readAsStringSync();
        expect(
          body.contains("carData['images'] != null") &&
              body.contains("(carData['images'] as List).isNotEmpty"),
          isTrue,
        );
      },
    );

    test(
      'save path clears empty drafts instead of keeping stale snapshots',
      () {
        final body = File(
          'lib/features/sell/sell_car_page_draft_persist.dart',
        ).readAsStringSync();
        expect(body.contains('_purgeEmptyDraftFromStorage'), isTrue);
        expect(
          body.contains('_discardEmptyDraftAfterLastMediaRemoved'),
          isTrue,
        );
        expect(body.contains('if (hasExistingSnapshot)'), isFalse);
      },
    );

    test(
      'L: discardSellDraftById only removes the matching draft id',
      () async {
        SharedPreferences.setMockInitialValues({
          LegacySellDraftPrefs.snapshotKey: jsonEncode({
            'draftId': 'd1',
            'currentStep': 0,
            'carData': {'brand': 'Toyota'},
          }),
          LegacySellDraftPrefs.archiveKey: jsonEncode([
            {
              'draftId': 'd1',
              'currentStep': 0,
              'carData': {'brand': 'Toyota'},
            },
            {
              'draftId': 'd2',
              'currentStep': 1,
              'carData': {'brand': 'BMW'},
            },
          ]),
        });

        await discardSellDraftById('d1');
        final sp = await SharedPreferences.getInstance();
        expect(sp.getString(LegacySellDraftPrefs.snapshotKey), isNull);
        final archive = decodeSellDraftArchive(
          sp.getString(LegacySellDraftPrefs.archiveKey),
        );
        expect(archive, hasLength(1));
        expect(archive.single['draftId'], 'd2');
      },
    );
  });
}
