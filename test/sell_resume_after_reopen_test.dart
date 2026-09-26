// Regression tests for the "submission does not resume after app
// close/reopen" bug report: once Submit has durably recorded a
// `PendingSellSubmissionRecord` for a draftId, that draftId must no longer
// be treated as an ordinary, freely "Continue"/"Discard"-able draft by the
// Sell entry points -- even though the ordinary draft snapshot for that
// same draftId is only cleared once the listing is actually created (see
// `discardSellDraftById`, called from
// `PendingSellSubmissionService._runSubmission` only AFTER a successful
// create), leaving a real window where both exist at once.
//
// Root cause: `SellDraftGatePage` (the "Drafts in progress" list) and
// `SellEntryRouterPage` (decides whether tapping "Sell" shows that list or
// goes straight to a fresh listing) both read ONLY the ordinary draft
// snapshot/archive, with zero awareness of `SellSubmissionStatePrefs` /
// `PendingSellSubmissionRecord`. If the app is killed and reopened between
// "Submit pressed" and "listing created", these entry points showed the
// still-in-flight submission as a plain, editable draft -- exactly the
// reported "instead the Sell data appears as a draft" symptom -- even
// though `PendingSellSubmissionService.resumeAll()` was (and still is)
// already correctly auto-resuming it in the background (see
// `pending_sell_submission_service_test.dart` for full resume-mechanism
// coverage; this file is purely about what these two entry points DISPLAY
// while that background resume is in flight).
import 'dart:convert';

import 'package:car_listing_app/features/sell/sell_draft_gate.dart';
import 'package:car_listing_app/features/sell/sell_entry_router.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/feature_flags.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Map<String, dynamic> _pendingCarData = {
  'brand': 'Toyota',
  'model': 'Corolla',
  'trim': 'LE',
  'year': '2021',
};

const Map<String, dynamic> _otherCarData = {
  'brand': 'Kia',
  'model': 'Sportage',
  'trim': 'EX',
  'year': '2019',
};

Future<void> _seedPendingSubmission(String draftId) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await SellSubmissionStatePrefs.upsert(
    SellSubmissionRecord(
      draftId: draftId,
      status: SellSubmissionStatus.pending,
      carData: const {'brand': 'toyota', 'images': <dynamic>[]},
      idempotencyKey: 'sell-create-$draftId',
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Widget _appFor(Widget home, {Map<String, WidgetBuilder>? routes}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
    routes: routes ?? const {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FeatureFlags.setCachedForTests(FeatureFlagsSnapshot.defaults());
  });

  tearDown(() {
    FeatureFlags.resetCacheForTests();
  });

  group('SellDraftGatePage hides drafts with an active pending submission', () {
    testWidgets(
      'an active draft whose draftId has a pending submission is NOT shown '
      'as a continuable draft, while an unrelated ordinary draft still is',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'legacy_sell_draft_snapshot_v1': json.encode({
            'draftId': 'pending_draft',
            'currentStep': 5,
            'carData': _pendingCarData,
            'updatedAt': 1700000000000,
          }),
          'legacy_sell_draft_archive_v1': json.encode([
            {
              'draftId': 'other_draft',
              'currentStep': 1,
              'carData': _otherCarData,
              'updatedAt': 1690000000000,
            },
          ]),
        });
        await _seedPendingSubmission('pending_draft');

        await tester.pumpWidget(_appFor(const SellDraftGatePage()));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Toyota Corolla'),
          findsNothing,
          reason: 'the draftId with an active pending submission must not '
              'be offered as an ordinary continuable draft',
        );
        expect(
          find.textContaining('Kia Sportage'),
          findsOneWidget,
          reason: 'an unrelated ordinary draft must still show normally',
        );
      },
    );

    testWidgets(
      'once the pending submission record is gone (e.g. it completed or '
      'needs attention and was cleared), the same draftId snapshot is '
      'shown normally again',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'legacy_sell_draft_snapshot_v1': json.encode({
            'draftId': 'now_free_draft',
            'currentStep': 5,
            'carData': _pendingCarData,
            'updatedAt': 1700000000000,
          }),
        });
        // No SellSubmissionStatePrefs record for this draftId at all.

        await tester.pumpWidget(_appFor(const SellDraftGatePage()));
        await tester.pumpAndSettle();

        expect(find.textContaining('Toyota Corolla'), findsOneWidget);
      },
    );
  });

  group('SellEntryRouterPage does not route a pending-submission draftId '
      'as an ordinary "has a draft" signal', () {
    testWidgets(
      'the ONLY existing draft has an active pending submission -> routes '
      'straight to a fresh listing (startFresh), not the draft gate',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'legacy_sell_draft_snapshot_v1': json.encode({
            'draftId': 'only_pending_draft',
            'currentStep': 5,
            'carData': _pendingCarData,
            'updatedAt': 1700000000000,
          }),
        });
        await _seedPendingSubmission('only_pending_draft');

        Map<String, dynamic>? capturedArgs;
        await tester.pumpWidget(
          _appFor(
            const SellEntryRouterPage(),
            routes: {
              '/sell': (context) {
                capturedArgs = ModalRoute.of(context)!.settings.arguments
                    as Map<String, dynamic>?;
                return const Scaffold(body: Text('sell-page'));
              },
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('sell-page'), findsOneWidget);
        expect(
          capturedArgs,
          {'startFresh': true},
          reason: 'a draftId that is really an in-flight submission must '
              'never route the user into the ordinary draft gate',
        );
      },
    );

    testWidgets(
      'a pending-submission draft PLUS an unrelated ordinary draft -> '
      'still routes to the draft gate (for the ordinary one)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'legacy_sell_draft_snapshot_v1': json.encode({
            'draftId': 'pending_draft_2',
            'currentStep': 5,
            'carData': _pendingCarData,
            'updatedAt': 1700000000000,
          }),
          'legacy_sell_draft_archive_v1': json.encode([
            {
              'draftId': 'other_draft_2',
              'currentStep': 1,
              'carData': _otherCarData,
              'updatedAt': 1690000000000,
            },
          ]),
        });
        await _seedPendingSubmission('pending_draft_2');

        Map<String, dynamic>? capturedArgs;
        await tester.pumpWidget(
          _appFor(
            const SellEntryRouterPage(),
            routes: {
              '/sell': (context) {
                capturedArgs = ModalRoute.of(context)!.settings.arguments
                    as Map<String, dynamic>?;
                return const Scaffold(body: Text('sell-page'));
              },
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('sell-page'), findsOneWidget);
        expect(capturedArgs, {'showDraftGate': true});
      },
    );
  });
}
