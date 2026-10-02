// Follow-up to the byte-level service-layer proof in
// `test/sell_new_listing_unblurred_upload_bytes_test.dart`. That file
// proved: IF `carData['images']` correctly equals `original_images` at
// submit time, the uploaded bytes ARE the originals. It deliberately did
// NOT touch the actual UI (the choice tiles' onTap wiring) or the
// asynchronous background-blur-completion race -- this file audits both,
// with REAL widget taps against the production `SellStepBlurChoicePage`
// (not a reimplementation, not a helper-level inference).
//
// Section A: taps the actual "Yes, use blurred photos" / "No, keep
// original photos" tiles and asserts BOTH the resulting `carData` state
// AND the visible selected/unselected radio icons + header summary --
// ruling out a UI-inverted-from-state bug.
//
// Section B: the highest-priority remaining hypothesis -- the user taps
// UNBLURRED (or BLURRED) WHILE the background plate-blur Celery job
// (started automatically when landing on this page, per
// `sell_step_blur_choice_logic.dart`'s `didChangeDependencies`) is still
// running, then the job's completion handler
// (`startBackgroundPlateBlur` in `sell_car_page_plate_blur.dart`) fires
// AFTER the choice was made. Timing is controlled deterministically (no
// real delay, no flakiness, no dependence on `SellImageJobPolling`'s real
// 1.5s poll interval) via `_ControlledBlurJobClient`: a `MockClient` whose
// `GET /api/jobs/<id>` responses are backed by test-held `Completer`s that
// are deliberately left un-answered until the test calls
// `completeJobSuccess` -- letting a test hold the REAL
// `startBackgroundPlateBlur`/`_blurMediaList`/`SellImageJobPolling`
// production code "mid-flight" for as long as it wants, with zero real
// Timers, then release it on demand.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

/// Controls the network side of a single `startBackgroundPlateBlur()` run
/// with zero real time and zero Timers -- every `GET /api/jobs/<id>` poll
/// this test cares about is deliberately left un-answered (a bare,
/// uncompleted [Completer]) until the test calls [completeJobSuccess], so
/// the job can be held "still running" across a widget tap for as long as
/// the test wants, then resolved on demand.
///
/// This is what makes the race genuinely deterministic and avoids
/// `tester.runAsync()`/real wall-clock waits altogether:
/// `SellImageJobPolling`'s very first poll attempt has NO delay before it
/// (see `sell_image_job_polling.dart`), so as long as a job's completer is
/// held open across the tap, the polling loop never even reaches its
/// `Future.delayed(pollInterval)` retry branch -- it is simply awaiting an
/// ordinary (uncompleted) Dart `Future`, which plain `tester.pump()` calls
/// correctly interleave with widget interaction (no real Timer is ever
/// created, so there is nothing for a fake clock to fail to advance).
class _ControlledBlurJobClient {
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
        final jobId = 'ctrl-job-$_seq-$i';
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

