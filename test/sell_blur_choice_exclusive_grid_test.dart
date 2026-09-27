// Blur-choice UI restore (real-device feedback): an earlier fix (see the
// now-removed `sell_blur_choice_shows_both_originals_test.dart`, which this
// file supersedes) made the blur-choice step ALWAYS show BOTH "Original
// photos" and "Blurred photos" simultaneously, regardless of which radio
// tile ("No, keep original photos" / "Yes, use blurred photos") was
// selected. The user does not want that:
//
//   - selecting UNBLURRED -> show ONLY the unblurred/original grid
//   - selecting BLURRED   -> show ONLY the blurred grid
//   - never show both at the same time
//
// This is a presentation-only change (see `_previewSection` in
// `sell_step_blur_choice_build.dart`). `applySellPlateBlurChoice`
// (`sell_plate_blur_choice.dart`, covered separately by
// `sell_plate_blur_choice_test.dart`, untouched by this fix) still commits
// BOTH `original_images` and `blurred_images` into `carData` every time --
// neither is ever cleared -- only which one is rendered changes. The
// original/unblurred grid keeps rendering through `_blurPreviewGrid`, which
// already resolves `ListingImageMedia.previewLocalFile()` (not the raw
// `localFile()`), so HEIF originals keep working exactly as before.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/listings/listing_image_media.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
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
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Map<String, dynamic> blurChoiceReadyCarData() => {
        ...sellCarDataThroughStep4(),
        'sell_wizard_v2': true,
        'original_images': <dynamic>['uploads/original_1.jpg'],
        'blurred_images': <dynamic>['uploads/blurred_1.jpg'],
        'images': <dynamic>['uploads/original_1.jpg'],
        'images_processed': true,
      };

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'no choice made yet: neither "Original photos" nor "Blurred photos" is '
    'shown (matches the original pre-existing UX before either tile is '
    'tapped)',
    (tester) async {
      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await openSellDraftStep(
        tester,
        step: 4, // SellWizardSteps.plateBlur
        carData: blurChoiceReadyCarData(),
      );

      expect(find.text('Original photos'), findsNothing);
      expect(find.text('Blurred photos'), findsNothing);
    },
  );

  testWidgets(
    'selecting "No, keep original photos" shows ONLY "Original photos" -- '
    '"Blurred photos" must NOT also be shown',
    (tester) async {
      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await openSellDraftStep(
        tester,
        step: 4,
        carData: blurChoiceReadyCarData(),
      );

      await tester.tap(find.text('No, keep original photos'));
      await settle(tester);

      expect(find.text('Original photos'), findsOneWidget);
      expect(
        find.text('Blurred photos'),
        findsNothing,
        reason: 'selecting Unblurred must hide the blurred grid entirely, '
            'not show it alongside the original',
      );
    },
  );

  testWidgets(
    'selecting "Yes, use blurred photos" shows ONLY "Blurred photos" -- '
    '"Original photos" must NOT also be shown',
    (tester) async {
      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await openSellDraftStep(
        tester,
        step: 4,
        carData: blurChoiceReadyCarData(),
      );

      await tester.tap(find.text('Yes, use blurred photos'));
      await settle(tester);

      expect(find.text('Blurred photos'), findsOneWidget);
      expect(
        find.text('Original photos'),
        findsNothing,
        reason: 'selecting Blurred must hide the original grid entirely, '
            'not show it alongside the blurred result',
      );
    },
  );

  testWidgets(
    'switching the selection swaps which grid is visible: '
    'unblurred -> blurred -> unblurred',
    (tester) async {
      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await openSellDraftStep(
        tester,
        step: 4,
        carData: blurChoiceReadyCarData(),
      );

      await tester.tap(find.text('No, keep original photos'));
      await settle(tester);
      expect(find.text('Original photos'), findsOneWidget);
      expect(find.text('Blurred photos'), findsNothing);

      await tester.tap(find.text('Yes, use blurred photos'));
      await settle(tester);
      expect(find.text('Blurred photos'), findsOneWidget);
      expect(find.text('Original photos'), findsNothing);

      await tester.tap(find.text('No, keep original photos'));
      await settle(tester);
      expect(find.text('Original photos'), findsOneWidget);
      expect(find.text('Blurred photos'), findsNothing);
    },
  );

  testWidgets(
    'internal original + blurred mappings both remain intact in the '
    'persisted draft regardless of which grid is currently visible',
    (tester) async {
      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await openSellDraftStep(
        tester,
        step: 4,
        carData: blurChoiceReadyCarData(),
      );

      Future<Map<String, dynamic>> readPersistedCarData() async {
        final sp = await SharedPreferences.getInstance();
        final raw = sp.getString('legacy_sell_draft_snapshot_v1');
        expect(raw, isNotNull, reason: 'a draft snapshot must have been saved');
        final decoded = json.decode(raw!) as Map;
        return Map<String, dynamic>.from(decoded['carData'] as Map);
      }

      await tester.tap(find.text('Yes, use blurred photos'));
      await settle(tester);
      final afterBlurred = await readPersistedCarData();
      expect(
        afterBlurred['original_images'],
        isNotEmpty,
        reason: 'the original reference must survive selecting Blurred, '
            'even though only the blurred grid is currently displayed',
      );
      expect(afterBlurred['blurred_images'], isNotEmpty);

      await tester.tap(find.text('No, keep original photos'));
      await settle(tester);
      final afterOriginal = await readPersistedCarData();
      expect(afterOriginal['original_images'], isNotEmpty);
      expect(
        afterOriginal['blurred_images'],
        isNotEmpty,
        reason: 'the blurred reference must survive switching back to '
            'Unblurred -- selecting Unblurred only changes which grid is '
            'DISPLAYED, never the underlying original_images/blurred_images '
            'data',
      );
    },
  );

  testWidgets(
    'a HEIF original (a Map entry with preview_source) still renders in the '
    'exclusive "Original photos" grid, with no crash, when Unblurred is '
    'selected',
    (tester) async {
      final heifCarData = {
        ...sellCarDataThroughStep4(),
        'sell_wizard_v2': true,
        'original_images': <dynamic>[
          {
            'source': '/tmp/blur_choice_orig.heif',
            'preview_source': '/tmp/blur_choice_preview.jpg',
          },
        ],
        'blurred_images': <dynamic>['uploads/blurred_1.jpg'],
        'images': <dynamic>['uploads/original_1.jpg'],
        'images_processed': true,
      };

      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await openSellDraftStep(tester, step: 4, carData: heifCarData);

      await tester.tap(find.text('No, keep original photos'));
      await settle(tester);

      expect(find.text('Original photos'), findsOneWidget);
      expect(find.text('Blurred photos'), findsNothing);
      expect(
        tester.takeException(),
        isNull,
        reason: 'rendering a HEIF-shaped original (source=.heif, '
            'preview_source=.jpg) must not throw',
      );
    },
  );

  test(
    'unit: ListingImageMedia.previewLocalFile resolves a blur-choice '
    "original entry's HEIF source to its JPEG preview_source -- exactly "
    'what _originalImages()/_blurPreviewGrid feed into the "Original '
    'photos" grid',
    () {
      final entry = {
        'source': '/tmp/blur_choice_orig.heif',
        'preview_source': '/tmp/blur_choice_preview.jpg',
      };
      final resolved = ListingImageMedia.previewLocalFile(entry);
      expect(resolved?.path, '/tmp/blur_choice_preview.jpg');
      expect(resolved?.path, isNot(ListingImageMedia.source(entry)));
    },
  );
}
