// Widget-level coverage for `SellSubmissionStatusBanner` (see
// `lib/app/widgets/sell_submission_status_banner.dart`) -- the global,
// page-independent "Uploading listing…" progress banner mounted once in
// `MaterialApp.builder`.
//
// Phase 3B added three new `SellSubmissionPhase` values
// (`uploadingVideoSource`/`processingVideoOnServer`/`finishingVideoUpload`)
// specifically so this banner (and the Step 5 page-local status text --
// see `test/sell_step5_phase_label_source_mapping_test.dart`) can show a
// short, already-localized label for each server-transcode sub-phase
// instead of the generic "Uploading listing… X of Y media uploaded"
// message. Earlier verification only proved the `switch` COMPILES
// (exhaustiveness) and that the underlying orchestration *calls* the right
// phase via log lines -- this file drives the widget itself through the
// real `PendingSellSubmissionService.instance.statusNotifier` (exactly the
// mechanism `_runSubmission`'s `reportPhase()` uses in production) and
// asserts the actual RENDERED text, proving the enum wiring reaches
// visible UI, not merely that it type-checks.
//
// Expected label text is read from `AppLocalizationsEn` (the generated
// getters), never duplicated as a literal English string here, so this
// test can never silently drift from `lib/l10n/app_en.arb`.
import 'package:car_listing_app/app/widgets/sell_submission_status_banner.dart';
import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final AppLocalizationsEn _en = AppLocalizationsEn();

Widget _bannerApp() {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const SellSubmissionStatusBanner(
      child: Scaffold(body: SizedBox()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Defensive: this is a real process-wide singleton
    // (`PendingSellSubmissionService.instance`), so a value left over from
    // another test in this same suite file must never leak in.
    PendingSellSubmissionService.instance.statusNotifier.value = null;
  });

  tearDown(() {
    PendingSellSubmissionService.instance.statusNotifier.value = null;
  });

  group('Phase 3B server-transcode sub-phase labels are actually rendered', () {
    testWidgets(
      'uploadingVideoSource renders the exact sellVideoUploadingSource '
      'localized text',
      (tester) async {
        await tester.pumpWidget(_bannerApp());
        await tester.pump();

        PendingSellSubmissionService.instance.statusNotifier.value =
            const SellSubmissionUiStatus(
          draftId: 'd1',
          phase: SellSubmissionPhase.uploadingVideoSource,
          completedMediaCount: 0,
          totalMediaCount: 1,
        );
        await tester.pump();

        expect(find.text(_en.sellVideoUploadingSource), findsOneWidget);
        // Never falls back to the generic count-based message while a
        // server-transcode sub-phase is active.
        expect(
          find.text(_en.sellSubmissionUploadingProgress(0, 1)),
          findsNothing,
        );
      },
    );

    testWidgets(
      'processingVideoOnServer renders the exact sellVideoProcessingOnServer '
      'localized text',
      (tester) async {
        await tester.pumpWidget(_bannerApp());
        await tester.pump();

        PendingSellSubmissionService.instance.statusNotifier.value =
            const SellSubmissionUiStatus(
          draftId: 'd1',
          phase: SellSubmissionPhase.processingVideoOnServer,
          completedMediaCount: 0,
          totalMediaCount: 1,
        );
        await tester.pump();

        expect(find.text(_en.sellVideoProcessingOnServer), findsOneWidget);
      },
    );

    testWidgets(
      'finishingVideoUpload renders the exact sellVideoFinishing localized '
      'text',
      (tester) async {
        await tester.pumpWidget(_bannerApp());
        await tester.pump();

        PendingSellSubmissionService.instance.statusNotifier.value =
            const SellSubmissionUiStatus(
          draftId: 'd1',
          phase: SellSubmissionPhase.finishingVideoUpload,
          completedMediaCount: 0,
          totalMediaCount: 1,
        );
        await tester.pump();

        expect(find.text(_en.sellVideoFinishing), findsOneWidget);
      },
    );

    testWidgets(
      'a single banner instance transitions through all three '
      'server-transcode sub-phase labels in order, each replacing the '
      'last -- exactly the sequence `SellServerTranscodeVideoRunner` '
      'reports via `onPhase` for one video',
      (tester) async {
        await tester.pumpWidget(_bannerApp());
        await tester.pump();

        final notifier = PendingSellSubmissionService.instance.statusNotifier;

        notifier.value = const SellSubmissionUiStatus(
          draftId: 'd1',
          phase: SellSubmissionPhase.uploadingVideoSource,
          completedMediaCount: 0,
          totalMediaCount: 1,
        );
        await tester.pump();
        expect(find.text(_en.sellVideoUploadingSource), findsOneWidget);

        notifier.value = const SellSubmissionUiStatus(
          draftId: 'd1',
          phase: SellSubmissionPhase.processingVideoOnServer,
          completedMediaCount: 0,
          totalMediaCount: 1,
        );
        await tester.pump();
        expect(find.text(_en.sellVideoUploadingSource), findsNothing);
        expect(find.text(_en.sellVideoProcessingOnServer), findsOneWidget);

        notifier.value = const SellSubmissionUiStatus(
          draftId: 'd1',
          phase: SellSubmissionPhase.finishingVideoUpload,
          completedMediaCount: 0,
          totalMediaCount: 1,
        );
        await tester.pump();
        expect(find.text(_en.sellVideoProcessingOnServer), findsNothing);
        expect(find.text(_en.sellVideoFinishing), findsOneWidget);

        notifier.value = const SellSubmissionUiStatus(
          draftId: 'd1',
          phase: SellSubmissionPhase.done,
          completedMediaCount: 1,
          totalMediaCount: 1,
        );
        await tester.pump();
        expect(
          find.text(_en.sellVideoFinishing),
          findsNothing,
          reason: 'the banner hides entirely once the phase is done',
        );
      },
    );
  });

  group('pre-existing phase labels are unaffected by the new sub-phases', () {
    testWidgets(
      'the coarse uploadingVideos phase (normal <=100MB video path) still '
      'renders the pre-existing generic "X of Y media uploaded" message, '
      'never one of the new server-transcode strings',
      (tester) async {
        await tester.pumpWidget(_bannerApp());
        await tester.pump();

        PendingSellSubmissionService.instance.statusNotifier.value =
            const SellSubmissionUiStatus(
          draftId: 'd1',
          phase: SellSubmissionPhase.uploadingVideos,
          completedMediaCount: 1,
          totalMediaCount: 3,
        );
        await tester.pump();

        expect(
          find.text(_en.sellSubmissionUploadingProgress(1, 3)),
          findsOneWidget,
        );
        expect(find.text(_en.sellVideoUploadingSource), findsNothing);
        expect(find.text(_en.sellVideoProcessingOnServer), findsNothing);
        expect(find.text(_en.sellVideoFinishing), findsNothing);
      },
    );

    testWidgets(
      'a null status (nothing in flight) renders no banner at all -- just '
      'the child',
      (tester) async {
        await tester.pumpWidget(_bannerApp());
        await tester.pump();

        expect(find.text(_en.sellVideoUploadingSource), findsNothing);
        expect(find.text(_en.sellVideoProcessingOnServer), findsNothing);
        expect(find.text(_en.sellVideoFinishing), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });
}
