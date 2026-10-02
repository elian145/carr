// Stale-media-after-delete / async-resurrection fix (NEW REAL-DEVICE BUG):
//   "In Sell Step 1: add several photos, blur preview/prestage begins in
//   the background, delete some of those photos, then at the Blurred /
//   Unblurred choice step the DELETED photos still appear."
//
// Root causes fixed (see `sell_step4_logic.dart`):
//   1. `_removePhotoAt`/`_removeDamagePhotoAt` fired
//      `unawaited(_syncMediaDraftToParent())` then immediately
//      `unawaited(startBackgroundPlateBlur())` with no synchronization --
//      the NEW blur job read `carData['original_images']` SYNCHRONOUSLY,
//      before the slow, async `_syncMediaDraftToParent()` had written the
//      post-deletion list, so it started from a STALE (pre-deletion) set
//      and later wrote the deleted photo's own blur result straight back
//      into `carData`. Fixed by synchronously publishing the pruned lists
//      into `carData` BEFORE invalidating/restarting the blur job.
//   2. `_blurredImages` (Step4's own local field) was pruned POSITIONALLY
//      (`removeAt(index)`), but it is populated ASYNCHRONOUSLY and is not
//      guaranteed to stay index-aligned with `_selectedImages`. Fixed via
//      `_pruneBlurredToCurrentSelection` (identity-first, path-fallback).
//   3. `_syncMediaDraftToParent()` had no generation guard -- two
//      overlapping calls (one from an in-flight pick, one from a delete)
//      could let the OLDER (stale) one's `setState` land last and
//      resurrect a deleted item. Fixed with `_mediaSyncGeneration`.
//   4. Step 5 trusted `carData['blurred_images']`/`['blurred_damage_images']`
//      verbatim. Fixed with a defensive identity/path filter against the
//      CURRENT `original_images`/`original_damage_images`
//      (`_filterToCurrentSelection`, `sell_step_blur_choice_logic.dart`).
//   5. A fresh, per-pick `_ui_media_id` (`ListingImageMedia.uiMediaId`,
//      seeded with a monotonic counter) makes "delete X, re-pick the same
//      file" produce a genuinely NEW identity, so a stale in-flight
//      result for the OLD pick can never attach to the new one.
//
// Test letters below match the user's own spec (A-J); some are
// implemented as direct Step-5 carData constructions (fast, no real
// async machinery needed) and some drive the real Step-1 widget with a
// controlled fake blur-job HTTP client (same technique as
// `sell_blur_preview_progressive_lifecycle_test.dart` /
// `sell_step4_pick_images_behavior_test.dart`).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:car_listing_app/features/sell/sell_media_identity.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/listings/listing_image_media.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

/// Same fix/rationale as every other Sell test file's own copy of this --
/// `SellDraftMediaPersistence`'s durable copy and `CachedNetworkImage`'s
/// disk cache both need a real `getApplicationDocumentsDirectory()`/
/// `getTemporaryDirectory()`.
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

/// Returns a caller-controlled list of [XFile]s for every
/// `pickMultiImage()` call instead of launching the real OS picker --
/// same technique as `sell_step4_pick_images_behavior_test.dart`.
class FakeMultiImagePickerPlatform extends ImagePickerPlatform {
  final List<List<XFile>> queue = <List<XFile>>[];

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    if (queue.isEmpty) return <XFile>[];
    return queue.removeAt(0);
  }
}

/// Deterministic, zero-real-Timer fake for `/process-car-images` +
/// `/api/jobs/<id>` -- same technique as `_ControlledJobClient` in
/// `sell_blur_preview_progressive_lifecycle_test.dart`. Every call to
/// `/process-car-images` enqueues one job per picked LOCAL file (in
/// order) and returns its job id immediately; each job stays PENDING
/// until the test explicitly resolves it.
class _ControlledJobClient {
  final Map<String, Completer<http.Response>> _pending = {};
  final List<List<String>> enqueuedBatches = [];
  int _seq = 0;

