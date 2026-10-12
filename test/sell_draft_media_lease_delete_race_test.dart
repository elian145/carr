// Lease-safe draft media deletion.
//
// Physical folder delete must NEVER run while a read lease is held — even
// after the simulated 90s wall clock — and must complete event-driven when
// the last lease is released (empty-draft UI path stays non-blocking).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:car_listing_app/services/ai_service.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsRoot;
  late PathProviderPlatform previousProvider;

  setUp(() async {
    previousProvider = PathProviderPlatform.instance;
    docsRoot = await Directory.systemTemp.createTemp('sell_media_lease_');
    PathProviderPlatform.instance = _FakeDocsPathProvider(docsRoot.path);
    // Simulated "90s" — tests must not wait a real minute.
    SellDraftMediaPersistence.deleteLeaseWaitTimeout =
        const Duration(milliseconds: 80);
    SellDraftMediaPersistence.debugBeforeCopyOverride = null;
  });

  tearDown(() async {
    SellDraftMediaPersistence.debugBeforeCopyOverride = null;
    await SellDraftMediaPersistence.debugAwaitPendingFolderDeletes();
    PathProviderPlatform.instance = previousProvider;
    SellDraftMediaPersistence.deleteLeaseWaitTimeout =
        const Duration(seconds: 90);
    ApiService.testHttpClient = null;
    await ApiService.clearTokens();
    if (await docsRoot.exists()) {
      await docsRoot.delete(recursive: true);
    }
  });

  Future<File> markerInDraft(String draftId, {String name = 'listing.jpg'}) async {
    final dir = await SellDraftMediaPersistence.draftDirectory(draftId);
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
    return f;
  }

  test('draftIdFromMediaPath extracts id under sell_draft_media', () {
    expect(
      SellDraftMediaPersistence.draftIdFromMediaPath(
        p.join('x', 'sell_draft_media', 'draft_abc', 'listing_1.jpg'),
      ),
      'draft_abc',
    );
    expect(
      SellDraftMediaPersistence.draftIdFromMediaPath(
        'https://cdn.example/car.jpg',
      ),
      isNull,
    );
  });

  test(
    'H: deleteLocalDraftFolder returns immediately while a lease is held',
    () async {
      const draftId = 'ui_responsive_draft';
      final marker = await markerInDraft(draftId);
      final dir = marker.parent;

      final release = Completer<void>();
      final leaseStarted = Completer<void>();
      final leaseFuture = SellDraftMediaPersistence.withLocalMediaLeases(
        [marker.path],
        () async {
          leaseStarted.complete();
          await release.future;
          return 1;
        },
      );
      await leaseStarted.future;

      final sw = Stopwatch()..start();
      await SellDraftMediaPersistence.deleteLocalDraftFolder(draftId);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(200));
      expect(await dir.exists(), isTrue);

      release.complete();
      await leaseFuture;
      await SellDraftMediaPersistence.debugAwaitPendingFolderDeletes(draftId);
      expect(await dir.exists(), isFalse);
    },
  );

  test(
    'A: hold lease past simulated 90s timeout — folder must still exist',
    () async {
      const draftId = 'timeout_hold';
      final marker = await markerInDraft(draftId);
      final dir = marker.parent;

      final release = Completer<void>();
      final leaseFuture = SellDraftMediaPersistence.withLocalMediaLeases(
        [marker.path],
        () async {
          await release.future;
          return 1;
        },
      );

      await SellDraftMediaPersistence.deleteLocalDraftFolder(draftId);
      await Future<void>.delayed(
        SellDraftMediaPersistence.deleteLeaseWaitTimeout * 2,
      );

      expect(
        await dir.exists(),
        isTrue,
        reason: 'must never force-delete while a lease is held',
      );
      expect(await marker.exists(), isTrue);
      expect(SellDraftMediaPersistence.debugFolderDeleteRequested(draftId), isTrue);

      release.complete();
      await leaseFuture;
      await SellDraftMediaPersistence.debugAwaitPendingFolderDeletes(draftId);
      // B: release → folder eventually disappears
      expect(await dir.exists(), isFalse);
    },
  );

  test(
    'B/D: multiple readers — delete only after ALL release',
    () async {
      const draftId = 'multi_reader';
      final marker = await markerInDraft(draftId);
      final dir = marker.parent;

      final release1 = Completer<void>();
      final release2 = Completer<void>();
      final l1 = SellDraftMediaPersistence.withLocalMediaLeases(
        [marker.path],
        () async {
          await release1.future;
          return 1;
        },
      );
      final l2 = SellDraftMediaPersistence.withLocalMediaLeases(
        [marker.path],
        () async {
          await release2.future;
          return 2;
        },
      );
      expect(SellDraftMediaPersistence.debugReadLeaseCount(draftId), 2);

      await SellDraftMediaPersistence.deleteLocalDraftFolder(draftId);
      release1.complete();
      await l1;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(await dir.exists(), isTrue, reason: 'one reader still active');

      release2.complete();
      await l2;
      await SellDraftMediaPersistence.debugAwaitPendingFolderDeletes(draftId);
      expect(await dir.exists(), isFalse);
    },
  );

  test(
    'C: slow upload past timeout completes without file loss',
    () async {
      const draftId = 'slow_upload';
      final marker = await markerInDraft(draftId);
      var bytesRead = 0;

      final release = Completer<void>();
      final upload = SellDraftMediaPersistence.withLocalMediaLeases(
        [marker.path],
        () async {
          // Simulate a multipart stream that outlives the old 90s cutoff.
          await Future<void>.delayed(
            SellDraftMediaPersistence.deleteLeaseWaitTimeout * 2,
          );
          bytesRead = await File(marker.path).length();
          await release.future;
          return bytesRead;
        },
      );

      await SellDraftMediaPersistence.deleteLocalDraftFolder(draftId);
      await Future<void>.delayed(
        SellDraftMediaPersistence.deleteLeaseWaitTimeout,
      );
      expect(await marker.exists(), isTrue);

      release.complete();
      final n = await upload;
      expect(n, greaterThan(0));
      await SellDraftMediaPersistence.debugAwaitPendingFolderDeletes(draftId);
      expect(await marker.parent.exists(), isFalse);
    },
  );

  test('E: Draft A lease does not block Draft B delete', () async {
    const draftA = 'iso_a';
    const draftB = 'iso_b';
    final fileA = await markerInDraft(draftA, name: 'a.jpg');
    final fileB = await markerInDraft(draftB, name: 'b.jpg');
    final dirA = fileA.parent;
    final dirB = fileB.parent;

    final releaseA = Completer<void>();
    final leaseA = SellDraftMediaPersistence.withLocalMediaLeases(
      [fileA.path],
      () async {
        await releaseA.future;
        return 1;
      },
    );

    await SellDraftMediaPersistence.deleteLocalDraftFolder(draftB);
    await SellDraftMediaPersistence.debugAwaitPendingFolderDeletes(draftB);
    expect(await dirB.exists(), isFalse);
    expect(await fileA.exists(), isTrue);
    expect(SellDraftMediaPersistence.debugReadLeaseCount(draftA), 1);

    releaseA.complete();
    await leaseA;
    await SellDraftMediaPersistence.deleteLocalDraftFolder(draftA);
    await SellDraftMediaPersistence.debugAwaitPendingFolderDeletes(draftA);
    expect(await dirA.exists(), isFalse);
  });

  test(
    'F: concurrent persist + lease + delete — no deadlock / no mid-copy delete',
    () async {
      const draftId = 'deadlock_draft';
      final src = File(p.join(docsRoot.path, 'deadlock_src.jpg'))
        ..writeAsBytesSync(List<int>.filled(2048, 0x42));

      final copyGate = Completer<void>();
      final leaseGate = Completer<void>();
      var copyEntered = false;
      SellDraftMediaPersistence.debugBeforeCopyOverride = (_) async {
        copyEntered = true;
        await copyGate.future;
      };

      final persistFuture = SellDraftMediaPersistence.persistDynamicMediaList(
        [src.path],
        draftId: draftId,
        namePrefix: 'listing',
      );
      for (var i = 0; i < 50 && !copyEntered; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(copyEntered, isTrue);

      final marker = await markerInDraft(draftId, name: 'lease_marker.jpg');
      final leaseFuture = SellDraftMediaPersistence.withLocalMediaLeases(
        [marker.path],
        () async {
          await leaseGate.future;
          return true;
        },
      );

      await SellDraftMediaPersistence.deleteLocalDraftFolder(draftId);

      copyGate.complete();
      leaseGate.complete();

      await Future.any([
        Future.wait([
          persistFuture,
          leaseFuture,
          SellDraftMediaPersistence.debugAwaitPendingFolderDeletes(draftId),
        ]),
        Future<void>.delayed(const Duration(seconds: 3)).then(
          (_) => fail('deadlock: persist/lease/delete did not finish in 3s'),
        ),
      ]);

      expect(SellDraftMediaPersistence.debugReadLeaseCount(draftId), 0);
    },
  );

  group('G: withLocalMediaLeases / enqueueCarImagesAsync release leases', () {
    Future<File> durableJpeg(String draftId) => markerInDraft(draftId);

    setUp(() async {
      await ApiService.setTokens(
        accessToken: 'lease_test_token',
        refreshToken: 'lease_test_refresh',
      );
    });

    test('releases lease after successful enqueue', () async {
      const draftId = 'lease_ok';
      final file = await durableJpeg(draftId);
      ApiService.testHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'job_ids': ['job-1'],
          }),
          202,
          headers: {'content-type': 'application/json'},
        );
      });

      final ids = await AiService.enqueueCarImagesAsync([XFile(file.path)]);
      expect(ids, ['job-1']);
      expect(SellDraftMediaPersistence.debugReadLeaseCount(draftId), 0);
    });

    test('releases lease after HTTP 502', () async {
      const draftId = 'lease_502';
      final file = await durableJpeg(draftId);
      ApiService.testHttpClient = MockClient((request) async {
        return http.Response('bad gateway', 502);
      });

      final ids = await AiService.enqueueCarImagesAsync([XFile(file.path)]);
      expect(ids, isNull);
      expect(SellDraftMediaPersistence.debugReadLeaseCount(draftId), 0);
    });

    test('releases lease after timeout', () async {
      const draftId = 'lease_timeout';
      final file = await durableJpeg(draftId);
      ApiService.testHttpClient = MockClient((request) async {
        throw TimeoutException('Enqueue images timed out');
      });

      await expectLater(
        AiService.enqueueCarImagesAsync([XFile(file.path)]),
        throwsA(isA<TimeoutException>()),
      );
      expect(SellDraftMediaPersistence.debugReadLeaseCount(draftId), 0);
    });

    test('releases lease after file-read exception', () async {
      const draftId = 'lease_missing';
      final missing = p.join(
        docsRoot.path,
        'sell_draft_media',
        draftId,
        'gone.jpg',
      );
      await Directory(p.dirname(missing)).create(recursive: true);

      await expectLater(
        AiService.enqueueCarImagesAsync([XFile(missing)]),
        throwsA(anything),
      );
      expect(SellDraftMediaPersistence.debugReadLeaseCount(draftId), 0);
    });

    test('releases lease when action throws (cancel-equivalent)', () async {
      const draftId = 'lease_cancel';
      final file = await durableJpeg(draftId);
      await expectLater(
        SellDraftMediaPersistence.withLocalMediaLeases(
          [file.path],
          () async {
            expect(SellDraftMediaPersistence.debugReadLeaseCount(draftId), 1);
            throw StateError('cancelled');
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(SellDraftMediaPersistence.debugReadLeaseCount(draftId), 0);
    });
  });
}