  /// Resolves [jobId]'s currently-pending poll with a terminal SUCCESS
  /// response carrying [relPath] -- the poll the production code is
  /// already awaiting sees this result the moment the test next drives a
  /// `pump()`.
  void completeJobSuccess(String jobId, String relPath) {
    final completer = _pending[jobId];
    if (completer == null || completer.isCompleted) return;
    completer.complete(
      http.Response(
        json.encode({
          'state': 'SUCCESS',
          'result': {'rel_path': relPath},
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
  }
}

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

/// Reads `carData` off the currently-mounted `SellCarPage`'s (private)
/// State. `carData` is a public-named member -- Dart privacy is per-
/// library, not per-class, and hides only underscore-prefixed names from
/// other libraries, so a dynamic-dispatch read of this public field from
/// outside `sell_flow.dart` is legitimate (not a hack around privacy);
/// it is simply not expressible with a static type since the declaring
/// class itself is private.
Map<String, dynamic> currentCarData(WidgetTester tester) {
  final state = tester.state(find.byType(SellCarPage));
  return Map<String, dynamic>.from((state as dynamic).carData as Map);
}

List<String> _sourcesOf(dynamic list) {
  if (list is! List) return const [];
  return list
      .map((e) => e is Map ? (e['source'] ?? '').toString() : e.toString())
      .toList();
}

/// True when [blurredRaw] represents "no GENUINE blur result exists yet" --
/// either legacy-empty (the original, pre-progressive-skeleton contract:
/// `blurred_images` stayed unset until the whole batch finished) or every
/// entry is still a `blur_pending` placeholder (the async preview-lifecycle
/// fix's `pendingBlurSkeleton`, `sell_plate_blur_merge.dart`, published the
/// INSTANT the background job starts so the choice screen can render a
/// live per-tile "Generating blurred preview…" state -- see
/// `sell_car_page_plate_blur.dart`). Either way, nothing in [blurredRaw] is
/// an actual processed/blurred result yet.
bool _noGenuineBlurResultYet(dynamic blurredRaw) {
  if (blurredRaw == null) return true;
  if (blurredRaw is! List) return true;
  if (blurredRaw.isEmpty) return true;
  return blurredRaw.every((e) => e is Map && e['blur_pending'] == true);
}

/// Finds the radio icon (checked/unchecked) inside the same choice-tile
/// Row as [title] -- proves the VISIBLE selected state, not just carData.
bool _tileShowsChecked(String title) {
  final row = find.ancestor(
    of: find.text(title),
    matching: find.byType(Row),
  ).first;
  final checked = find.descendant(
    of: row,
    matching: find.byIcon(Icons.radio_button_checked),
  );
  final unchecked = find.descendant(
    of: row,
    matching: find.byIcon(Icons.radio_button_off),
  );
  expect(
    checked.evaluate().length + unchecked.evaluate().length,
    1,
    reason: 'exactly one radio icon must exist for the "$title" tile',
  );
  return checked.evaluate().isNotEmpty;
}

/// Extracts the raw byte content of every multipart part named
/// [fieldName] -- same technique as
/// `sell_new_listing_unblurred_upload_bytes_test.dart`.
List<String> _multipartFieldContents(http.Request request, String fieldName) {
  final contentType = request.headers['content-type'] ?? '';
  if (!contentType.contains('multipart/form-data')) return const [];
  final boundaryMatch = RegExp(r'boundary=([^\s;]+)').firstMatch(contentType);
  if (boundaryMatch == null) return const [];
  final boundary = boundaryMatch.group(1)!.replaceAll('"', '');
  final bodyText = latin1.decode(request.bodyBytes);
  final out = <String>[];
  for (final rawPart in bodyText.split('--$boundary')) {
    if (!rawPart.contains('name="$fieldName"')) continue;
    final headerEnd = rawPart.indexOf('\r\n\r\n');
    if (headerEnd == -1) continue;
    var content = rawPart.substring(headerEnd + 4);
    if (content.endsWith('\r\n')) content = content.substring(0, content.length - 2);
    out.add(content);
  }
  return out;
}

/// Submits [carData] through the REAL `PendingSellSubmissionService`
/// (exactly what `_submitListing` in `sell_step5_logic.dart` calls) and
/// returns the raw bytes of every `images` multipart part actually sent,
/// in order. Uses its own isolated `MockClient`/docs dir -- swapped in
/// only for this leg, after all widget interaction is done.
Future<List<String>> _submitAndCaptureImageBytes({
  required Map<String, dynamic> carData,
  required String draftId,
}) async {
  final tempDir = Directory.systemTemp.createTempSync('sell_blur_race_submit_');
  final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync(recursive: true);
  PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);
  setRuntimeApiBaseOverride('http://127.0.0.1:1');
  debugSellSubmissionRetryBackoffOverride = (_) => Duration.zero;

  final fileContentsCaptured = <String>[];
  var carIdCounter = 0;
  var jobIdCounter = 0;
  final jobRelPathByJobId = <String, String>{};
  final carsById = <String, Map<String, dynamic>>{};

  ApiService.testHttpClient = MockClient((request) async {
    final method = request.method.toUpperCase();
    final path = request.url.path;

    if (method == 'POST' && path == '/api/cars') {
      carIdCounter++;
      final id = 'car_race_$carIdCounter';
      carsById[id] = {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]};
      return http.Response(
        json.encode({'car': carsById[id]}),
        201,
        headers: {'content-type': 'application/json'},
      );
    }

    final enqueueMatch = RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
    if (method == 'POST' && enqueueMatch != null) {
      final parts = _multipartFieldContents(request, 'images');
      fileContentsCaptured.addAll(parts);
      final jobIds = <String>[];
      for (final content in parts) {
        jobIdCounter++;
        final jobId = 'job_race_$jobIdCounter';
        jobRelPathByJobId[jobId] = 'uploads/car_photos/processed_$content.jpg';
        jobIds.add(jobId);
      }
      return http.Response(
        json.encode({'job_ids': jobIds}),
        202,
        headers: {'content-type': 'application/json'},
      );
    }

    if (method == 'GET' && path.startsWith('/api/jobs/')) {
      final jobId = path.substring('/api/jobs/'.length);
      final relPath = jobRelPathByJobId[jobId] ?? 'uploads/car_photos/$jobId.jpg';
      return http.Response(
        json.encode({'task_id': jobId, 'state': 'SUCCESS', 'result': {'rel_path': relPath}}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    final attachMatch = RegExp(r'^/api/cars/([^/]+)/images/attach$').firstMatch(path);
    if (method == 'POST' && attachMatch != null) {
      final id = attachMatch.group(1)!;
      final decoded = json.decode(request.body) as Map;
      final paths = List<String>.from(decoded['paths'] as List);
      final car = carsById.putIfAbsent(
        id,
        () => {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]},
      );
      for (final path in paths) {
        (car['images'] as List).add({'id': jobIdCounter, 'image_url': path});
      }
      return http.Response(
        json.encode({'images': (car['images'] as List)}),
        201,
        headers: {'content-type': 'application/json'},
      );
    }

    final mediaSummaryMatch = RegExp(r'^/api/cars/([^/]+)/media-summary$').firstMatch(path);
    if (method == 'GET' && mediaSummaryMatch != null) {
      return http.Response(
        json.encode({'media_status': 'ready', 'items': <dynamic>[], 'phase_a_complete': true}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    final getMatch = RegExp(r'^/api/cars/([^/]+)$').firstMatch(path);
    if (method == 'GET' && getMatch != null) {
      final id = getMatch.group(1)!;
      final car = carsById[id] ?? {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]};
      return http.Response(json.encode({'car': car}), 200, headers: {'content-type': 'application/json'});
    }

    return http.Response('{"cars": []}', 200, headers: {'content-type': 'application/json'});
  });

  await ApiService.setTokens(accessToken: 'test_access_token', refreshToken: 'test_refresh_token');

  await PendingSellSubmissionService.instance.submitFast(
    draftId: draftId,
    carData: Map<String, dynamic>.from(carData),
  );

  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (await SellSubmissionStatePrefs.load(draftId) != null) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for submission $draftId to finish');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  debugSellSubmissionRetryBackoffOverride = null;
  ApiService.testHttpClient = null;
  try {
    tempDir.deleteSync(recursive: true);
  } catch (_) {}
  return fileContentsCaptured;
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
    tempDir = await Directory.systemTemp.createTemp('sell_blur_race_');
    originalAPath = p.join(tempDir.path, 'originalA.jpg');
    originalBPath = p.join(tempDir.path, 'originalB.jpg');
    File(originalAPath).writeAsStringSync('ORIGINAL_A');
    File(originalBPath).writeAsStringSync('ORIGINAL_B');

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

    // `DeepLinkService.init()` (called once per app boot, e.g. from
    // `bootSellWizard`'s `legacy.MyApp()`) calls `AppLinks.getInitialLink()`
    // with no error handling on its `.then()` -- with no platform-channel
    // mock, that rejects with a `MissingPluginException` that surfaces as
    // an uncaught async error whenever the rejection happens to be
    // processed (this file's heavier use of `tester.runAsync()` for the
    // real blur-job network chain makes that surfacing more likely than
    // in a typical widget test). Unrelated to plate-blur choice logic --
    // mocked here purely so this pre-existing, unrelated gap in
    // `DeepLinkService` cannot flake these tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/messages'),
      (call) async => null,
    );
    // Same as above -- `AppLinks.uriLinkStream` opens an `EventChannel` on
    // this second channel; its `listen` call needs a mock too, or it
    // throws the same way.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (call) async => null,
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

  group('Section A: choice-tile widget wiring is not inverted (real taps)', () {
    testWidgets(
      'tapping "No, keep original photos" sets use_blurred_plates=false, '
      'carData[images] becomes original_images, and the visible radio + '
      'header summary agree with that state',
      (tester) async {
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 4,
          carData: {
            ...baseFields(),
            'original_images': [
              {'source': originalAPath},
              {'source': originalBPath},
            ],
            'blurred_images': [
              {'source': 'uploads/blurred_a.jpg'},
              {'source': 'uploads/blurred_b.jpg'},
            ],
            'images': [
              {'source': originalAPath},
              {'source': originalBPath},
            ],
            'images_processed': true,
          },
        );

        await tester.tap(find.text('No, keep original photos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final carData = currentCarData(tester);
        expect(carData['use_blurred_plates'], isFalse);
        expect(_sourcesOf(carData['images']), [originalAPath, originalBPath]);

        expect(_tileShowsChecked('No, keep original photos'), isTrue);
        expect(_tileShowsChecked('Yes, use blurred photos'), isFalse);
        expect(find.text('No, keep original'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping "Yes, use blurred photos" sets use_blurred_plates=true, '
      'carData[images] becomes blurred_images, and the visible radio + '
      'header summary agree with that state (opposite direction, proves '
      'the wiring is not simply always-false)',
      (tester) async {
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 4,
          carData: {
            ...baseFields(),
            'original_images': [
              {'source': originalAPath},
              {'source': originalBPath},
            ],
            'blurred_images': [
              {'source': 'uploads/blurred_a.jpg'},
              {'source': 'uploads/blurred_b.jpg'},
            ],
            'images': [
              {'source': originalAPath},
              {'source': originalBPath},
            ],
            'images_processed': true,
          },
        );

        await tester.tap(find.text('Yes, use blurred photos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final carData = currentCarData(tester);
        expect(carData['use_blurred_plates'], isTrue);
        expect(
          _sourcesOf(carData['images']),
          ['uploads/blurred_a.jpg', 'uploads/blurred_b.jpg'],
        );

        expect(_tileShowsChecked('Yes, use blurred photos'), isTrue);
        expect(_tileShowsChecked('No, keep original photos'), isFalse);
        expect(find.text('Yes, blur plates'), findsOneWidget);
      },
    );
  });

  group('Section B: async blur-completion race (real widget, controlled timing)', () {
    /// Lands on the plate-blur-choice step with a PLACEHOLDER
    /// `blurred_images` already present (so `hasBlurredPlatesReady` is
    /// true and `didChangeDependencies`'s auto-start is skipped on this
    /// page's very first build -- jumping straight to this step via a
    /// draft snapshot means that first build happens on the app's first
    /// frame, and calling the real `setState`-driven
    /// `startBackgroundPlateBlur` synchronously from
    /// `didChangeDependencies` at that exact moment trips Flutter's
    /// "setState called during build" guard -- a widget-test-harness
    /// timing artifact of jump-navigation, not the race this test is
    /// actually targeting). Once fully settled, the placeholder is
    /// discarded and the REAL, unmodified `startBackgroundPlateBlur()` is
    /// invoked directly on the (fully mounted, safe-to-setState) page
    /// state -- the exact same production method `didChangeDependencies`
    /// or the "Blur plates now" retry button would call, just triggered
    /// at a moment a real swipe-driven page transition would also be
    /// safe at.
    ///
    /// Installs a fresh [_ControlledBlurJobClient] as
    /// `ApiService.testHttpClient` so this specific `_blurMediaList` run's
    /// job polls are held open (deterministically, no real time) until
    /// the test explicitly resolves them.
    Future<_ControlledBlurJobClient> landOnChoiceStepAndStartBlur(
      WidgetTester tester, {
      required Map<String, dynamic> extraCarData,
    }) async {
      final controlled = _ControlledBlurJobClient();
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
      // Fire-and-forget: this is the exact same production method
      // `didChangeDependencies`/the "Blur plates now" retry button would
      // call. Its network calls resolve against [controlled], which
      // deliberately leaves every job's poll un-answered until the test
      // calls `completeJobSuccess`, so it stays genuinely mid-flight
      // across the upcoming tap with zero real Timers involved -- BUT the
      // enqueue step first reads the local photo files off disk via real
      // (non-fake) I/O (`http.MultipartFile.fromPath`, inside
      // `AiService.enqueueCarImagesAsync`), which cannot progress inside a
      // widget test's FakeAsync zone without `tester.runAsync()`. A short
      // real-time wait here is only for that one-time disk read + our
      // in-memory mock round-trip (both effectively instant); the instant
      // the code reaches its first job-status poll it blocks on an
      // intentionally-uncompleted `Completer` (see
      // `_ControlledBlurJobClient`) -- a plain Dart Future with no
      // Timer/real-IO involved, which is safe to leave pending outside of
      // `runAsync` for the rest of the test (no orphaned real Timer is
      // ever created).
      await tester.runAsync(() async {
        unawaited(state.startBackgroundPlateBlur() as Future<void>);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      return controlled;
    }

    /// After [_ControlledBlurJobClient.completeJobSuccess], the resolved
    /// job's continuation chain (`.timeout()`'s internal `.then()`,
    /// registered back when the GET request was first issued inside
    /// `landOnChoiceStepAndStartBlur`'s `runAsync` block) is pinned to
    /// THAT real zone -- it lands in the VM's real microtask queue, not
    /// FakeAsync's fake one, so plain `tester.pump()` calls alone (which
    /// only flush the fake queue) never drain it. A short real-time
    /// `runAsync` re-entry gives the real event loop a chance to actually
    /// run it before a normal `pump()` propagates the resulting `setState`
    /// into the widget tree. The chain is several hops deep (job A's poll
    /// resolves -> job B's poll is only THEN issued -> job B's poll
    /// resolves -> results are merged -> `setState`), and each hop can
    /// need its own real-event-loop turn, so this repeats several rounds
    /// rather than assuming one is enough.
    Future<void> settleControlledJobs(WidgetTester tester) async {
      // Async preview-lifecycle fix: `_blurMediaList` now publishes an
      // `onProgress` update (a `setState`-driven rebuild) after EACH
      // individual job resolves, not just once at the very end -- that is
      // strictly MORE real-event-loop hops than before for the exact same
      // reason this loop already exists (see the class doc above), so it
      // needs more rounds to fully settle a multi-job batch.
      for (var round = 0; round < 12; round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets(
      'Scenario A: user taps UNBLURRED WHILE the background blur job is '
      'still PENDING -- after the job later completes and writes '
      'blurred_images, carData[images] must still point at original_images '
      '(use_blurred_plates stayed false), and the final submitted bytes '
      'must be the ORIGINAL bytes',
      (tester) async {
        await bootSellWizard(tester);
        final controlled = await landOnChoiceStepAndStartBlur(
          tester,
          extraCarData: {
            'original_images': [
              {'source': originalAPath},
              {'source': originalBPath},
            ],
          },
        );

        expect(
          controlled.enqueuedJobIds,
          hasLength(2),
          reason: 'the enqueue call must have actually happened -- this '
              'test is meaningless otherwise',
        );
        expect(
          _noGenuineBlurResultYet(currentCarData(tester)['blurred_images']),
          isTrue,
        );

        // Background blur job is now mid-flight (both job polls are
        // deliberately un-answered). Tap UNBLURRED strictly before
        // completion.
        await tester.tap(find.text('No, keep original photos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        var carData = currentCarData(tester);
        expect(carData['use_blurred_plates'], isFalse);
        expect(_sourcesOf(carData['images']), [originalAPath, originalBPath]);
        expect(
          _noGenuineBlurResultYet(carData['blurred_images']),
          isTrue,
          reason: 'the blur job must still be mid-flight at this point -- '
              'this test is meaningless if it already finished',
        );

        // Now let the background job actually finish.
        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[0],
          'uploads/blurred_a_scen_a.jpg',
        );
        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[1],
          'uploads/blurred_b_scen_a.jpg',
        );
        await settleControlledJobs(tester);

        carData = currentCarData(tester);
        expect(
          _sourcesOf(carData['blurred_images']),
          ['uploads/blurred_a_scen_a.jpg', 'uploads/blurred_b_scen_a.jpg'],
          reason: 'the background job must have actually completed and '
              'written blurred_images by now',
        );
        expect(
          carData['use_blurred_plates'],
          isFalse,
          reason: 'the completion handler must not silently flip the '
              'already-made choice',
        );
        expect(
          _sourcesOf(carData['images']),
          [originalAPath, originalBPath],
          reason: 'THE KEY ASSERTION: after the blur job completes, '
              'carData[images] must still be the originals -- this is '
              'exactly the real-device symptom (chose unblurred, '
              'ended up uploading blurred) if it ever flips here',
        );

        late List<String> bytes;
        await tester.runAsync(() async {
          bytes = await _submitAndCaptureImageBytes(
            carData: carData,
            draftId: 'race_scenario_a',
          );
        });
        expect(bytes, ['ORIGINAL_A', 'ORIGINAL_B']);
      },
    );

    testWidgets(
      'Scenario B: user taps BLURRED WHILE the background blur job is '
      'still PENDING -- after the job completes, carData[images] must '
      'switch to the newly-available blurred_images '
      '(use_blurred_plates stayed true)',
      (tester) async {
        await bootSellWizard(tester);
        final controlled = await landOnChoiceStepAndStartBlur(
          tester,
          extraCarData: {
            'original_images': [
              {'source': originalAPath},
              {'source': originalBPath},
            ],
          },
        );

        expect(controlled.enqueuedJobIds, hasLength(2));
        expect(
          _noGenuineBlurResultYet(currentCarData(tester)['blurred_images']),
          isTrue,
        );

        await tester.tap(find.text('Yes, use blurred photos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        var carData = currentCarData(tester);
        expect(carData['use_blurred_plates'], isTrue);
        // Blur isn't ready yet -- applySellPlateBlurChoice's fallback
        // correctly leaves `images` on the originals until there is
        // something blurred to select.
        expect(_sourcesOf(carData['images']), [originalAPath, originalBPath]);

        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[0],
          'uploads/blurred_a_scen_b.jpg',
        );
        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[1],
          'uploads/blurred_b_scen_b.jpg',
        );
        await settleControlledJobs(tester);

        carData = currentCarData(tester);
        expect(
          _sourcesOf(carData['blurred_images']),
          ['uploads/blurred_a_scen_b.jpg', 'uploads/blurred_b_scen_b.jpg'],
        );
        expect(carData['use_blurred_plates'], isTrue);
        expect(
          _sourcesOf(carData['images']),
          ['uploads/blurred_a_scen_b.jpg', 'uploads/blurred_b_scen_b.jpg'],
          reason: 'once the blur job completes, the already-made BLURRED '
              'choice must now resolve to the newly-available '
              'blurred_images',
        );
      },
    );

    testWidgets(
      'Rapid interaction: user taps UNBLURRED then IMMEDIATELY continues '
      'to Review & Submit while the background blur job is still running '
      '-- the job finishes while Review is open, and carData[images] (and '
      'the final submitted bytes) must still be the originals',
      (tester) async {
        await bootSellWizard(tester);
        final controlled = await landOnChoiceStepAndStartBlur(
          tester,
          extraCarData: {
            'original_images': [
              {'source': originalAPath},
              {'source': originalBPath},
            ],
          },
        );

        expect(controlled.enqueuedJobIds, hasLength(2));

        // Tap UNBLURRED and immediately hit "Next Step" with no
        // intervening wait -- the closest a widget test can get to a
        // seller tapping through the wizard as fast as possible on a
        // real phone.
        await tester.tap(find.text('No, keep original photos'));
        await tester.pump();
        await tapNextSellStep(tester);

        expect(find.text('Review & Submit'), findsWidgets);

        // The background blur job (started on the Photos/choice step)
        // keeps running on `_SellCarPageState` regardless of which page
        // of the wizard is currently visible -- let it finish now, while
        // Review & Submit is on screen.
        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[0],
          'uploads/blurred_a_rapid.jpg',
        );
        controlled.completeJobSuccess(
          controlled.enqueuedJobIds[1],
          'uploads/blurred_b_rapid.jpg',
        );
        await settleControlledJobs(tester);

        final carData = currentCarData(tester);
        expect(
          _sourcesOf(carData['blurred_images']),
          ['uploads/blurred_a_rapid.jpg', 'uploads/blurred_b_rapid.jpg'],
          reason: 'the background job must have completed by now',
        );
        expect(carData['use_blurred_plates'], isFalse);
        expect(
          _sourcesOf(carData['images']),
          [originalAPath, originalBPath],
          reason: 'the rapid unblurred choice must survive both the '
              'immediate step transition and the later background-blur '
              'completion',
        );

        late List<String> bytes;
        await tester.runAsync(() async {
          bytes = await _submitAndCaptureImageBytes(
            carData: carData,
            draftId: 'race_rapid_interaction',
          );
        });
        expect(bytes, ['ORIGINAL_A', 'ORIGINAL_B']);
      },
    );
  });
}
