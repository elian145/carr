// F-41: multi-photo upload progress is visible AND accessible, and the banner
// offers a confirmed, safe cancel.
import 'package:car_listing_app/app/carzo_shared.dart'
    show productionNavigatorKey;
import 'package:car_listing_app/app/widgets/sell_submission_status_banner.dart';
import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/l10n/app_localizations_en.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final AppLocalizationsEn _en = AppLocalizationsEn();

Widget _app() => MaterialApp(
      navigatorKey: productionNavigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SellSubmissionStatusBanner(
        child: Scaffold(body: SizedBox()),
      ),
    );

SellSubmissionUiStatus _status({bool isEdit = false}) => SellSubmissionUiStatus(
      draftId: 'd1',
      phase: SellSubmissionPhase.uploadingPhotos,
      completedMediaCount: 2,
      totalMediaCount: 4,
      isEdit: isEdit,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = PendingSellSubmissionService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc.statusNotifier.value = null;
  });
  tearDown(() => svc.statusNotifier.value = null);

  testWidgets('progress is determinate and announced as a live region',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    svc.statusNotifier.value = _status();
    await tester.pump();

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, 0.5);

    final label = _en.sellSubmissionUploadingProgress(2, 4);
    final node = tester.getSemantics(find.bySemanticsLabel(label));
    expect(node.value, '50%');
    expect(node.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  test('unknown total => indeterminate (null), never a bogus 0%', () {
    expect(
      sellSubmissionProgressFraction(
        const SellSubmissionUiStatus(
          draftId: 'd',
          phase: SellSubmissionPhase.creating,
          completedMediaCount: 0,
          totalMediaCount: 0,
        ),
      ),
      isNull,
    );
  });

  testWidgets('cancel button has a tooltip, 48dp target and is hidden for edits',
      (tester) async {
    await tester.pumpWidget(_app());
    svc.statusNotifier.value = _status();
    await tester.pump();
    final btn = find.byTooltip(_en.a11yCancelUpload);
    expect(btn, findsOneWidget);
    final size = tester.getSize(btn);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    svc.statusNotifier.value = _status(isEdit: true);
    await tester.pump();
    expect(find.byTooltip(_en.a11yCancelUpload), findsNothing);
  });

  testWidgets('cancel asks first; "keep uploading" changes nothing',
      (tester) async {
    await SellSubmissionStatePrefs.upsert(
      SellSubmissionRecord(
        draftId: 'd1',
        status: SellSubmissionStatus.inProgress,
        carData: const {},
        idempotencyKey: 'k',
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    await tester.pumpWidget(_app());
    svc.statusNotifier.value = _status();
    await tester.pump();

    await tester.tap(find.byTooltip(_en.a11yCancelUpload));
    await tester.pumpAndSettle();
    expect(find.text(_en.a11yCancelUploadConfirm), findsOneWidget);

    await tester.tap(find.text(_en.a11yKeepUploading));
    await tester.pumpAndSettle();
    expect(await SellSubmissionStatePrefs.load('d1'), isNotNull);
    expect(svc.isCancelRequested('d1'), isFalse);
  });

  testWidgets('confirming cancel before the listing exists removes the record',
      (tester) async {
    await tester.runAsync(() => SellSubmissionStatePrefs.upsert(
          SellSubmissionRecord(
            draftId: 'd1',
            status: SellSubmissionStatus.inProgress,
            carData: const {},
            idempotencyKey: 'k',
            createdAt: 1,
            updatedAt: 1,
          ),
        ));
    await tester.pumpWidget(_app());
    svc.statusNotifier.value = _status();
    await tester.pump();

    await tester.tap(find.byTooltip(_en.a11yCancelUpload));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, _en.a11yCancelUpload));
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 50),
        ));
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(() => SellSubmissionStatePrefs.load('d1')),
      isNull,
    );
    expect(find.text(_en.a11yUploadCancelledDraftKept), findsOneWidget);
  });
}
