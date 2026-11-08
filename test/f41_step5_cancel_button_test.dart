// F-41: the Step 5 "submitting" overlay's Cancel button.
//
// Drives the REAL Sell wizard on its review/submit step, flips it into the
// submitting state and taps Cancel -> confirm, asserting the durable
// submission record is handled safely (draft kept / listing never deleted).
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:car_listing_app/features/sell/sell_wizard_steps.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/feature_flags.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cached_image_store_test_support.dart';

const _draftId = 'f41-step5-cancel';

SellSubmissionRecord _record({String? carId}) => SellSubmissionRecord(
      draftId: _draftId,
      status: SellSubmissionStatus.inProgress,
      carData: const {'brand': 'toyota'},
      idempotencyKey: 'k-step5',
      createdAt: 1,
      updatedAt: 1,
      carId: carId,
    );

/// The overlay's spinner animates forever, so pumpAndSettle never returns.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('f41_step5').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
    primeCachedImageStoreForTests();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FeatureFlags.setCachedForTests(FeatureFlagsSnapshot.defaults());
  });

  tearDown(FeatureFlags.resetCacheForTests);

  Widget app() => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SellCarPage(
          initialDraftSnapshot: <String, dynamic>{
            'draftId': _draftId,
            'currentStep': SellWizardSteps.reviewSubmit,
            'updatedAt': 1700000000000,
            'carData': <String, dynamic>{
              'brand': 'Toyota',
              'model': 'Camry',
              'year': '2020',
            },
          },
        ),
      );

  Future<dynamic> openStep5AndSubmitting(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 300));
    final s5 = tester.state(find.byType(SellStep5Page)) as dynamic;
    // The overlay is driven purely by this state flag.
    s5.setState(() {
      s5.isSubmitting = true;
    });
    await tester.pump();
    return s5;
  }

  testWidgets('the overlay shows a Cancel button with a 48dp target',
      (tester) async {
    await openStep5AndSubmitting(tester);
    final cancel = find.widgetWithText(TextButton, 'Cancel upload');
    expect(cancel, findsOneWidget);
    final size = tester.getSize(cancel);
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  testWidgets('Keep uploading closes the dialog and changes nothing',
      (tester) async {
    await tester.runAsync(() => SellSubmissionStatePrefs.upsert(_record()));
    final s5 = await openStep5AndSubmitting(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel upload'));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Keep uploading'));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(await SellSubmissionStatePrefs.load(_draftId), isNotNull);
    expect(s5.submitCancelRequested, isFalse);
  });

  testWidgets(
      'confirming Cancel before the listing exists removes only the '
      'submission record (draft kept)', (tester) async {
    await tester.runAsync(() => SellSubmissionStatePrefs.upsert(_record()));
    await openStep5AndSubmitting(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel upload'));
    await _settle(tester);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Cancel upload'),
    ));
    await _settle(tester);

    await tester.runAsync(() async {
      expect(await SellSubmissionStatePrefs.load(_draftId), isNull);
    });
    expect(PendingSellSubmissionService.instance.isCancelRequested(_draftId),
        isFalse);
  });

  testWidgets(
      'confirming Cancel after the listing exists keeps it (needsAttention, '
      'never deleted)', (tester) async {
    await tester.runAsync(() => SellSubmissionStatePrefs.upsert(_record(carId: 'car_77')));
    await openStep5AndSubmitting(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel upload'));
    await _settle(tester);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Cancel upload'),
    ));
    await _settle(tester);

    await tester.runAsync(() async {
      final r = await SellSubmissionStatePrefs.load(_draftId);
      expect(r, isNotNull);
      expect(r!.status, SellSubmissionStatus.needsAttention);
      expect(r.carId, 'car_77');
      expect(r.lastErrorRetryable, isFalse);
    });
  });

  testWidgets(
      'Cancel before the service has any record (validation window) arms the '
      'submit flow to stop instead of being a no-op', (tester) async {
    final s5 = await openStep5AndSubmitting(tester);
    expect(await SellSubmissionStatePrefs.load(_draftId), isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel upload'));
    await _settle(tester);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Cancel upload'),
    ));
    await _settle(tester);

    expect(s5.submitCancelRequested, isTrue);
  });
}
