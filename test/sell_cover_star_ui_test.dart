// Sell page: tapping the star on a photo makes THAT photo the cover.
//
// Drives the real Step 1 (photos) widget. Pins the UI/state half of the
// cover-selection fix:
//   * the star immediately updates the cover (state + draft),
//   * only ever one cover,
//   * the choice survives saving and re-opening the draft,
//   * deleting the cover (or a photo before it) keeps a valid cover,
//   * the starred photo is what the submission will declare
//     (`SellMediaIdentity.buildExpectedMedia`).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class _FakePicker extends ImagePickerPlatform {
  final List<List<XFile>> queue = <List<XFile>>[];

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async => queue.isEmpty ? <XFile>[] : queue.removeAt(0);
}

/// Background plate-blur preview jobs: accepted immediately and left PENDING
/// (same technique as `sell_step4_delete_resurrection_test.dart`) so the test
/// controls the lists; [resolveAll] finishes them so nothing is left polling
/// at teardown.
class _PendingBlurJobs {
  final Map<String, Completer<http.Response>> _pending = {};
  int _seq = 0;

  late final http.Client client = MockClient((request) async {
    final path = request.url.path;
    Map<String, String> h() => {'content-type': 'application/json'};
    if (request.method == 'POST' && path.endsWith('/process-car-images')) {
      final n = RegExp('name="images"')
          .allMatches(latin1.decode(request.bodyBytes))
          .length;
      final ids = <String>[];
      for (var i = 0; i < n; i++) {
        final id = 'cov-job-$_seq-$i';
        _pending[id] = Completer<http.Response>();
        ids.add(id);
      }
      _seq++;
      return http.Response(json.encode({'job_ids': ids}), 202, headers: h());
    }
    final job = RegExp(r'^/api/jobs/(.+)$').firstMatch(path);
    if (request.method == 'GET' && job != null) {
      final c = _pending[Uri.decodeComponent(job.group(1)!)];
      if (c != null) return c.future;
      return http.Response(json.encode({'state': 'PENDING'}), 200, headers: h());
    }
    return http.Response('{}', 200, headers: h());
  });

