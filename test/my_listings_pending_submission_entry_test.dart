// BUG 2 regression ("listing disappears after backgrounding the app").
//
// Before the fix a draft was hidden whenever ANY durable submission record
// existed for it (including `needsAttention` / not-yet-created ones), while
// My Listings rendered NO entry for a record at all -- so the user's
// listing simply vanished. A draft may now only be hidden when its
// superseding submission is shown as a visible, recoverable pending entry.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/pages/my_listings_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/prefs/legacy_sell_draft_prefs.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';

import 'fake_api_server.dart';

bool _isKnownPreexistingShellRenderingNoise(FlutterErrorDetails details) {
  final message = details.exceptionAsString();
  return message.contains('RenderFlex overflowed') ||
      message.contains('maxScale > minScale');
}

String _draftJson(String id, String brand, String model) => '''
{
  "draftId": "$id",
  "currentStep": 5,
  "carData": {"brand": "$brand", "model": "$model"},
  "isPlaceholder": false,
  "updatedAt": 1700000000000
}
''';

SellSubmissionRecord _record(
  String draftId,
  SellSubmissionStatus status, {
  bool isEdit = false,
  String? lastError,
  Map<String, dynamic>? carData,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return SellSubmissionRecord(
    draftId: draftId,
    status: status,
    isEdit: isEdit,
    carData: carData ?? const {'brand': 'kia', 'model': 'Sportage'},
    idempotencyKey: 'sell-create-$draftId',
    lastErrorMessage: lastError,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
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
    debugMyListingsLoadDraftsError = null;
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Future<void> pumpMyListings(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/my_listings');
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void ignoreShellNoise(WidgetTester tester) {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (_isKnownPreexistingShellRenderingNoise(details)) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  testWidgets(
    'a needsAttention submission whose listing was never created is shown as '
    'a visible pending entry with a Retry action AND its editable draft '
    'stays visible so the user can replace photos; an unrelated draft stays '
    'too, and NO draft data is deleted',
    (tester) async {
      ignoreShellNoise(tester);
      SharedPreferences.setMockInitialValues({
        'push_enabled': false,
        LegacySellDraftPrefs.archiveKey:
            '[${_draftJson('unrelated_draft', 'Toyota', 'Camry')}, '
            '${_draftJson('submitted_draft', 'Kia', 'Sportage')}]',
      });
      await SellSubmissionStatePrefs.upsert(
        _record(
          'submitted_draft',
          SellSubmissionStatus.needsAttention,
          lastError: 'Your 2 selected photo/video file(s) are no longer '
              'available (a.jpg). Please re-add them and submit again.',
        ),
      );

      await pumpMyListings(tester);

      // The listing is NOT gone: it has a visible pending entry...
      expect(
        find.byKey(const ValueKey<String>('pending-submission-submitted_draft')),
        findsOneWidget,
      );
      expect(find.text('Needs attention'), findsOneWidget);
      expect(
        find.textContaining('no longer available'),
        findsOneWidget,
        reason: 'the real reason is shown, not a silent disappearance',
      );
      // ...with a recoverable Retry action.
      expect(
        find.byKey(
          const ValueKey<String>('pending-submission-retry-submitted_draft'),
        ),
        findsOneWidget,
      );

      // Nothing was created server-side yet, so the draft is the user's way
      // to replace the unavailable photos: it stays visible NEXT TO the
      // entry (never hidden, never deleted), as does the unrelated draft.
      expect(find.text('DRAFT'), findsNWidgets(2));
      expect(find.textContaining('Toyota'), findsOneWidget);
      expect(find.textContaining('Kia'), findsOneWidget);

      // Nothing was deleted: both drafts and the record remain durable.
      final sp = await SharedPreferences.getInstance();
      final archive = sp.getString(LegacySellDraftPrefs.archiveKey) ?? '';
      expect(archive, contains('unrelated_draft'));
      expect(archive, contains('submitted_draft'));
      expect(
        await SellSubmissionStatePrefs.load('submitted_draft'),
        isNotNull,
      );
    },
  );

  testWidgets(
    'once the listing exists server-side the draft is consumed: the entry '
    'replaces it (hidden only because the entry is visible), the unrelated '
    'draft stays, and nothing is deleted',
    (tester) async {
      ignoreShellNoise(tester);
      SharedPreferences.setMockInitialValues({
        'push_enabled': false,
        LegacySellDraftPrefs.archiveKey:
            '[${_draftJson('unrelated_draft', 'Toyota', 'Camry')}, '
            '${_draftJson('submitted_draft', 'Kia', 'Sportage')}]',
      });
      final base = _record(
        'submitted_draft',
        SellSubmissionStatus.needsAttention,
        lastError: 'Photos could not be confirmed.',
      );
      await SellSubmissionStatePrefs.upsert(base.copyWith(carId: 'car_77'));

      await pumpMyListings(tester);

      expect(
        find.byKey(const ValueKey<String>('pending-submission-submitted_draft')),
        findsOneWidget,
      );
      expect(find.text('DRAFT'), findsOneWidget);
      expect(find.textContaining('Toyota'), findsOneWidget);
      expect(find.textContaining('Kia'), findsNothing);

      final sp = await SharedPreferences.getInstance();
      final archive = sp.getString(LegacySellDraftPrefs.archiveKey) ?? '';
      expect(archive, contains('submitted_draft'), reason: 'never deleted');
      expect(
        await SellSubmissionStatePrefs.load('submitted_draft'),
        isNotNull,
      );
    },
  );

  testWidgets(
    'a draft is NEVER hidden without a visible replacement: a completed '
    'record (listing already live) or an edit record has no pending entry, '
    'so the ordinary draft stays visible',
    (tester) async {
      ignoreShellNoise(tester);
      SharedPreferences.setMockInitialValues({
        'push_enabled': false,
        LegacySellDraftPrefs.archiveKey:
            '[${_draftJson('done_draft', 'Honda', 'Civic')}, '
            '${_draftJson('edit_draft', 'Ford', 'Focus')}]',
      });
      await SellSubmissionStatePrefs.upsert(
        _record('done_draft', SellSubmissionStatus.completed),
      );
      await SellSubmissionStatePrefs.upsert(
        _record('edit_draft', SellSubmissionStatus.needsAttention, isEdit: true),
      );

      await pumpMyListings(tester);

      expect(
        find.byKey(const ValueKey<String>('pending-submission-done_draft')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('pending-submission-edit_draft')),
        findsNothing,
      );
      expect(find.textContaining('Honda'), findsOneWidget);
      expect(find.textContaining('Ford'), findsOneWidget);
    },
  );

  testWidgets(
    'every in-flight state (pending / in progress / retryable) is also '
    'represented by a visible pending entry after a cold start',
    (tester) async {
      ignoreShellNoise(tester);
      SharedPreferences.setMockInitialValues({'push_enabled': false});
      // Retryable with a far-future-looking attempt budget is not auto-run
      // by the page; needsAttention-like states are covered above. A
      // `retryable` record must be visible while it waits.
      await SellSubmissionStatePrefs.upsert(
        _record(
          'waiting_draft',
          SellSubmissionStatus.retryable,
          lastError: 'Network connection lost.',
        ),
      );

      await pumpMyListings(tester);

      expect(
        find.byKey(const ValueKey<String>('pending-submission-waiting_draft')),
        findsOneWidget,
      );
    },
  );
}
