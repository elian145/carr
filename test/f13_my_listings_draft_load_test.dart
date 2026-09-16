// Regression tests for F-13: `_MyListingsPageState._loadDrafts()`'s outer
// safety-net `catch` must be observable (via `logNonFatal`, which reports to
// Sentry), not silently swallowed — see PRODUCTION_AUDIT.md F-13.
//
// The three known corrupt-prefs sources (`SellListingDraftPrefs.load` and
// `LegacySellDraftList`'s snapshot/archive decoders — `SellPendingMediaResume`
// is not exercised here, it has no bearing on draft *rendering*) already
// catch and `logNonFatal` their own decode failures internally and never
// reach the outer catch in `my_listings_page.dart`. Tests A and B prove that
// directly against real corrupt `SharedPreferences` data (no mocking of
// production logic). Test C proves isolation: a corrupt source does not
// prevent a valid draft from a different source from still rendering. Test D
// exercises the remaining outer safety-net catch itself — no real local
// corruption is currently known to reach it (see investigation notes), so it
// uses the minimal `debugMyListingsLoadDraftsError` test hook added
// alongside this fix, mirroring this repo's existing
// `debugLogNonFatalOverride` / `AuthService.debugProfileRetryDelaysOverride`
// test-seam convention. This scope is intentionally narrow (observability
// only): these tests do not exercise draft resume/discard, media
// persistence, or backend sync behavior — those are unchanged and out of
// scope.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/pages/my_listings_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/debug/app_log.dart';
import 'package:car_listing_app/shared/prefs/legacy_sell_draft_prefs.dart';
import 'package:car_listing_app/shared/prefs/sell_listing_draft_prefs.dart';

import 'fake_api_server.dart';

/// Pre-existing, unrelated rendering defect in this test environment (also
/// documented in `test/f04_favorites_mounted_guard_test.dart` and
/// `test/car_detail_error_states_test.dart`): `MainShell`'s
/// `BottomNavigationBar` stays mounted underneath any pushed route and
/// reports `RenderFlex`/`TextScaler` noise regardless of which page is
/// pushed on top of it. Not caused by, and out of scope for, F-13 — filtered
/// out here by message so any other, genuinely unexpected error still fails
/// the test.
bool _isKnownPreexistingShellRenderingNoise(FlutterErrorDetails details) {
  final message = details.exceptionAsString();
  return message.contains('RenderFlex overflowed') ||
      message.contains('maxScale > minScale');
}

/// One captured invocation of `logNonFatal` (via [debugLogNonFatalOverride]).
class _ReportedNonFatal {
  _ReportedNonFatal(this.error, this.stackTrace, this.context);
  final Object error;
  final StackTrace? stackTrace;
  final String? context;
}