  void resolveAll() {
    for (final c in _pending.values) {
      if (c.isCompleted) continue;
      c.complete(
        http.Response(
          json.encode({
            'state': 'SUCCESS',
            'result': {'rel_path': 'uploads/blurred.jpg'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
    }
  }
}

void main() {
  late Directory tempDir;
  late _FakePicker fakePicker;
  late ImagePickerPlatform originalPicker;
  late PathProviderPlatform previousPathProvider;
  late _PendingBlurJobs blurJobs;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sell_cover_star_');
    originalPicker = ImagePickerPlatform.instance;
    fakePicker = _FakePicker();
    ImagePickerPlatform.instance = fakePicker;
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakeDocsPathProvider(tempDir.path);
    SellDraftMediaPersistence.debugResetMediaLifecycleForTest();
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
    blurJobs = _PendingBlurJobs();
    ApiService.testHttpClient = blurJobs.client;
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
    SellDraftMediaPersistence.debugResetMediaLifecycleForTest();
    ImagePickerPlatform.instance = originalPicker;
    PathProviderPlatform.instance = previousPathProvider;
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

  List<XFile> fixtureFiles(String label, int count) => List.generate(count, (i) {
    final path = p.join(tempDir.path, '${label}_$i.jpg');
    File(path).writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9, i]);
    return XFile(path);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 40; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Map<String, dynamic> carDataOf(WidgetTester tester) => Map<String, dynamic>.from(
    (tester.state(find.byType(SellCarPage)) as dynamic).carData as Map,
  );

  /// Real file I/O (durable copy) runs on the real event loop; wait until the
  /// picked photos have actually been published into `carData`.
  Future<void> waitForOriginals(WidgetTester tester, int count) async {
    for (var i = 0; i < 300; i++) {
      final list = carDataOf(tester)['original_images'];
      if (list is List && list.length >= count) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pickPhotos(WidgetTester tester, List<XFile> files) async {
    fakePicker.queue.add(files);
    final finder = find.widgetWithText(ElevatedButton, 'Add Photos');
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(finder);
    await tester.pump();
    await waitForOriginals(tester, files.length);
    await settle(tester);
  }

  Future<void> openPhotosStep(WidgetTester tester, int photos) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await openSellStep1Fresh(tester);
    PathProviderPlatform.instance = _FakeDocsPathProvider(tempDir.path);
    SellDraftMediaPersistence.debugResetMediaLifecycleForTest();
    await pickPhotos(tester, fixtureFiles('photo', photos));
  }

  /// Taps the star on the Nth photo tile (0-based grid index). Only
  /// NON-cover tiles carry a tappable `star_border`, in grid order.
  Future<void> starPhoto(WidgetTester tester, int tile) async {
    final primary = carDataOf(tester)['primary_image_index'] as int? ?? 0;
    expect(tile, isNot(primary), reason: 'that photo is already the cover');
    final borders = find.byIcon(Icons.star_border);
    final position = tile < primary ? tile : tile - 1;
    expect(borders.evaluate().length, greaterThan(position));
    await tester.ensureVisible(borders.at(position));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(borders.at(position));
    await tester.pump();
    await settle(tester);
  }

  Future<void> deletePhotoAt(WidgetTester tester, int index) async {
    final close = find.byIcon(Icons.close);
    expect(close.evaluate().length, greaterThan(index));
    await tester.ensureVisible(close.at(index));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(close.at(index));
    await tester.pump();
    await settle(tester);
  }

  /// Resolve any still-pending blur jobs and let everything drain.
  Future<void> finish(WidgetTester tester) async {
    blurJobs.resolveAll();
    await settle(tester);
  }

  int starCount(WidgetTester tester) => find.byIcon(Icons.star).evaluate().length;

  /// Which tile (by its close button) is the cover badge closest to?
  int coverTileIndex(WidgetTester tester) {
    // The badge lives inside its own tile's Stack; the tile's close button is
    // in that same Stack, so the tile index = the close button inside it.
    final tileStack = find
        .ancestor(of: find.byIcon(Icons.star).first, matching: find.byType(Stack))
        .first;
    final rect = tester.getRect(tileStack);
    final closes = find.byIcon(Icons.close);
    for (var i = 0; i < closes.evaluate().length; i++) {
      if (rect.contains(tester.getCenter(closes.at(i)))) return i;
    }
    return -1;
  }

  List<String> originals(WidgetTester tester) => [
    for (final it in (carDataOf(tester)['original_images'] as List? ?? const []))
      ListingImageMedia.source(it),
  ];

  List<bool> declaredCovers(WidgetTester tester) => [
    for (final e in SellMediaIdentity.buildExpectedMedia(carDataOf(tester)))
      e['is_cover'] == 'true',
  ];

  testWidgets('1. star photo 3 of 5 -> photo 3 is the cover immediately', (
    tester,
  ) async {
    await openPhotosStep(tester, 5);
    expect(carDataOf(tester)['primary_image_index'] ?? 0, 0);
    expect(starCount(tester), 1, reason: 'first photo is the default cover');

    await starPhoto(tester, 2);

    expect(carDataOf(tester)['primary_image_index'], 2);
    expect(starCount(tester), 1, reason: 'only one cover badge');
    expect(coverTileIndex(tester), 2, reason: 'the badge moved to photo 3');
    expect(
      declaredCovers(tester),
      [false, false, true, false, false],
      reason: 'the submission will declare photo 3 as the cover',
    );
    await finish(tester);
  });

  testWidgets('2. star photo 2 after photo 3 -> photo 2 is the ONLY cover', (
    tester,
  ) async {
    await openPhotosStep(tester, 5);
    await starPhoto(tester, 2);
    await starPhoto(tester, 1);

    expect(carDataOf(tester)['primary_image_index'], 1);
    expect(starCount(tester), 1);
    expect(coverTileIndex(tester), 1);
    expect(declaredCovers(tester), [false, true, false, false, false]);
    await finish(tester);
  });

  testWidgets('3. save + reopen the draft -> the cover is preserved', (
    tester,
  ) async {
    await openPhotosStep(tester, 4);
    await starPhoto(tester, 3);
    expect(carDataOf(tester)['primary_image_index'], 3);

    // The star was written to the persisted step draft (the save does real
    // file copies first, so poll with a real-time budget).
    final sp = await SharedPreferences.getInstance();
    var persisted = <String>[];
    for (var i = 0; i < 200 && persisted.isEmpty; i++) {
      persisted = [
        for (final k in sp.getKeys())
          if ((sp.get(k)?.toString() ?? '').contains('"primaryImageIndex":3')) k,
      ];
      if (persisted.isEmpty) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    expect(persisted, isNotEmpty, reason: 'draft prefs must carry the cover');

    // Reopen the wizard from that draft (what resume-draft does).
    final paths = originals(tester);
    expect(paths, hasLength(4));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    PathProviderPlatform.instance = _FakeDocsPathProvider(tempDir.path);
    SellDraftMediaPersistence.debugResetMediaLifecycleForTest();
    await openSellDraftStep(
      tester,
      step: 0,
      carData: {
        ...sellCarDataThroughStep3(),
        'sell_wizard_v2': true,
        'images': paths,
        'original_images': paths,
        'primary_image_index': 3,
      },
    );
    await settle(tester);

    expect(carDataOf(tester)['primary_image_index'], 3);
    expect(starCount(tester), 1);
    expect(coverTileIndex(tester), 3, reason: 'the star is on photo 4 again');
    await finish(tester);
  });

  testWidgets('4. deleting the selected cover falls back to a valid cover', (
    tester,
  ) async {
    await openPhotosStep(tester, 5);
    await starPhoto(tester, 2);
    expect(coverTileIndex(tester), 2);

    await deletePhotoAt(tester, 2);

    expect(originals(tester), hasLength(4));
    final idx = carDataOf(tester)['primary_image_index'] as int;
    expect(idx, inInclusiveRange(0, 3), reason: 'cover index stays valid');
    expect(starCount(tester), 1, reason: 'exactly one cover remains');
    expect(declaredCovers(tester).where((c) => c), hasLength(1));
    await finish(tester);
  });

  testWidgets(
    '5. deleting a photo BEFORE the cover keeps the same photo as the cover',
    (tester) async {
      await openPhotosStep(tester, 5);
      await starPhoto(tester, 3);
      final coverPath = originals(tester)[3];

      await deletePhotoAt(tester, 0);

      final after = originals(tester);
      expect(after, hasLength(4));
      final idx = carDataOf(tester)['primary_image_index'] as int;
      expect(after[idx], coverPath, reason: 'same photo still the cover');
      expect(starCount(tester), 1);
      await finish(tester);
    },
  );
}
