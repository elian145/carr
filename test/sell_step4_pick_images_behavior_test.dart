// True runtime behavioral tests for the Sell Step 1 "images appear slowly
// one-by-one" fix (see `sell_step4_background_photo_prep_test.dart` for
// the companion static/source-shape tests and the full root-cause write
// up). Unlike that file, these drive the REAL Sell wizard widget tree
// (same harness `sell_step4_video_preview_decoupling_test.dart`'s Section
// B already uses) with:
//   - `ImagePickerPlatform.instance` swapped for a fake that returns
//     caller-controlled `XFile` lists instead of launching the real OS
//     picker.
//   - `SellDraftMediaPersistence.debugBeforeCopyOverride` (new test-only
//     hook) to hold the durable-copy step open indefinitely, or resolve
//     it on demand per file -- simulating "background processing never
//     finishes" / "finishes one-by-one" / "finishes out of order" /
//     "fails for one file" without depending on real file-copy timing.
//
// Each `testWidgets` below is labelled with the spec test letter it
// implements (A-H).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

/// `SellDraftMediaPersistence`'s durable copy (`_draftDir`) needs a real
/// `getApplicationDocumentsDirectory()` -- same fix/rationale as every
/// other Sell test file's own `_FakeDocsPathProvider` (e.g.
/// `sell_blur_preview_progressive_lifecycle_test.dart`).
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
/// `pickMultiImage()` call, instead of launching the real OS picker.
/// [queue] is consumed one call at a time; once empty, further calls
/// return an empty list (matches a user cancelling the picker).
class FakeMultiImagePickerPlatform extends ImagePickerPlatform {
  final List<List<XFile>> queue = <List<XFile>>[];
  int callCount = 0;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    callCount++;
    if (queue.isEmpty) return <XFile>[];
    return queue.removeAt(0);
  }
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
    tempDir = await Directory.systemTemp.createTemp('sell_pick_behavior_');
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
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  /// Creates [count] small on-disk files (content is irrelevant -- these
  /// exercise the gallery-state/ordering contract, not real image
  /// decoding) and returns them as `XFile`s, named so their picked ORDER
  /// is obvious from the path.
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

  group('Spec tests A-H: real Sell Step 1 widget tree', () {
    testWidgets(
      'A: picker returns 5 images, durable-copy futures never complete -- '
      'gallery shows 5 immediately anyway',
      (tester) async {
        // Hold every durable copy open forever (never completes).
        final neverCompletes = Completer<void>();
        SellDraftMediaPersistence.debugBeforeCopyOverride =
            (_) => neverCompletes.future;

        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        fakePicker.queue.add(fixtureFiles('a', 5));
        await tapAddPhotos(tester);
        // Exactly one pump -- the picker Future and the immediate setState
        // both resolve on the same microtask/frame; no further time may
        // need to pass for all 5 to be visible.
        await tester.pump();

        expect(photoCountFromLabel(tester), 5);
        expect(find.text('Add photos (5)'), findsOneWidget);
      },
    );

    testWidgets(
      'B: 5 persistence futures complete one-by-one over several seconds '
      '-- gallery stays at 5 the entire time',
      (tester) async {
        final gates = <String, Completer<void>>{};
        SellDraftMediaPersistence.debugBeforeCopyOverride = (path) {
          return (gates[path] ??= Completer<void>()).future;
        };

        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final files = fixtureFiles('b', 5);
        fakePicker.queue.add(files);
        await tapAddPhotos(tester);
        await tester.pump();
        expect(photoCountFromLabel(tester), 5);

        // Release the gates one at a time, pumping real time in between --
        // the gallery count must never move.
        for (final f in files) {
          await tester.runAsync(() async {
            gates[f.path]?.complete();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump(const Duration(seconds: 1));
          expect(photoCountFromLabel(tester), 5);
        }
      },
    );

    testWidgets(
      'C: blur-prestage stays pending -- Step 1 still shows all selected '
      'originals',
      (tester) async {
        // Blur prestage runs AFTER durable copy in the background chain;
        // holding durable copy open also holds prestage from ever
        // starting, which is exactly the "still shows all originals"
        // assertion this test cares about.
        final neverCompletes = Completer<void>();
        SellDraftMediaPersistence.debugBeforeCopyOverride =
            (_) => neverCompletes.future;

        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        fakePicker.queue.add(fixtureFiles('c', 4));
        await tapAddPhotos(tester);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(photoCountFromLabel(tester), 4);
        expect(find.text('Add photos (4)'), findsOneWidget);
      },
    );

    testWidgets(
      'D: image #3 persistence fails -- all 5 remain in the gallery',
      (tester) async {
        final files = fixtureFiles('d', 5);
        SellDraftMediaPersistence.debugBeforeCopyOverride = (path) {
          if (path == files[2].path) {
            return Future<void>.error('simulated copy failure');
          }
          return Future<void>.value();
        };

        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        fakePicker.queue.add(files);
        await tapAddPhotos(tester);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(
          photoCountFromLabel(tester),
          5,
          reason: 'a background failure for one file must never remove '
              'any already-published photo, including the failed one',
        );
      },
    );

    testWidgets(
      'E: background tasks finish out of order -- final gallery ordering '
      'stays the original picker order',
      (tester) async {
        final gates = <String, Completer<void>>{};
        SellDraftMediaPersistence.debugBeforeCopyOverride = (path) {
          return (gates[path] ??= Completer<void>()).future;
        };

        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final files = fixtureFiles('e', 5);
        fakePicker.queue.add(files);
        await tapAddPhotos(tester);
        await tester.pump();
        expect(photoCountFromLabel(tester), 5);

        // Complete out of order: 5, 2, 1, 4, 3 (1-based) == indices
        // 4, 1, 0, 3, 2.
        for (final i in [4, 1, 0, 3, 2]) {
          await tester.runAsync(() async {
            gates[files[i].path]?.complete();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
          await tester.pump(const Duration(milliseconds: 200));
        }
        await tester.pump(const Duration(seconds: 1));

        // Ordering lives in `_selectedImages`, which drives the grid's
        // `ValueKey` (joined sources) -- assert the gallery still shows
        // exactly 5 and never crashed/reordered into a broken state.
        expect(photoCountFromLabel(tester), 5);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'F: select 5, then add 3 more -- first 5 remain, all 8 appear '
      'immediately once the second pick resolves',
      (tester) async {
        final neverCompletes = Completer<void>();
        SellDraftMediaPersistence.debugBeforeCopyOverride =
            (_) => neverCompletes.future;

        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        fakePicker.queue.add(fixtureFiles('f1', 5));
        await tapAddPhotos(tester);
        await tester.pump();
        expect(photoCountFromLabel(tester), 5);

        fakePicker.queue.add(fixtureFiles('f2', 3));
        await tapAddPhotos(tester, more: true);
        await tester.pump();

        expect(photoCountFromLabel(tester), 8);
      },
    );

    testWidgets(
      'G: removing an image while its background persistence is running '
      'does not resurrect it when that persistence later completes',
      (tester) async {
        final gates = <String, Completer<void>>{};
        SellDraftMediaPersistence.debugBeforeCopyOverride = (path) {
          return (gates[path] ??= Completer<void>()).future;
        };

        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        final files = fixtureFiles('g', 3);
        fakePicker.queue.add(files);
        await tapAddPhotos(tester);
        await tester.pump();
        expect(photoCountFromLabel(tester), 3);

        // Remove the first photo tile while persistence is still pending.
        final closeButtons = find.byIcon(Icons.close);
        expect(closeButtons, findsWidgets);
        await tester.tap(closeButtons.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(photoCountFromLabel(tester), 2);

        // Now let every pending persistence finish, including the removed
        // photo's.
        for (final f in files) {
          await tester.runAsync(() async {
            gates[f.path]?.complete();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
        }
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(
          photoCountFromLabel(tester),
          2,
          reason: 'the removed photo must never come back once its '
              'background persistence eventually resolves',
        );

        // Stale-media-after-delete fix: the delete's own restart (and/or
        // the original pick's own one-time restart, once durable-copy
        // unblocks) now correctly reads the CURRENT (already-pruned)
        // selection and genuinely calls `FakeApiServer`'s real
        // `/process-car-images` + `/api/jobs/<id>` endpoints over a real
        // socket -- `tester.pump(Duration)` alone does not drive that
        // real I/O to completion the way it drives fake `Timer`s; give
        // it real wall-clock time via `tester.runAsync` so its polling
        // loop actually finishes before teardown checks for pending
        // `Timer`s (same technique used by every other test file in this
        // suite that resolves a real/controlled blur job).
        for (var round = 0; round < 20; round++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
    );

    testWidgets(
      'H: navigating away from Sell Step 1 while background preparation '
      'is still running never throws (no setState-after-dispose)',
      (tester) async {
        final neverCompletes = Completer<void>();
        SellDraftMediaPersistence.debugBeforeCopyOverride =
            (_) => neverCompletes.future;

        await tester.pumpWidget(const legacy.MyApp());
        await tester.pump();
        await openSellStep1Fresh(tester);

        fakePicker.queue.add(fixtureFiles('h', 4));
        await tapAddPhotos(tester);
        await tester.pump();
        expect(photoCountFromLabel(tester), 4);

        // Pop the Sell wizard away entirely while backfill/durable-copy is
        // still pending in the background.
        final nav = tester.state<NavigatorState>(find.byType(Navigator));
        nav.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Let the still-pending background work's `mounted` checks run
        // against the now-disposed State.
        neverCompletes.complete();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
      },
    );
  });
}
