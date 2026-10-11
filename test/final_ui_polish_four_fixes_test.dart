import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/listings/listing_uploaded_ago.dart';
import 'package:car_listing_app/shared/prefs/legacy_sell_draft_prefs.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

/// Focused coverage for the four final store-release UI polish fixes.
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

  Future<void> pumpToDraftTab(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await settle(tester);

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

  group('Fix 2 — blur preview has no bottom status paragraph', () {
    testWidgets(
      'blur choice screen never shows the removed bottom status paragraph',
      (tester) async {
        await tester.pumpWidget(const legacy.MyApp());
        await settle(tester);

        await openSellDraftStep(
          tester,
          step: 4,
          carData: {
            ...sellCarDataThroughStep4(),
            'sell_wizard_v2': true,
            'original_images': <dynamic>[
              'uploads/original_1.jpg',
              'uploads/original_2.jpg',
            ],
            'blurred_images': <dynamic>[
              {
                'source': 'uploads/original_1.jpg',
                'blur_pending': true,
              },
              {
                'source': 'uploads/original_2.jpg',
                'blur_pending': true,
              },
            ],
            'images': <dynamic>['uploads/original_1.jpg'],
            'images_processed': true,
            'use_blurred_plates': true,
          },
        );
        await settle(tester);

        final yesBlur = find.text('Yes, use blurred photos');
        if (yesBlur.evaluate().isNotEmpty) {
          await tester.tap(yesBlur);
          await settle(tester);
        }

        expect(
          find.text(
            'Still blurring plates in the background. Photos will appear here when ready.',
          ),
          findsNothing,
          reason: 'bottom status paragraph must be removed',
        );
      },
    );
  });

  group('Fix 3 — empty draft listing card', () {
    testWidgets(
      'empty-photo draft renders designed card with continue/delete and no broken image',
      (tester) async {
        // Meaningful carData (so the draft is visible) but no photos.
        SharedPreferences.setMockInitialValues({
          'push_enabled': false,
          'app_locale': 'en',
          LegacySellDraftPrefs.archiveKey: jsonEncode([
            {
              'draftId': 'empty_draft_ui_polish',
              'currentStep': 0,
              'carData': {
                'brand': 'toyota',
                'model': 'camry',
                'images': <dynamic>[],
              },
              'isPlaceholder': false,
              'updatedAt': 1700000000000,
            },
          ]),
        });

        await pumpToDraftTab(tester);

        expect(find.text('DRAFT'), findsOneWidget);
        expect(find.text('Continue editing'), findsOneWidget);
        expect(find.text('Add photos to continue'), findsOneWidget);
        expect(find.text('Contact for price'), findsNothing);
        expect(find.byIcon(Icons.broken_image), findsNothing);
        expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
        expect(
          find.byKey(const ValueKey('draft-delete-empty_draft_ui_polish')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('draft-continue-empty_draft_ui_polish')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('draft-card-empty_draft_ui_polish')),
          findsOneWidget,
        );
        // Title comes from localized brand/model (case preserved from catalog).
        expect(find.textContaining('camry'), findsWidgets);
      },
    );

    testWidgets(
      'untitled empty draft uses localized untitled fallback title',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'push_enabled': false,
          'app_locale': 'en',
          LegacySellDraftPrefs.archiveKey: jsonEncode([
            {
              'draftId': 'untitled_empty_draft',
              'currentStep': 2,
              'carData': {
                // Meaningful but untitled (no brand/model/year/trim).
                'city': 'Erbil',
                'images': <dynamic>[],
              },
              'isPlaceholder': false,
              'updatedAt': 1700000000000,
            },
          ]),
        });

        await pumpToDraftTab(tester);

        expect(find.text('Untitled draft'), findsOneWidget);
        expect(find.text('Continue editing'), findsOneWidget);
        expect(find.byIcon(Icons.broken_image), findsNothing);
      },
    );
  });

  group('Fix 4A — Arabic relative age does not truncate', () {
    testWidgets(
      'Arabic listing age renders the full localized string on a phone width',
      (tester) async {
        final createdAt = DateTime.now()
            .subtract(const Duration(days: 12))
            .toUtc()
            .toIso8601String();
        late String expectedAge;
        late String renderedAge;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: Size(390, 844)),
              child: Builder(
                builder: (context) {
                  expectedAge = AppLocalizations.of(context)!.timeDaysAgo(12);
                  renderedAge = listingUploadedAgo(context, {
                    'created_at': createdAt,
                  });
                  return Scaffold(
                    body: SizedBox(
                      width: 390,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Toyota Avalon 2021'),
                          const Text(r'$6,555'),
                          const Text('المدينة: بغداد'),
                          Text(
                            renderedAge,
                            softWrap: true,
                            maxLines: 2,
                            overflow: TextOverflow.visible,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(expectedAge, 'قبل 12 يوماً');
        expect(renderedAge, expectedAge);
        expect(find.text(expectedAge), findsOneWidget);
        expect(find.textContaining('يو...'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Fix 4B — VIDEO badge respects iPhone top safe area', () {
    testWidgets(
      'hero VIDEO badge sits below status bar + toolbar inset',
      (tester) async {
        const topSafe = 59.0;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = FakeViewPadding(
          top: topSafe,
          left: 0,
          right: 0,
          bottom: 0,
        );
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);

        const carId = 'video_badge_safe_area_1';
        final listing = sampleDetailListing(carId)
          ..['videos'] = <dynamic>['uploads/clip.mp4']
          ..['images'] = <dynamic>[]
          ..['city'] = 'Baghdad'
          ..['created_at'] = DateTime.now()
              .subtract(const Duration(days: 12))
              .toUtc()
              .toIso8601String();
        seedCarDetailCache(carId, listing: listing);
        FakeApiServer.carDetailOverrides[carId] = () => http.Response(
              jsonEncode({'car': listing}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
        addTearDown(() => FakeApiServer.carDetailOverrides.remove(carId));

        await tester.pumpWidget(const legacy.MyApp());
        await settle(tester);

        final nav = tester.state<NavigatorState>(find.byType(Navigator));
        nav.pushNamed('/car_detail', arguments: {'carId': carId});
        await tester.pump();

        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find
              .byKey(const ValueKey<String>('listing-hero-video-badge'))
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }

        final badge = find.byKey(
          const ValueKey<String>('listing-hero-video-badge'),
        );
        expect(badge, findsOneWidget, reason: 'VIDEO badge should render');

        final box = tester.renderObject<RenderBox>(badge);
        final top = box.localToGlobal(Offset.zero).dy;
        expect(
          top,
          greaterThanOrEqualTo(topSafe + kToolbarHeight),
          reason: 'VIDEO badge must clear status bar and AppBar toolbar',
        );
        expect(find.text('VIDEO'), findsOneWidget);
      },
    );
  });

  group('Fix 1 companion — listing-level analytics icon still present', () {
    testWidgets(
      'owner listing detail still exposes insights analytics action',
      (tester) async {
        const carId = 'owner_analytics_icon_1';
        final listing = sampleDetailListing(carId)
          ..['seller_id'] = '1'
          ..['seller'] = {
            'id': 1,
            'user_id': 1,
            'username': 'seller',
          };
        seedCarDetailCache(carId, listing: listing);
        FakeApiServer.carDetailOverrides[carId] = () => http.Response(
              jsonEncode({'car': listing}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
        addTearDown(() => FakeApiServer.carDetailOverrides.remove(carId));

        await tester.pumpWidget(const legacy.MyApp());
        await settle(tester);

        final nav = tester.state<NavigatorState>(find.byType(Navigator));
        nav.pushNamed(
          '/car_detail',
          arguments: {
            'carId': carId,
            'allowOwnerManagement': true,
          },
        );
        await tester.pump();

        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.byIcon(Icons.insights_outlined).evaluate().isNotEmpty) {
            break;
          }
        }

        expect(
          find.byIcon(Icons.insights_outlined),
          findsOneWidget,
          reason: 'per-listing analytics icon must remain on listing details',
        );
      },
    );
  });
}
