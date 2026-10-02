// Architecture fix (real-device evidence: "even the Blurred option can
// show the unblurred image"): covers Section 3's truthful per-photo
// "not blurred" marker, which `sell_blur_choice_exclusive_grid_test.dart`
// does not exercise.
//
// When the background blur job completes but ONE specific photo's blur
// failed/found no plate (`mergeBlurResultsIntoOriginals` falls back to
// that photo's original bytes and tags it `blur_not_applied: true` -- see
// `sell_plate_blur_merge.dart`), the "Blurred photos" grid must render a
// visible "not blurred" indicator on THAT tile instead of silently
// presenting the fallback as a genuine, indistinguishable distinct
// blurred result.
//
// (The "blurred result still genuinely pending" UI branch --
// `_previewSection`'s `else` case in `sell_step_blur_choice_build.dart`,
// showing "Blurred photos are not ready yet." plus a retry button -- is
// pre-existing, unchanged code, not modified by this fix; it is not
// covered by a dedicated test here because deterministically holding the
// real background job mid-flight in this widget-test harness requires a
// dangling `Future.delayed` timer that `flutter_test` correctly flags as
// a leak, so it was verified by code review instead: see `_previewSection`
// in `sell_step_blur_choice_build.dart`.)
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

/// Every `imageUrl` currently rendered via `CachedNetworkImage` anywhere in
/// the tree -- this is the actual widget `_listingNetworkImage`
/// (`listing_network_image.dart`) resolves to for any non-local `source`
/// (every `blurred_images`/`original_images` entry in these tests is a
/// bare server rel path, never a local file, so this is guaranteed to be
/// the real image actually painted on screen for each grid tile -- not an
/// inference from `carData`).
List<String> _renderedNetworkImageUrls(WidgetTester tester) {
  return tester
      .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
      .map((w) => w.imageUrl)
      .toList();
}

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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'per-photo "not blurred" marker: a blurred_images entry tagged '
    'blur_not_applied=true (per-photo blur failure/no-plate-detected, see '
    'mergeBlurResultsIntoOriginals) renders a visible truthful indicator '
    'on that tile instead of silently passing off the original bytes as a '
    'genuine distinct blurred result',
    (tester) async {
      final carData = {
        ...sellCarDataThroughStep4(),
        'sell_wizard_v2': true,
        'original_images': <dynamic>['uploads/original_1.jpg'],
        'blurred_images': <dynamic>[
          {
            'source': 'uploads/original_1.jpg',
            'blur_not_applied': true,
          },
        ],
        'images': <dynamic>['uploads/original_1.jpg'],
        'images_processed': true,
      };

      await tester.pumpWidget(const legacy.MyApp());
      await settle(tester);

      await openSellDraftStep(tester, step: 4, carData: carData);

      await tester.tap(find.text('Yes, use blurred photos'));
      await settle(tester);

      expect(find.text('Blurred photos'), findsOneWidget);
      expect(
        find.text('Not blurred — no plate detected'),
        findsOneWidget,
        reason: 'THE KEY ASSERTION: a per-photo blur failure/no-plate '
            'fallback must be visibly, truthfully labeled on its tile -- '
            'never silently presented as an indistinguishable, genuine '
            'blurred result',
      );
    },
  );

  testWidgets(
    'a genuinely blurred entry (no blur_not_applied marker) shows NO '
    '"not blurred" indicator -- the truthful label only ever appears for '
    'the specific fallback case, never for a real blurred result',
    (tester) async {
      final carData = {
        ...sellCarDataThroughStep4(),
        'sell_wizard_v2': true,
        'original_images': <dynamic>['uploads/original_1.jpg'],
        'blurred_images': <dynamic>['uploads/blurred_1.jpg'],
        'images': <dynamic>['uploads/original_1.jpg'],
        'images_processed': true,
      };

      await tester.pumpWidget(const legacy.MyApp());
      await settle(tester);

      await openSellDraftStep(tester, step: 4, carData: carData);

      await tester.tap(find.text('Yes, use blurred photos'));
      await settle(tester);

      expect(find.text('Blurred photos'), findsOneWidget);
      expect(find.text('Not blurred — no plate detected'), findsNothing);
    },
  );

  // Section 6 (real-device evidence: "every image in the Blurred section
  // LOOKS unblurred", even though production proved at least one preview
  // job genuinely produced `plate_blur_applied=True` for that source).
  // Every prior test in this file only ever asserted on `carData` --
  // proving the CHOICE state and merge logic are correct never actually
  // proves the CHOICE SCREEN paints the right bytes. This test uses
  // deliberately, obviously distinct original vs. blurred rel paths and
  // reads the real `CachedNetworkImage.imageUrl` actually mounted in the
  // widget tree -- the same widget `_listingNetworkImage` resolves to in
  // production -- to rule out (or catch) a genuine source-binding bug
  // between `mergeBlurResultsIntoOriginals`'s output and what
  // `_blurPreviewGrid` actually paints.
  testWidgets(
    'UNBLURRED tile renders the ORIGINAL source URL; BLURRED tile renders '
    'the distinct PROCESSED/blurred source URL -- not each other\'s',
    (tester) async {
      const originalUrl = 'uploads/car_photos/DISTINCT_ORIGINAL_unblurred.jpg';
      const blurredUrl = 'uploads/car_photos/DISTINCT_PROCESSED_blurred.jpg';
      final carData = {
        ...sellCarDataThroughStep4(),
        'sell_wizard_v2': true,
        'original_images': <dynamic>[originalUrl],
        'blurred_images': <dynamic>[blurredUrl],
        'images': <dynamic>[originalUrl],
        'images_processed': true,
      };

      await tester.pumpWidget(const legacy.MyApp());
      await settle(tester);

      await openSellDraftStep(tester, step: 4, carData: carData);

      // "No, keep original photos" -- must render ONLY the original URL.
      await tester.tap(find.text('No, keep original photos'));
      await settle(tester);

      var rendered = _renderedNetworkImageUrls(tester);
      expect(
        rendered.any((u) => u.contains(originalUrl)),
        isTrue,
        reason: 'UNBLURRED tile must render the original source '
            '(rendered: $rendered)',
      );
      expect(
        rendered.any((u) => u.contains(blurredUrl)),
        isFalse,
        reason: 'UNBLURRED tile must NEVER render the blurred source '
            '(rendered: $rendered)',
      );

      // "Yes, use blurred photos" -- must render ONLY the distinct
      // processed/blurred URL. THE KEY ASSERTION for the reported bug:
      // if the choice screen ever silently keeps painting the original
      // bytes while claiming "Blurred photos", this fails here.
      await tester.tap(find.text('Yes, use blurred photos'));
      await settle(tester);

      rendered = _renderedNetworkImageUrls(tester);
      expect(
        rendered.any((u) => u.contains(blurredUrl)),
        isTrue,
        reason: 'BLURRED tile must render the distinct processed/blurred '
            'source returned by the blur job (rendered: $rendered)',
      );
      expect(
        rendered.any((u) => u.contains(originalUrl)),
        isFalse,
        reason: 'BLURRED tile must NEVER render the original, unblurred '
            'source (rendered: $rendered)',
      );
    },
  );
}
