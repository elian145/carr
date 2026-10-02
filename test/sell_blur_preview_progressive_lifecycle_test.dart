// Async preview-lifecycle fix (real-device evidence: "the Blurred section
// ALSO visually shows originals, even after selecting Blurred, even though
// the backend confirms plate_blur_applied=True for some photos"). The root
// cause (see `mergeBlurResultsIntoOriginals` in `sell_plate_blur_merge.dart`)
// was a stale local `preview_source` surviving into a successfully-blurred
// entry, making `_blurPreviewGrid` keep rendering the local original
// forever even once `source` correctly pointed at the new blurred URL.
//
// `sell_blur_preview_truthful_state_test.dart` proves the FINAL, fully-
// settled render is correct (original vs. blurred URL, and the truthful
// "not blurred" badge) but never exercises the actual ASYNC, per-photo
// PENDING -> RESOLVED transition live on screen -- every fixture there is
// a fully-resolved snapshot. `sell_blur_choice_ui_and_race_test.dart`
// exercises that same async job-polling machinery but only ever asserts on
// `carData`, never on what is actually painted on the choice screen.
//
// This file closes that gap: using the same deterministic, zero-real-Timer
// `_ControlledBlurJobClient` technique as
// `sell_blur_choice_ui_and_race_test.dart`, it drives `_blurMediaList`'s
// REAL per-job progressive-reveal code path (`sell_car_page_plate_blur.dart`)
// and asserts, at each step, on the REAL widgets actually mounted in the
// `SellStepBlurChoicePage` tree (rendered `CachedNetworkImage.imageUrl`s,
// visible loading/failure/not-applied text) -- not just `carData` state.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

/// `CachedNetworkImage` (rendered by `_listingNetworkImage` for every
/// genuinely-resolved blurred tile this file checks) uses
/// `flutter_cache_manager`, which needs a real `getTemporaryDirectory()` to
/// disk-cache the downloaded bytes. This file's `settle()` uses
/// `tester.runAsync()` (to drain the controlled job's real microtask
/// chain), which gives that disk-cache logic a genuine chance to actually
/// run (unlike a plain `pump()`-only widget test) -- without a mocked
/// `PathProviderPlatform`, that throws an uncaught
/// `MissingPluginException` the moment a tile's `CachedNetworkImage`
/// mounts. Same fix as `sell_blur_choice_ui_and_race_test.dart`'s own
/// `_FakeDocsPathProvider`.
class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;

  @override
  Future<String?> getTemporaryPath() async => _path;

  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

/// Same technique as `_ControlledBlurJobClient`
/// (`sell_blur_choice_ui_and_race_test.dart`): every `/api/jobs/<id>` poll
/// is backed by a deliberately-uncompleted [Completer], held open until the
/// test explicitly resolves it via [completeJobSuccess] -- letting a test
/// hold the REAL `_blurMediaList`/`SellImageJobPolling` production code
/// "mid-flight" for as long as it wants, with zero real Timers.
class _ControlledJobClient {
  final Map<String, Completer<http.Response>> _pending = {};
  final List<String> enqueuedJobIds = [];
  int _seq = 0;