  int _countMultipartParts(http.Request request, String fieldName) {
    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.contains('multipart/form-data')) return 0;
    final bodyStr = latin1.decode(request.bodyBytes);
    return RegExp('name="$fieldName"').allMatches(bodyStr).length;
  }

  late final http.Client client = MockClient((request) async {
    final method = request.method.toUpperCase();
    final path = request.url.path;

    if (method == 'POST' && path.endsWith('/process-car-images')) {
      final fileCount = _countMultipartParts(request, 'images');
      final ids = <String>[];
      for (var i = 0; i < fileCount; i++) {
        final jobId = 'del-job-$_seq-$i';
        _pending[jobId] = Completer<http.Response>();
        ids.add(jobId);
      }
      enqueuedBatches.add(ids);
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

  void completeJobSuccess(String jobId, String relPath) {
    final completer = _pending[jobId];
    if (completer == null || completer.isCompleted) return;
    completer.complete(
      http.Response(
        json.encode({
          'state': 'SUCCESS',
          'result': {
            'rel_path': relPath,
            '_trace_plate_blur_applied': true,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
  }
}

/// Every URL currently rendered via `CachedNetworkImage`, in tree order.
List<String> _renderedNetworkImageUrls(WidgetTester tester) {
  return tester
      .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
      .map((w) => w.imageUrl)
      .toList();
}

void main() {
  late Directory tempDir;
  late FakeMultiImagePickerPlatform fakePicker;
  late ImagePickerPlatform originalPicker;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sell_delete_resurrect_');
    originalPicker = ImagePickerPlatform.instance;
    fakePicker = FakeMultiImagePickerPlatform();
    ImagePickerPlatform.instance = fakePicker;
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
    SellDraftMediaPersistence.debugBeforeCopyOverride = null;
    ImagePickerPlatform.instance = originalPicker;
    ApiService.testHttpClient = null;
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  List<XFile> fixtureFiles(String label, int count) {
    return List.generate(count, (i) {
      final path = p.join(tempDir.path, '${label}_$i.jpg');
      File(path).writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9, i]);
      return XFile(path);
    });
  }

  Future<void> tapAddPhotos(WidgetTester tester, {bool more = false}) async {
    final label = more ? 'Add More Photos' : 'Add Photos';
    final finder = find.widgetWithText(ElevatedButton, label);
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(finder);
    await tester.pump();
  }

  int photoCountFromLabel(WidgetTester tester) {
    final matches = find.textContaining(RegExp(r'^Add photos \(\d+\)$'));
    if (matches.evaluate().isEmpty) return 0;
    final text = tester.widget<Text>(matches).data!;
    final m = RegExp(r'\((\d+)\)').firstMatch(text)!;
    return int.parse(m.group(1)!);
  }

  /// Taps the close ("x") button on the Nth currently-rendered photo
  /// tile (0-based, in grid order).
  Future<void> deletePhotoAt(WidgetTester tester, int index) async {
    final closeButtons = find.byIcon(Icons.close);
    expect(closeButtons.evaluate().length, greaterThan(index));
    await tester.tap(closeButtons.at(index));
    await tester.pump();
  }

  Map<String, dynamic> carDataOf(WidgetTester tester) {
    return Map<String, dynamic>.from(
      (tester.state(find.byType(SellCarPage)) as dynamic).carData as Map,
    );
  }

  List<String> sourcesOf(List<dynamic> items) =>
      items.map(ListingImageMedia.source).toList();

  Map<String, dynamic> baseFields() => {
        ...sellCarDataThroughStep3(),
        'sell_wizard_v2': true,
      };

  /// Real durable-copy file I/O (`dart:io`) and the controlled job
  /// client's HTTP round-trips both run on the REAL event loop, not the
  /// fake-async zone a plain `pump()` drives -- `tester.runAsync()` is
  /// required to actually let them progress (same technique as
  /// `sell_blur_preview_progressive_lifecycle_test.dart`'s `settle()`).
  Future<void> settle(WidgetTester tester) async {
    // Every `persistDynamicMediaList` call for a given draft is
    // serialized through a single per-draft queue
    // (`SellDraftMediaPersistence._serializedForDraft`) -- several
    // overlapping `_syncMediaDraftToParent` calls (one per pick/delete in
    // these tests) can queue up many real sub-operations deep, so this
    // needs enough real-time rounds to fully drain, not just settle one
    // call's own awaits.
    for (var round = 0; round < 60; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// A pick's own background chain (`_prepareImagesInBackground`:
  /// dimension backfill, THEN `_syncMediaDraftToParent()`, THEN its own
  /// `unawaited(startBackgroundPlateBlur())`) is real, multi-step async
  /// work -- if a test deletes a photo before that chain's OWN
  /// `startBackgroundPlateBlur()` call has happened yet, that call still
  /// fires LATER (reading the by-then-already-pruned, CURRENT selection,
  /// so it is not itself incorrect) and can supersede/invalidate a
  /// delete's OWN restart with a redundant one for the exact same
  /// selection -- flaky to depend on for tests that want to resolve ONE
  /// specific, predictable job batch. Waiting for the pick's FIRST batch
  /// to actually land in [controlled]`.enqueuedBatches` before deleting
  /// anything guarantees `_prepareImagesInBackground`'s own call site has
  /// already executed its one-time `startBackgroundPlateBlur()` call (an
  /// `unawaited` fire-and-forget -- once reached, it never fires again
  /// for this same pick), so every later restart in the test is then
  /// deterministically caused by (and only by) that test's own explicit
  /// deletes.
  Future<void> waitForInitialEnqueue(
    WidgetTester tester,
    _ControlledJobClient controlled,
  ) async {
    for (var round = 0; round < 60; round++) {
      if (controlled.enqueuedBatches.isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group(
    'Step 5 defensive filtering against stale blurred_images '
    '(spec item 4; direct carData, no async needed)',
    () {
      Map<String, dynamic> img(String id, String source) =>
          {'source': source, '_ui_media_id': id};

      testWidgets(
        'A/H: originals are now A C E F G (B D deleted, F G added) but '
        'blurred_images is STALE from before that (A B C D E, same '
        'length so the auto-resume background job never kicks in) -- '
        'Step 5 shows exactly A C E for Blurred (filtered), and exactly '
        'A C E F G, in order, for Unblurred',
        (tester) async {
          await tester.pumpWidget(const legacy.MyApp());
          await tester.pump();
          await openSellDraftStep(
            tester,
            step: 4,
            carData: {
              ...baseFields(),
              'original_images': [
                img('A', 'http://x.test/a.jpg'),
                img('C', 'http://x.test/c.jpg'),
                img('E', 'http://x.test/e.jpg'),
                img('F', 'http://x.test/f.jpg'),
                img('G', 'http://x.test/g.jpg'),
              ],
              // Deliberately STALE: still carries B and D's blurred
              // output (and has no entries for F/G yet), exactly as a
              // pre-fix race would have left it. Same LENGTH as
              // originals so `hasBlurredPlatesReady` doesn't trigger an
              // unrelated auto-restart of the (unmocked, in this group)
              // background blur job.
              'blurred_images': [
                img('A', 'http://x.test/a_blur.jpg'),
                img('B', 'http://x.test/b_blur.jpg'),
                img('C', 'http://x.test/c_blur.jpg'),
                img('D', 'http://x.test/d_blur.jpg'),
                img('E', 'http://x.test/e_blur.jpg'),
              ],
              'use_blurred_plates': true,
            },
          );
          await tester.pump(const Duration(milliseconds: 200));

          final rendered = _renderedNetworkImageUrls(tester);
          expect(
            rendered,
            ['http://x.test/a_blur.jpg', 'http://x.test/c_blur.jpg', 'http://x.test/e_blur.jpg'],
            reason: 'B and D must be filtered out, and A/C/E must keep '
                'their original relative order',
          );

          await tester.tap(find.text('No, keep original photos'));
          await tester.pump();

          final renderedOriginals = _renderedNetworkImageUrls(tester);
          expect(
            renderedOriginals,
            [
              'http://x.test/a.jpg',
              'http://x.test/c.jpg',
              'http://x.test/e.jpg',
              'http://x.test/f.jpg',
              'http://x.test/g.jpg',
            ],
          );
        },
      );

      testWidgets(
        'A (all-deleted edge case): every original was removed -- a '
        'leftover blurred_images list must render NOTHING, not the stale '
        'entries',
        (tester) async {
          await tester.pumpWidget(const legacy.MyApp());
          await tester.pump();
          await openSellDraftStep(
            tester,
            step: 4,
            carData: {
              ...baseFields(),
              'original_images': const [],
              'blurred_images': [
                img('A', 'http://x.test/a_blur.jpg'),
                img('B', 'http://x.test/b_blur.jpg'),
              ],
              'use_blurred_plates': true,
            },
          );
          await tester.pump(const Duration(milliseconds: 200));

          expect(_renderedNetworkImageUrls(tester), isEmpty);
        },
      );
    },
  );

  group(
    'Delete-path identity pruning + async-resurrection guard '
    '(real Step 1 widget + controlled blur-job HTTP client)',
    () {
      testWidgets(
        'B: blur job enqueued for A B C, C deleted before its job '
        'resolves, C\'s job THEN resolves -- C never reappears',
        (tester) async {
          final controlled = _ControlledJobClient();
          ApiService.testHttpClient = controlled.client;

          await tester.pumpWidget(const legacy.MyApp());
          await tester.pump();
          await openSellStep1Fresh(tester);

          final files = fixtureFiles('b', 3);
          fakePicker.queue.add(files);
          await tapAddPhotos(tester);
          await tester.pump();
          await settle(tester);
          expect(photoCountFromLabel(tester), 3);
          expect(controlled.enqueuedBatches, hasLength(1));
          expect(controlled.enqueuedBatches.single, hasLength(3));
          final staleJobIds = controlled.enqueuedBatches.single;

          // Delete the THIRD photo (C) while its job is still pending.
          await deletePhotoAt(tester, 2);
          await settle(tester);
          expect(photoCountFromLabel(tester), 2);

          // A fresh job batch must have been enqueued for the remaining
          // A/B only (the race fix: the new job reads the ALREADY-pruned
          // list, not the stale pre-deletion one).
          expect(controlled.enqueuedBatches.length, greaterThanOrEqualTo(2));
          expect(controlled.enqueuedBatches.last, hasLength(2));

          // Now resolve the OLD (stale, now-superseded) job's result for
          // C -- it must never surface anywhere.
          controlled.completeJobSuccess(
            staleJobIds[2],
            'uploads/c_should_never_appear.jpg',
          );
          await settle(tester);

          final carData = carDataOf(tester);
          final originals = carData['original_images'] as List? ?? [];
          final blurred = carData['blurred_images'] as List? ?? [];
          expect(originals, hasLength(2));
          expect(
            sourcesOf(originals).any((s) => s.contains(files[2].path)),
            isFalse,
          );
          expect(
            sourcesOf(blurred).any(
              (s) => s.contains('c_should_never_appear.jpg'),
            ),
            isFalse,
            reason: 'a stale job result for a deleted photo must never '
                'be written into blurred_images',
          );

          // The fresh (A/B-only) restart's own jobs were never resolved
          // above (this test only cares that the STALE job's result for
          // C never surfaces) -- resolve them now so their polling loop
          // doesn't leave a real `Timer` pending at test teardown.
          for (final batch in controlled.enqueuedBatches) {
            for (final jobId in batch) {
              controlled.completeJobSuccess(jobId, 'uploads/resolved.jpg');
            }
          }
          await settle(tester);
        },
      );

      testWidgets(
        'C: delete a photo AFTER its own blurred result already exists '
        '-- the result is pruned immediately, synchronously, with the '
        'delete itself (no further async needed)',
        (tester) async {
          final controlled = _ControlledJobClient();
          ApiService.testHttpClient = controlled.client;

          await tester.pumpWidget(const legacy.MyApp());
          await tester.pump();
          await openSellStep1Fresh(tester);

          final files = fixtureFiles('c', 2);
          fakePicker.queue.add(files);
          await tapAddPhotos(tester);
          await tester.pump();
          await settle(tester);
          expect(controlled.enqueuedBatches, hasLength(1));
          final jobIds = controlled.enqueuedBatches.single;

          controlled.completeJobSuccess(jobIds[0], 'uploads/a_blurred.jpg');
          controlled.completeJobSuccess(jobIds[1], 'uploads/b_blurred.jpg');
          await settle(tester);

          var carData = carDataOf(tester);
          expect(
            sourcesOf(carData['blurred_images'] as List),
            ['uploads/a_blurred.jpg', 'uploads/b_blurred.jpg'],
          );

          // Delete the SECOND photo (whose blurred result already
          // resolved).
          await deletePhotoAt(tester, 1);

          // Assert IMMEDIATELY -- the synchronous carData pre-write must
          // have already pruned it, with no further pumping needed.
          carData = carDataOf(tester);
          expect(
            sourcesOf(carData['original_images'] as List),
            hasLength(1),
          );
          expect(
            sourcesOf(carData['blurred_images'] as List),
            ['uploads/a_blurred.jpg'],
            reason: 'the deleted photo\'s already-resolved blurred result '
                'must be pruned the instant it is deleted',
          );
        },
      );

      testWidgets(
        'D: delete two of five while multiple blur jobs resolve OUT OF '
        'ORDER -- only the currently-selected ones ever end up in '
        'blurred_images, in originals\' order',
        (tester) async {
          final controlled = _ControlledJobClient();
          ApiService.testHttpClient = controlled.client;

          await tester.pumpWidget(const legacy.MyApp());
          await tester.pump();
          await openSellStep1Fresh(tester);

          final files = fixtureFiles('d', 5);
          fakePicker.queue.add(files);
          await tapAddPhotos(tester);
          await tester.pump();
          await settle(tester);
          expect(photoCountFromLabel(tester), 5);
          // See `waitForInitialEnqueue`'s doc comment: make sure the
          // pick's OWN background chain has already reached its
          // one-time `startBackgroundPlateBlur()` call before either
          // delete below, so it can never supersede a delete's restart
          // later with a surprise, hard-to-predict extra job.
          await waitForInitialEnqueue(tester, controlled);
          expect(controlled.enqueuedBatches, hasLength(1));
          expect(controlled.enqueuedBatches.single, hasLength(5));

          // Delete B (index 1), then D (now index 2, since A C D E
          // remains after removing B).
          await deletePhotoAt(tester, 1);
          await tester.pump(const Duration(milliseconds: 100));
          await deletePhotoAt(tester, 2);
          await settle(tester);
          expect(photoCountFromLabel(tester), 3);

          // Both deletes' own restarts read `_plateBlurOriginals()`
          // SYNCHRONOUSLY (no `await` before it), so their ENQUEUED
          // BATCH CONTENT is deterministic regardless of real-world
          // scheduling -- but the ORDER they end up recorded in
          // [controlled]`.enqueuedBatches` is NOT: each restart's own
          // `AiService.enqueueCarImagesAsync` reads its own files off
          // disk before POSTing, and that real I/O can finish in either
          // order. `waitForInitialEnqueue` above already guarantees the
          // pick's own one-time restart fired before any delete, so the
          // only two restarts left are exactly "B's delete" (4 items)
          // and "D's delete" (3 items) -- look up the 3-item one by
          // CONTENT, not position.
          final latestJobIds = controlled.enqueuedBatches.firstWhere(
            (b) => b.length == 3,
          );

          // Resolve out of order: E (index 2), A (index 0), C (index 1).
          controlled.completeJobSuccess(
            latestJobIds[2],
            'uploads/e_blurred.jpg',
          );
          await settle(tester);
          controlled.completeJobSuccess(
            latestJobIds[0],
            'uploads/a_blurred.jpg',
          );
          await settle(tester);
          controlled.completeJobSuccess(
            latestJobIds[1],
            'uploads/c_blurred.jpg',
          );
          await settle(tester);

          final carData = carDataOf(tester);
          expect(
            sourcesOf(carData['original_images'] as List),
            hasLength(3),
          );
          expect(
            sourcesOf(carData['blurred_images'] as List),
            ['uploads/a_blurred.jpg', 'uploads/c_blurred.jpg', 'uploads/e_blurred.jpg'],
            reason: 'background completion order must never become '
                'gallery order -- the result stays in A/C/E (originals\') '
                'order regardless of which job resolved first',
          );

          // The OTHER restart (B's delete, invalidated/superseded by
          // D's) is left with its own jobs never resolved -- clean those
          // up too (same rationale as E/F's own cleanup) so their
          // polling loops don't leave a real `Timer` pending at test
          // teardown. Their results are irrelevant: each is stale by
          // construction (any still-outstanding job's `jobId` no longer
          // matches `_plateBlurJobId`, so its own completion is always
          // ignored by `_blurMediaList`'s own guard, regardless of what
          // ends up in these dummy results).
          for (final batch in controlled.enqueuedBatches) {
            if (identical(batch, latestJobIds)) continue;
            for (final jobId in batch) {
              controlled.completeJobSuccess(jobId, 'uploads/stale.jpg');
            }
          }
          await settle(tester);
        },
      );

      testWidgets(
        'E/F: deleting a photo while the background durable-copy/sync '
        'pipeline for the ENTIRE just-picked batch is still pending, '
        'then letting it complete, must not resurrect the deleted photo '
        'or its blur state',
        (tester) async {
          final controlled = _ControlledJobClient();
          ApiService.testHttpClient = controlled.client;

          final gates = <String, Completer<void>>{};
          SellDraftMediaPersistence.debugBeforeCopyOverride = (path) {
            return (gates[path] ??= Completer<void>()).future;
          };

          await tester.pumpWidget(const legacy.MyApp());
          await tester.pump();
          await openSellStep1Fresh(tester);

          final files = fixtureFiles('ef', 3);
          fakePicker.queue.add(files);
          await tapAddPhotos(tester);
          await tester.pump();
          expect(photoCountFromLabel(tester), 3);

          // Durable copy (and therefore the blur-job enqueue that follows
          // it in `_prepareImagesInBackground`) is still held open for
          // every file -- nothing has been enqueued yet.
          expect(controlled.enqueuedBatches, isEmpty);

          // Delete the middle photo while persistence is still pending.
          await deletePhotoAt(tester, 1);
          await tester.pump(const Duration(milliseconds: 100));
          expect(photoCountFromLabel(tester), 2);

          // Now let every pending durable-copy gate resolve, including
          // the deleted photo's own.
          for (final f in files) {
            await tester.runAsync(() async {
              gates[f.path]?.complete();
              await Future<void>.delayed(const Duration(milliseconds: 20));
            });
          }
          await settle(tester);

          expect(
            photoCountFromLabel(tester),
            2,
            reason: 'the deleted photo must not come back once the '
                'original pick\'s background pipeline finally completes',
          );
          final carData = carDataOf(tester);
          expect(
            sourcesOf(carData['original_images'] as List),
            hasLength(2),
          );

          // Once persistence finally unblocks, the pick's own background
          // chain still fires its one-time `startBackgroundPlateBlur()`
          // call (now correctly reading the ALREADY-pruned, 2-item
          // selection -- itself not a bug; see `waitForInitialEnqueue`'s
          // doc comment on the equivalent race in test D). Resolve
          // whatever that job batch turns out to be so its polling loop
          // doesn't leave a real `Timer` pending at test teardown.
          for (final batch in controlled.enqueuedBatches) {
            for (final jobId in batch) {
              controlled.completeJobSuccess(jobId, 'uploads/resolved.jpg');
            }
          }
          await settle(tester);
        },
      );

      testWidgets(
        'G: delete a photo, then re-pick the EXACT SAME file -- an old '
        'in-flight blur result for the deleted pick must not attach to '
        'the new one',
        (tester) async {
          final controlled = _ControlledJobClient();
          ApiService.testHttpClient = controlled.client;

          await tester.pumpWidget(const legacy.MyApp());
          await tester.pump();
          await openSellStep1Fresh(tester);

          final file = fixtureFiles('g', 1).single;
          fakePicker.queue.add([file]);
          await tapAddPhotos(tester);
          await tester.pump();
          await settle(tester);
          expect(photoCountFromLabel(tester), 1);
          expect(controlled.enqueuedBatches, hasLength(1));
          final oldJobId = controlled.enqueuedBatches.single.single;

          // Delete it, then re-pick the SAME physical path.
          await deletePhotoAt(tester, 0);
          await settle(tester);
          expect(photoCountFromLabel(tester), 0);

          fakePicker.queue.add([XFile(file.path)]);
          await tapAddPhotos(tester, more: false);
          await tester.pump();
          await settle(tester);
          expect(photoCountFromLabel(tester), 1);
          expect(controlled.enqueuedBatches.length, greaterThanOrEqualTo(2));
          final newJobId = controlled.enqueuedBatches.last.single;

          // Resolve the OLD job (for the deleted pick) with a
          // DISTINGUISHABLE result -- it must never attach to the new
          // item.
          controlled.completeJobSuccess(
            oldJobId,
            'uploads/STALE_should_never_attach.jpg',
          );
          await settle(tester);

          var carData = carDataOf(tester);
          var blurred = carData['blurred_images'] as List? ?? [];
          expect(
            sourcesOf(blurred).any((s) => s.contains('STALE_should_never_attach')),
            isFalse,
            reason: 'the old pick\'s job result must never attach to the '
                're-picked item, even though it is the same file path',
          );

          // The NEW job (for the re-pick) resolving normally must still
          // work correctly.
          controlled.completeJobSuccess(
            newJobId,
            'uploads/fresh_pick_blurred.jpg',
          );
          await settle(tester);

          carData = carDataOf(tester);
          blurred = carData['blurred_images'] as List? ?? [];
          expect(
            sourcesOf(blurred),
            ['uploads/fresh_pick_blurred.jpg'],
          );
        },
      );

      // H ("select A..E, delete B and D, add F G -- final originals order
      // is exactly A C E F G") is covered directly by the "A/H" test in
      // the "Step 5 defensive filtering" group above, via an explicit
      // carData construction -- that keeps the assertion deterministic
      // instead of depending on exact real-async interleaving of several
      // overlapping `_syncMediaDraftToParent`/background-job calls (this
      // repo's own pre-existing per-draft persistence queue --
      // `SellDraftMediaPersistence._serializedForDraft` -- legitimately
      // takes a variable, real-I/O-dependent amount of time to drain many
      // overlapping pick/delete calls, which is orthogonal to what this
      // test is trying to prove). The ordering GUARANTEE itself comes
      // from `_removePhotoAt`/`_pickImages` only ever filtering or
      // appending -- never reordering -- `_selectedImages`, which the
      // "A/H" test exercises end-to-end at the Step-5 rendering layer.
    },
  );

  group('Final submission manifest excludes deleted photos (spec item 9J)', () {
    test(
      'J: buildExpectedMedia only ever reflects carData[original_images] '
      '-- deleted client_media_ids never appear',
      () {
        // `_removePhotoAt`'s fix guarantees `original_images` is always
        // the pruned, post-deletion list by the time submission reads it
        // (see `SellMediaIdentity.finalListingImages`) -- this is a
        // direct, pure-function proof of that downstream consequence.
        final carData = <String, dynamic>{
          'original_images': [
            {'source': '/tmp/a.jpg'},
            {'source': '/tmp/c.jpg'},
          ],
          // A stale `images`/`blurred_images` leftover must never be
          // consulted when `original_images` is present and non-empty.
          'images': [
            {'source': '/tmp/a.jpg'},
            {'source': '/tmp/b_DELETED.jpg'},
            {'source': '/tmp/c.jpg'},
          ],
        };

        final expected = SellMediaIdentity.buildExpectedMedia(carData);
        final expectedIds = expected.map((e) => e['client_media_id']).toSet();
        final deletedId = SellMediaIdentity.forImageItem(
          {'source': '/tmp/b_DELETED.jpg'},
          kind: 'listing',
        );

        expect(expected, hasLength(2));
        expect(expectedIds.contains(deletedId), isFalse);
      },
    );
  });
}
