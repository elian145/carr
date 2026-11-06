import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:car_listing_app/services/device_id_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore implements DeviceIdStore {
  _MemoryStore([this.value]);
  String? value;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(String v) async {
    writes++;
    value = v;
  }
}

class _BrokenStore implements DeviceIdStore {
  _BrokenStore({this.failRead = true, this.failWrite = true});
  final bool failRead;
  final bool failWrite;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('storage unavailable');
    return null;
  }

  @override
  Future<void> write(String v) async {
    writes++;
    if (failWrite) throw StateError('storage unavailable');
  }
}

class _HangingStore implements DeviceIdStore {
  final Completer<String?> never = Completer<String?>();
  @override
  Future<String?> read() => never.future;
  @override
  Future<void> write(String v) => never.future.then((_) {});
}

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
// kk/rate_identity.py::_DEVICE_ID_RE
final RegExp _backend = RegExp(r'^[A-Za-z0-9._:\-]{8,128}$');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F-12 DeviceIdService', () {
    test('generates a UUIDv4 once and persists it', () async {
      final store = _MemoryStore();
      final id = await DeviceIdService(store: store).getDeviceId();
      expect(_uuidV4.hasMatch(id), isTrue, reason: id);
      expect(store.value, id);
      expect(store.writes, 1);
    });

    test('id is stable across restarts (new service, same storage)', () async {
      final store = _MemoryStore();
      final first = await DeviceIdService(store: store).getDeviceId();
      for (var restart = 0; restart < 5; restart++) {
        final again = await DeviceIdService(store: store).getDeviceId();
        expect(again, first);
      }
      expect(store.writes, 1, reason: 'must not rewrite an existing id');
    });

    test('same instance never re-reads storage after the first load', () async {
      final store = _MemoryStore();
      final svc = DeviceIdService(store: store);
      final a = await svc.getDeviceId();
      final b = await svc.getDeviceId();
      expect(a, b);
      expect(svc.cachedId, a);
      expect(store.reads, 1);
    });

    test('concurrent first callers share one generation', () async {
      var generated = 0;
      final store = _MemoryStore();
      final svc = DeviceIdService(
        store: store,
        generator: () {
          generated++;
          return DeviceIdService.generateUuidV4();
        },
      );
      final ids = await Future.wait(List.generate(25, (_) => svc.getDeviceId()));
      expect(ids.toSet().length, 1);
      expect(generated, 1);
      expect(store.writes, 1);
    });

    test('generated ids are canonical UUIDv4 and satisfy the backend format', () {
      final seen = <String>{};
      for (var i = 0; i < 2000; i++) {
        final id = DeviceIdService.generateUuidV4();
        expect(id.length, 36);
        expect(_uuidV4.hasMatch(id), isTrue, reason: id);
        expect(_backend.hasMatch(id), isTrue, reason: id);
        expect(DeviceIdService.isValidDeviceId(id), isTrue);
        seen.add(id);
      }
      expect(seen.length, 2000, reason: 'random, no collisions');
    });

    test('UUID version and variant bits are set even for degenerate randomness', () {
      final zero = DeviceIdService.generateUuidV4(_ConstRandom(0));
      final ones = DeviceIdService.generateUuidV4(_ConstRandom(255));
      expect(zero, '00000000-0000-4000-8000-000000000000');
      expect(ones, 'ffffffff-ffff-4fff-bfff-ffffffffffff');
      expect(_uuidV4.hasMatch(ones), isTrue);
    });

    test('validation rejects anything the backend would ignore or that is not a UUID', () {
      for (final bad in <String?>[
        null,
        '',
        'short',
        'ABCDEFAB-ABCD-4ABC-8ABC-ABCDEFABCDEF', // upper-case: not canonical
        '12345678-1234-1234-1234-123456789012', // not v4
        '12345678-1234-4234-c234-123456789012', // bad variant
        'has space-1234-4234-8234-123456789012',
        'a' * 200,
      ]) {
        expect(DeviceIdService.isValidDeviceId(bad), isFalse, reason: '$bad');
      }
    });

    test('a corrupt or foreign stored value is replaced by a fresh UUID', () async {
      final store = _MemoryStore('not-a-uuid <script>');
      final id = await DeviceIdService(store: store).getDeviceId();
      expect(_uuidV4.hasMatch(id), isTrue);
      expect(store.value, id);
    });

    test('a generator returning garbage cannot leak an invalid id', () async {
      final id = await DeviceIdService(
        store: _MemoryStore(),
        generator: () => 'x',
      ).getDeviceId();
      expect(DeviceIdService.isValidDeviceId(id), isTrue);
    });

    test('storage read failure does not throw: ephemeral per-process id', () async {
      final store = _BrokenStore();
      final svc = DeviceIdService(store: store);
      final id = await svc.getDeviceId();
      expect(_uuidV4.hasMatch(id), isTrue);
      expect(await svc.getDeviceId(), id, reason: 'stable within the process');
      expect(store.writes, 0, reason: 'unreadable store is not written to');
      // a new process (new service) gets a different ephemeral id
      expect(await DeviceIdService(store: _BrokenStore()).getDeviceId(), isNot(id));
    });

    test('storage write failure still yields a usable id for this process', () async {
      final store = _BrokenStore(failRead: false, failWrite: true);
      final svc = DeviceIdService(store: store);
      final id = await svc.getDeviceId();
      expect(_uuidV4.hasMatch(id), isTrue);
      expect(await svc.getDeviceId(), id);
      expect(store.writes, 1);
    });

    test('a hanging store cannot block: times out into an ephemeral id', () async {
      final svc = DeviceIdService(
        store: _HangingStore(),
        storageTimeout: const Duration(milliseconds: 40),
      );
      final id = await svc.getDeviceId().timeout(const Duration(seconds: 2));
      expect(_uuidV4.hasMatch(id), isTrue);
    });

    test('SharedPreferences store: persisted under an app-private key, survives restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final first = await DeviceIdService().getDeviceId();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SharedPreferencesDeviceIdStore.key), first);
      expect(SharedPreferencesDeviceIdStore.key, 'carnet.install_id.v1');
      expect(await DeviceIdService().getDeviceId(), first);
    });

    test('"clear data / reinstall" (empty prefs) starts a new id', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final first = await DeviceIdService().getDeviceId();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final second = await DeviceIdService().getDeviceId();
      expect(second, isNot(first));
    });
  });

  group('F-12 privacy guards (source level)', () {
    final source = File('lib/services/device_id_service.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    test('no hardware / advertising / account identifiers are used', () {
      // Strip comments so documentation of what we DON'T use is allowed.
      final code = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n')
          .toLowerCase();
      for (final needle in <String>[
        'imei',
        'android_id',
        'androidid',
        'mac_address',
        'macaddress',
        'serial',
        'advertising',
        'idfa',
        'identifierforvendor',
        'device_info',
        'deviceinfo',
        'platform.operatingsystem',
        'phone_number',
        'phonenumber',
        'user_id',
        'userid',
        'package:flutter_secure_storage',
      ]) {
        expect(code.contains(needle), isFalse, reason: 'must not reference $needle');
      }
    });

    test('only dart:async / dart:math + shared_preferences are imported', () {
      final imports = RegExp(r"^import '([^']+)';", multiLine: true)
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();
      expect(imports, <String>{
        'dart:async',
        'dart:math',
        'package:shared_preferences/shared_preferences.dart',
      });
    });

    test('no hardware-id / tracking dependency was added to pubspec', () {
      for (final dep in <String>[
        'device_info_plus',
        'device_info:',
        'android_id',
        'platform_device_id',
        'advertising_id',
        'flutter_udid',
        'unique_identifier',
        'uuid:',
        'imei',
      ]) {
        expect(pubspec.contains(dep), isFalse, reason: 'pubspec must not contain $dep');
      }
    });

    test('the id is never logged', () {
      for (final f in <String>[
        'lib/services/device_id_service.dart',
        'lib/services/api/device_id_http_client.dart',
      ]) {
        final s = File(f).readAsStringSync();
        for (final log in <String>['print(', 'debugPrint(', 'log(', 'logNonFatal', 'developer.', 'AppLog']) {
          expect(s.contains(log), isFalse, reason: '$f must not call $log');
        }
      }
    });
  });
}

class _ConstRandom implements Random {
  _ConstRandom(this.value);
  final int value;
  @override
  bool nextBool() => value != 0;
  @override
  double nextDouble() => value / 256;
  @override
  int nextInt(int max) => value.clamp(0, max - 1);
}