void main() {
  final reported = <_ReportedNonFatal>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    reported.clear();
    debugLogNonFatalOverride = (error, stackTrace, context) {
      reported.add(_ReportedNonFatal(error, stackTrace, context));
    };
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
    debugLogNonFatalOverride = null;
    debugMyListingsLoadDraftsError = null;
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  /// Pumps the full app, navigates to My Listings, and switches to the
  /// Draft filter tab, mirroring `test/legacy_my_listings_widget_test.dart`.
  Future<void> pumpToDraftTab(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

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

  testWidgets(
    'A. malformed modern draft JSON is handled without crashing and logs a non-fatal event',
    (tester) async {
      final capturedErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (_isKnownPreexistingShellRenderingNoise(details)) return;
        capturedErrors.add(details);
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      // Test user's id is 1, so `_buildDraftOwnerKey()` resolves to '1'.
      SharedPreferences.setMockInitialValues({
        'push_enabled': false,
        SellListingDraftPrefs.keyFor('1'): '{not valid json',
      });

      await pumpToDraftTab(tester);

      // No crash, and the page still renders its (degraded) empty state.
      expect(find.text('No drafts'), findsOneWidget);
      expect(capturedErrors, isEmpty);

      // `SellListingDraftPrefs.load` must have reported the decode failure.
      final formatExceptionReports =
          reported.where((r) => r.error is FormatException).toList();
      expect(
        formatExceptionReports,
        isNotEmpty,
        reason:
            'SellListingDraftPrefs.load should logNonFatal the malformed JSON',
      );
      // Documents current (pre-existing, out-of-scope) behavior: this
      // internal loader reports without a context string, unlike the F-13
      // fix applied to the outer catch below.
      expect(formatExceptionReports.first.context, isNull);
      expect(formatExceptionReports.first.stackTrace, isNotNull);
    },
  );

  testWidgets(
    'B. malformed legacy archive is handled without crashing and logs a non-fatal event',
    (tester) async {
      final capturedErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (_isKnownPreexistingShellRenderingNoise(details)) return;
        capturedErrors.add(details);
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      SharedPreferences.setMockInitialValues({
        'push_enabled': false,
        LegacySellDraftPrefs.archiveKey: '[{"draftId": "broken", ',
      });

      await pumpToDraftTab(tester);

      expect(find.text('No drafts'), findsOneWidget);
      expect(capturedErrors, isEmpty);

      final formatExceptionReports =
          reported.where((r) => r.error is FormatException).toList();
      expect(
        formatExceptionReports,
        isNotEmpty,
        reason:
            'LegacySellDraftList._decodeArchive should logNonFatal the malformed JSON',
      );
      expect(formatExceptionReports.first.context, isNull);
    },
  );

  testWidgets(
    'C. a valid draft from an unaffected source still loads when another source is corrupt',
    (tester) async {
      final capturedErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (_isKnownPreexistingShellRenderingNoise(details)) return;
        capturedErrors.add(details);
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      // Modern draft source is corrupt; the legacy archive has one valid,
      // visible draft. The valid draft must still render.
      SharedPreferences.setMockInitialValues({
        'push_enabled': false,
        SellListingDraftPrefs.keyFor('1'): '{not valid json',
        LegacySellDraftPrefs.archiveKey: '[${_validLegacyDraftJson()}]',
      });

      await pumpToDraftTab(tester);

      // The legacy draft card renders (each draft card shows a 'DRAFT'
      // badge — see `_MyListingsPageWidgets._buildDraftCard`).
      expect(find.text('DRAFT'), findsOneWidget);
      expect(find.text('No drafts'), findsNothing);
      expect(capturedErrors, isEmpty);

      // The corrupt modern source is still reported, proving isolation
      // (one corrupt source does not suppress reporting for, or block
      // rendering of, an unaffected source).
      expect(reported.where((r) => r.error is FormatException), isNotEmpty);
    },
  );

  testWidgets(
    'D. _loadDrafts() outer catch logs with context MyListingsPage._loadDrafts',
    (tester) async {
      final capturedErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (_isKnownPreexistingShellRenderingNoise(details)) return;
        capturedErrors.add(details);
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      SharedPreferences.setMockInitialValues({'push_enabled': false});

      final injected = Exception('F-13 injected unexpected draft-load error');
      debugMyListingsLoadDraftsError = injected;

      await pumpToDraftTab(tester);

      // No crash: the outer catch still swallows the error and degrades to
      // the empty-drafts state, exactly as before this fix.
      expect(find.text('No drafts'), findsOneWidget);
      expect(capturedErrors, isEmpty);

      // The fix: this path is now observable with the expected context.
      final ownReports =
          reported.where((r) => identical(r.error, injected)).toList();
      expect(ownReports, hasLength(1));
      expect(ownReports.single.context, 'MyListingsPage._loadDrafts');
      expect(ownReports.single.stackTrace, isNotNull);

      // The hook self-clears after firing once.
      expect(debugMyListingsLoadDraftsError, isNull);
    },
  );
}

/// A minimal, valid, visible legacy sell-draft archive entry (JSON object
/// literal, to be embedded inside a `[...]` archive array by the caller).
String _validLegacyDraftJson() => '''
{
  "draftId": "f13_valid_draft",
  "currentStep": 1,
  "carData": {"brand": "Toyota", "model": "Camry"},
  "isPlaceholder": false,
  "updatedAt": 1700000000000
}
''';