  int _countMultipartParts(http.Request request, String fieldName) {
    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.contains('multipart/form-data')) return 0;
    final bodyStr = latin1.decode(request.bodyBytes);
    return RegExp('name="$fieldName"').allMatches(bodyStr).length;
  }

  late final MockClient client = MockClient((request) async {
    final method = request.method.toUpperCase();
    final path = request.url.path;

    if (method == 'POST' && path.endsWith('/process-car-images')) {
      final fileCount = _countMultipartParts(request, 'images');
      final ids = <String>[];
      for (var i = 0; i < fileCount; i++) {
        final jobId = 'prog-job-$_seq-$i';
        _pending[jobId] = Completer<http.Response>();
        enqueuedJobIds.add(jobId);
        ids.add(jobId);
      }
      _seq++;
      return http.Response(
        json.encode({'job_ids': ids}),
        202,
        headers: {'content-type': 'application/json'},
      );
    }

    final jobMatch = RegExp(r'^/api/jobs/(.+)$').firstMatch(path);
    if (method == 'GET' && jobMatch != null) {
      final jobId = Uri.decodeComponent(jobMatch.group(1)!);
      final completer = _pending[jobId];
      if (completer != null) return completer.future;
      return http.Response(
        json.encode({'state': 'PENDING'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    return http.Response(
      '{}',
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  /// Resolves [jobId] with a terminal SUCCESS result. [plateBlurApplied]
  /// defaults to `true` (a genuine blurred output); pass `false` to
  /// simulate "job succeeded, no plate detected".
  void completeJobSuccess(
    String jobId,
    String relPath, {
    bool plateBlurApplied = true,
  }) {
    final completer = _pending[jobId];
    if (completer == null || completer.isCompleted) return;
    completer.complete(
      http.Response(
        json.encode({
          'state': 'SUCCESS',
          'result': {
            'rel_path': relPath,
            '_trace_plate_blur_applied': plateBlurApplied,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  /// Resolves [jobId] with a terminal FAILURE -- a genuine job failure,
  /// distinct from "succeeded, no plate found".
  void completeJobFailure(String jobId) {
    final completer = _pending[jobId];
    if (completer == null || completer.isCompleted) return;
    completer.complete(
      http.Response(
        json.encode({'state': 'FAILURE'}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
  }
}

/// Every `imageUrl` currently rendered via `CachedNetworkImage` anywhere in
/// the tree, in tree order -- i.e. exactly what a real device would paint
/// for any REMOTE (non-local) tile. Local-file tiles (pending/original
/// photos still backed by an on-disk path) render via a different, private
/// widget and never show up here -- those are instead asserted on via the
/// visible "Generating blurred preview…"/failure/not-applied badge text.
List<String> _renderedNetworkImageUrls(WidgetTester tester) {
  return tester
      .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
      .map((w) => w.imageUrl)
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  late Directory tempDir;
  late String originalAPath;
  late String originalBPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sell_blur_progressive_');
    originalAPath = p.join(tempDir.path, 'originalA.jpg');
    originalBPath = p.join(tempDir.path, 'originalB.jpg');
    File(originalAPath).writeAsStringSync('ORIGINAL_A');
    File(originalBPath).writeAsStringSync('ORIGINAL_B');
    PathProviderPlatform.instance = _FakeDocsPathProvider(tempDir.path);

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
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> bootSellWizard(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Map<String, dynamic> baseFields() => {
        ...sellCarDataThroughStep3(),
        'sell_wizard_v2': true,
      };

  /// Lands on the plate-blur-choice step and kicks off the REAL
  /// `startBackgroundPlateBlur()` against a fresh [_ControlledJobClient]
  /// -- same jump-navigation + "call it directly once mounted" technique
  /// as `sell_blur_choice_ui_and_race_test.dart` (see that file's own
  /// extensive comment for why a placeholder `blurred_images` + explicit
  /// `invalidatePlateBlurJob` + direct call is used instead of relying on
  /// `didChangeDependencies`'s auto-start).
  Future<_ControlledJobClient> landAndStartBlur(
    WidgetTester tester, {
    required Map<String, dynamic> extraCarData,
  }) async {
    await bootSellWizard(tester);
    final controlled = _ControlledJobClient();
    ApiService.testHttpClient = controlled.client;

    await openSellDraftStep(
      tester,
      step: 4,
      carData: {
        ...baseFields(),
        'blurred_images': [
          {'source': 'placeholder_blurred.jpg'},
        ],
        ...extraCarData,
      },
    );
    final dynamic state = tester.state(find.byType(SellCarPage));
    state.invalidatePlateBlurJob(clearBlurred: true);
    // Wait for the OBSERVABLE state, not a fixed wall-clock guess: the real
    // `startBackgroundPlateBlur()` reads every local file off disk
    // (`http.MultipartFile.fromPath`), POSTs, and only THEN publishes the
    // `blur_pending` skeleton. A fixed 100ms sleep here was only ~2.5x the
    // time that takes on a fast dev machine (~40ms) and failed on a slower /
    // loaded CI runner (cold first test in the file) with
    // `enqueuedJobIds` still empty. Poll (bounded) until every job is
    // enqueued AND every expected tile carries its `blur_pending` skeleton.
    final expectedJobs =
        (extraCarData['original_images'] as List?)?.length ?? 0;
    await tester.runAsync(() async {
      unawaited(state.startBackgroundPlateBlur() as Future<void>);
      bool skeletonPublished() {
        if (controlled.enqueuedJobIds.length != expectedJobs) return false;
        final blurred = (state.carData as Map)['blurred_images'];
        return blurred is List &&
            blurred.length == expectedJobs &&
            blurred.every((e) => e is Map && e['blur_pending'] == true);
      }

      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!skeletonPublished()) {
        if (DateTime.now().isAfter(deadline)) {
          throw TestFailure(
            'plate-blur pending skeleton never published: '
            'enqueued=${controlled.enqueuedJobIds.length}/$expectedJobs, '
            'blurred_images=${(state.carData as Map)['blurred_images']}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
    return controlled;
  }

  /// See `settleControlledJobs` in `sell_blur_choice_ui_and_race_test.dart`
  /// for why this needs several real-event-loop `runAsync` rounds, not
  /// just one `pump()`: each resolved job's continuation chain (including
  /// the progressive `onProgress` `setState` this file is specifically
  /// testing) is pinned to the real zone it was issued from.
  ///
  /// [until], when supplied, makes the wait state-driven instead of a fixed
  /// number of rounds: keeps running rounds (bounded by a generous real-time
  /// deadline, never a short guess) until the expected observable state is
  /// reached, then runs a few extra rounds to flush trailing timers.
  Future<void> settle(
    WidgetTester tester, {
    bool Function()? until,
  }) async {
    var extraRounds = 12;
    if (until != null) {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      var guard = 0;
      while (!until()) {
        if (DateTime.now().isAfter(deadline) || ++guard > 2000) {
          throw TestFailure('settle(): expected state not reached in time');
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 15));
      }
      // Keep the full trailing flush (`extraRounds` stays 12): the
      // cache-manager cleanup `Timer` described below is not observable
      // from the widget tree, so it can only be flushed by the same
      // real-async rounds as before.
    }
    for (var round = 0; round < extraRounds; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      // Once a genuinely-resolved blurred tile mounts a real
      // `CachedNetworkImage`, `flutter_cache_manager` schedules its own
      // ~10s cache-cleanup `Timer` (a FakeAsync-tracked one -- its own
      // continuation resumes during a plain `pump()`, not inside the
      // `runAsync` round above) the first time ITS OWN on-disk cache
      // store opens -- a NEW, independent one for every DIFFERENT tile
      // that switches from local to network rendering, each on its own
      // real-async schedule. Left unflushed, any such pending Timer trips
      // `AutomatedTestWidgetsFlutterBinding`'s `!timersPending` teardown
      // invariant -- entirely unrelated to this file's actual assertions
      // (which only ever check widget CONFIG, e.g.
      // `CachedNetworkImage.imageUrl`, never real decoded image bytes).
      // Advancing the fake clock past that delay on EVERY round (not just
      // once at the end) catches one no matter which round it was
      // scheduled on.
      await tester.pump(const Duration(seconds: 15));
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('Section 6: progressive per-photo preview lifecycle (real widget)', () {
    testWidgets(
      'A+B+G: initial pending state shows original + loading on EVERY '
      'tile; each job then updates its OWN tile independently as it '
      'resolves (never the other tile), and the final blurred tile '
      'renders the DISTINCT processed URL via CachedNetworkImage (new '
      'source, new key) -- never the original',
      (tester) async {
        final controlled = await landAndStartBlur(
          tester,
          extraCarData: {
            'original_images': [
              {'source': originalAPath},
              {'source': originalBPath},
            ],
          },
        );
        expect(controlled.enqueuedJobIds, hasLength(2));

        await tester.tap(find.text('Yes, use blurred photos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Initial state: both jobs still pending -- both tiles must show
        // the "Generating blurred preview…" overlay, and NEITHER tile has
        // rendered a network (blurred) image yet (the underlying source is
        // still each original's local file).
        expect(
          find.text('Generating blurred preview…'),
          findsNWidgets(2),
          reason: 'both tiles must show the live loading overlay while '
              'both jobs are still pending',
        );
        expect(
          _renderedNetworkImageUrls(tester),
          isEmpty,
          reason: 'no genuine blurred (network) image exists yet -- both '
              'tiles are still painting their original, local file',
        );

        // Resolve ONLY job A.
        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[0],
          'uploads/blurred_a_progressive.jpg',
        );
        await settle(
          tester,
          until: () => _renderedNetworkImageUrls(tester)
              .any((u) => u.contains('blurred_a_progressive.jpg')),
        );

        var rendered = _renderedNetworkImageUrls(tester);
        expect(
          rendered.any((u) => u.contains('blurred_a_progressive.jpg')),
          isTrue,
          reason: 'tile A must now render its own distinct processed URL',
        );
        expect(
          find.text('Generating blurred preview…'),
          findsOneWidget,
          reason: 'tile B must STILL show the loading overlay -- job A '
              'resolving must not affect tile B (each tile updates '
              'independently)',
        );

        // Now resolve job B too.
        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[1],
          'uploads/blurred_b_progressive.jpg',
        );
        await settle(
          tester,
          until: () => _renderedNetworkImageUrls(tester)
              .any((u) => u.contains('blurred_b_progressive.jpg')),
        );

        rendered = _renderedNetworkImageUrls(tester);
        expect(
          rendered.any((u) => u.contains('blurred_a_progressive.jpg')),
          isTrue,
        );
        expect(
          rendered.any((u) => u.contains('blurred_b_progressive.jpg')),
          isTrue,
          reason: 'tile B must now ALSO render its own distinct processed '
              'URL once its own job resolves',
        );
        expect(
          find.text('Generating blurred preview…'),
          findsNothing,
          reason: 'no tile should still show the loading overlay once '
              'every job has resolved',
        );
      },
    );

    testWidgets(
      'C: a job that succeeds but reports plate_blur_applied=false keeps '
      'the original visually-unblurred bytes AND shows the truthful '
      '"not blurred" badge -- never silently presented as a genuine '
      'blurred result',
      (tester) async {
        final controlled = await landAndStartBlur(
          tester,
          extraCarData: {
            'original_images': [
              {'source': originalAPath},
            ],
          },
        );
        expect(controlled.enqueuedJobIds, hasLength(1));

        await tester.tap(find.text('Yes, use blurred photos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[0],
          'uploads/passthrough_no_plate.jpg',
          plateBlurApplied: false,
        );
        await settle(tester);

        expect(
          find.text('Not blurred — no plate detected'),
          findsOneWidget,
          reason: 'plate_blur_applied=false must render the truthful '
              '"not blurred" badge',
        );
        expect(
          find.text('Generating blurred preview…'),
          findsNothing,
          reason: 'the job has reached a terminal state -- the loading '
              'overlay must be gone',
        );
      },
    );

    testWidgets(
      'a job that genuinely FAILS (network/timeout) keeps the original '
      'and shows a distinct, truthful failure/retry badge -- never the '
      '"not blurred, no plate detected" badge (which implies success)',
      (tester) async {
        final controlled = await landAndStartBlur(
          tester,
          extraCarData: {
            'original_images': [
              {'source': originalAPath},
            ],
          },
        );
        expect(controlled.enqueuedJobIds, hasLength(1));

        await tester.tap(find.text('Yes, use blurred photos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        controlled.completeJobFailure(controlled.enqueuedJobIds[0]);
        await settle(tester);

        expect(
          find.text('Preview failed — tap "Blur plates now" below to retry'),
          findsOneWidget,
          reason: 'a genuine job failure must render a distinct, truthful '
              'failure badge',
        );
        expect(find.text('Not blurred — no plate detected'), findsNothing);
        expect(find.text('Generating blurred preview…'), findsNothing);
      },
    );

    testWidgets(
      'D: user selects "Blurred" BEFORE the job resolves -- the tile '
      'still updates correctly, live, once the result arrives',
      (tester) async {
        final controlled = await landAndStartBlur(
          tester,
          extraCarData: {
            'original_images': [
              {'source': originalAPath},
            ],
          },
        );
        expect(controlled.enqueuedJobIds, hasLength(1));

        // Choice made strictly BEFORE any job result exists.
        await tester.tap(find.text('Yes, use blurred photos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Generating blurred preview…'), findsOneWidget);
        expect(_renderedNetworkImageUrls(tester), isEmpty);

        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[0],
          'uploads/blurred_after_early_choice.jpg',
        );
        await settle(tester);

        expect(
          _renderedNetworkImageUrls(tester)
              .any((u) => u.contains('blurred_after_early_choice.jpg')),
          isTrue,
          reason: 'the tile must update live to the real blurred URL once '
              'the job resolves, even though the choice was made while it '
              'was still pending',
        );
        expect(find.text('Generating blurred preview…'), findsNothing);
      },
    );

    testWidgets(
      'E: rapidly switching Unblurred -> Blurred -> Unblurred does not '
      'lose the in-flight/eventual blur result',
      (tester) async {
        final controlled = await landAndStartBlur(
          tester,
          extraCarData: {
            'original_images': [
              {'source': originalAPath},
            ],
          },
        );
        expect(controlled.enqueuedJobIds, hasLength(1));

        await tester.tap(find.text('No, keep original photos'));
        await tester.pump();
        await tester.tap(find.text('Yes, use blurred photos'));
        await tester.pump();
        await tester.tap(find.text('No, keep original photos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[0],
          'uploads/blurred_after_rapid_switch.jpg',
        );
        await settle(tester);

        // Currently on "keep original" -- the blurred grid isn't even
        // shown, but the underlying result must not have been lost.
        final carData =
            Map<String, dynamic>.from(
          (tester.state(find.byType(SellCarPage)) as dynamic).carData as Map,
        );
        final blurredList = carData['blurred_images'] as List;
        expect(
          blurredList.map((e) => (e as Map)['source']).toList(),
          ['uploads/blurred_after_rapid_switch.jpg'],
          reason: 'rapidly toggling the choice before/during/after the job '
              'resolves must not discard the eventual real result',
        );

        // Switching back to "Blurred" now must show the real result --
        // not a stale/blank/pending state.
        await tester.tap(find.text('Yes, use blurred photos'));
        await settle(tester);
        expect(
          _renderedNetworkImageUrls(tester)
              .any((u) => u.contains('blurred_after_rapid_switch.jpg')),
          isTrue,
        );
        expect(find.text('Generating blurred preview…'), findsNothing);
      },
    );

    testWidgets(
      'F: a widget rebuild/step revisit after the blur result has already '
      'arrived keeps rendering the resolved blurred image -- it is never '
      'reset back to the original',
      (tester) async {
        final controlled = await landAndStartBlur(
          tester,
          extraCarData: {
            'price': '10000',
            'original_images': [
              {'source': originalAPath},
            ],
          },
        );
        expect(controlled.enqueuedJobIds, hasLength(1));

        await tester.tap(find.text('Yes, use blurred photos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[0],
          'uploads/blurred_survives_rebuild.jpg',
        );
        await settle(tester);
        expect(
          _renderedNetworkImageUrls(tester)
              .any((u) => u.contains('blurred_survives_rebuild.jpg')),
          isTrue,
        );

        // Re-open the wizard fresh on this same step, with the NOW-
        // RESOLVED `blurred_images` already in the draft snapshot -- a
        // brand new `SellCarPage`/`SellStepBlurChoicePage` route push
        // (`openSellDraftStep` calls `Navigator.pushNamed`), forcing a
        // genuine full dispose + fresh `initState`/`build`, i.e. a real
        // widget rebuild/step-revisit, not just an in-place `setState` on
        // the same long-lived State object. This is a more direct/
        // reliable way to exercise "revisit" than tapping through the
        // wizard's "Previous"/"Next Step" buttons, which would otherwise
        // also require satisfying the entirely unrelated "Pricing &
        // Contact" step's own required-field/phone-verification
        // validation just to get back here.
        final resolvedCarData = Map<String, dynamic>.from(
          (tester.state(find.byType(SellCarPage)) as dynamic).carData as Map,
        );
        await openSellDraftStep(tester, step: 4, carData: resolvedCarData);
        // See `settle()`'s own comment: a freshly-mounted
        // `CachedNetworkImage` schedules a real (FakeAsync-tracked)
        // ~10s cache-cleanup `Timer` the first time its disk cache store
        // opens -- flush it before this test ends.
        await tester.pump(const Duration(seconds: 15));

        expect(
          _renderedNetworkImageUrls(tester)
              .any((u) => u.contains('blurred_survives_rebuild.jpg')),
          isTrue,
          reason: 'the already-resolved blurred result must still be '
              'rendered after navigating away and back -- never silently '
              'reset to the original',
        );
        expect(find.text('Generating blurred preview…'), findsNothing);
      },
    );
  });
}
