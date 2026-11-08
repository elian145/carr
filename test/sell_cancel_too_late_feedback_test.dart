// A cancel the service REFUSES (nothing cancellable: e.g. everything is already
// confirmed and the listing is being published) must tell the user instead of
// silently doing nothing; an ACCEPTED cancel must not show that message.
import 'package:car_listing_app/app/carzo_shared.dart'
    show productionNavigatorKey;
import 'package:car_listing_app/app/widgets/sell_submission_status_banner.dart';
import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/features/sell/sell_cancel_refused_feedback.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/l10n/app_localizations_ar.dart';
import 'package:car_listing_app/l10n/app_localizations_en.dart';
import 'package:car_listing_app/l10n/app_localizations_ku.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final AppLocalizationsEn _en = AppLocalizationsEn();

Widget _app() => MaterialApp(
  navigatorKey: productionNavigatorKey,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) =>
      SellSubmissionStatusBanner(child: child ?? const SizedBox.shrink()),
  home: const Scaffold(body: SizedBox()),
);

const SellSubmissionUiStatus _status = SellSubmissionUiStatus(
  draftId: 'd1',
  phase: SellSubmissionPhase.uploadingPhotos,
  completedMediaCount: 4,
  totalMediaCount: 4,
);

SellSubmissionRecord _record(SellSubmissionStatus status) =>
    SellSubmissionRecord(
      draftId: 'd1',
      status: status,
      carData: const {},
      idempotencyKey: 'k',
      createdAt: 1,
      updatedAt: 1,
    );

Future<void> _tapCancelAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(kSellSubmissionBannerCancelKey));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, _en.a11yCancelUpload));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = PendingSellSubmissionService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc.statusNotifier.value = null;
  });
  tearDown(() => svc.statusNotifier.value = null);

  testWidgets('refused cancel (nothing cancellable) shows the too-late '
      'message as a live region', (tester) async {
    final handle = tester.ensureSemantics();
    // No record for the draft => cancelSubmission returns null (refused).
    expect(await tester.runAsync(() => svc.cancelSubmission('d1')), isNull);

    await tester.pumpWidget(_app());
    svc.statusNotifier.value = _status;
    await tester.pump();
    await _tapCancelAndConfirm(tester);

    expect(find.byKey(kSellCancelTooLateKey), findsOneWidget);
    expect(find.text(_en.a11yUploadCancelTooLate), findsOneWidget);
    expect(find.text(_en.a11yUploadCancelledDraftKept), findsNothing);
    final node = tester.getSemantics(find.byKey(kSellCancelTooLateKey));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    expect(node.label, _en.a11yUploadCancelTooLate);
    // The refused cancel changed nothing.
    expect(svc.isCancelRequested('d1'), isFalse);
    handle.dispose();
  });

  testWidgets('a cancel for an already-completed record is '
      'refused and says so', (tester) async {
    await tester.runAsync(
      () => SellSubmissionStatePrefs.upsert(
        _record(SellSubmissionStatus.completed),
      ),
    );
    await tester.pumpWidget(_app());
    svc.statusNotifier.value = _status;
    await tester.pump();
    await _tapCancelAndConfirm(tester);
    expect(find.byKey(kSellCancelTooLateKey), findsOneWidget);
  });

  testWidgets('accepted cancel shows "draft kept", NOT the too-late message', (
    tester,
  ) async {
    await tester.runAsync(
      () => SellSubmissionStatePrefs.upsert(
        _record(SellSubmissionStatus.inProgress),
      ),
    );
    await tester.pumpWidget(_app());
    svc.statusNotifier.value = _status;
    await tester.pump();
    await _tapCancelAndConfirm(tester);

    expect(find.text(_en.a11yUploadCancelledDraftKept), findsOneWidget);
    expect(find.byKey(kSellCancelTooLateKey), findsNothing);
    expect(find.text(_en.a11yUploadCancelTooLate), findsNothing);
  });

  testWidgets('"keep uploading" shows no too-late message', (tester) async {
    await tester.pumpWidget(_app());
    svc.statusNotifier.value = _status;
    await tester.pump();
    await tester.tap(find.byKey(kSellSubmissionBannerCancelKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.a11yKeepUploading));
    await tester.pumpAndSettle();
    expect(find.byKey(kSellCancelTooLateKey), findsNothing);
  });

  test('the too-late string exists, is non-empty and differs per locale', () {
    final en = AppLocalizationsEn().a11yUploadCancelTooLate;
    final ar = AppLocalizationsAr().a11yUploadCancelTooLate;
    final ku = AppLocalizationsKu().a11yUploadCancelTooLate;
    expect({en, ar, ku}.length, 3);
    for (final s in [en, ar, ku]) {
      expect(s.trim(), isNotEmpty);
    }
  });
}
