import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/connectivity_service.dart';

/// Deterministic fake for [ConnectivityPlatform.instance].
///
/// B-08 tests need to force connectivity_plus success/failure/stream-error
/// scenarios independent of whatever real platform channel (or absence of
/// one) happens to be available under `flutter test`.
class _FakeConnectivityPlatform extends ConnectivityPlatform {
  /// Result returned by [checkConnectivity]. Ignored if [checkError] is set.
  List<ConnectivityResult>? checkResult;

  /// If set, [checkConnectivity] throws this instead of returning a result —
  /// simulates a plugin/check failure (the B-08 regression case).
  Object? checkError;

  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    final error = checkError;
    if (error != null) {
      throw error;
    }
    return checkResult ?? const [ConnectivityResult.wifi];
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> results) => _controller.add(results);

  void emitError(Object error) => _controller.addError(error);

  Future<void> close() => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityPlatform originalPlatform;
  late _FakeConnectivityPlatform fakePlatform;

  setUp(() async {
    // ConnectivityService is a singleton with shared `_started`/`isOnline`
    // state — reset it before installing the fake platform for this test so
    // tests are independent of each other and of execution order.
    await ConnectivityService.instance.dispose();
    ConnectivityService.instance.isOnline.value = true;

    originalPlatform = ConnectivityPlatform.instance;
    fakePlatform = _FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await ConnectivityService.instance.dispose();
    ConnectivityService.instance.isOnline.value = true;
    await fakePlatform.close();
    ConnectivityPlatform.instance = originalPlatform;
  });

  test('a connected interface result reports online', () async {
    fakePlatform.checkResult = [ConnectivityResult.wifi];

    await ConnectivityService.instance.start();

    expect(ConnectivityService.instance.isOnline.value, isTrue);
  });

  test('ConnectivityResult.none reports offline', () async {
    fakePlatform.checkResult = [ConnectivityResult.none];

    await ConnectivityService.instance.start();

    expect(ConnectivityService.instance.isOnline.value, isFalse);
  });

  test(
    'B-08 regression: initial plugin/check failure fails conservatively '
    'toward offline instead of defaulting to online',
    () async {
      fakePlatform.checkError = Exception('simulated plugin failure');

      await ConnectivityService.instance.start();

      expect(ConnectivityService.instance.isOnline.value, isFalse);
    },
  );

  test(
    'stream update reporting no connectivity switches to offline',
    () async {
      fakePlatform.checkResult = [ConnectivityResult.wifi];
      await ConnectivityService.instance.start();
      expect(ConnectivityService.instance.isOnline.value, isTrue);

      fakePlatform.emit([ConnectivityResult.none]);
      await pumpEventQueue();

      expect(ConnectivityService.instance.isOnline.value, isFalse);
    },
  );

  test(
    'stream update reporting connectivity again switches back to online',
    () async {
      fakePlatform.checkResult = [ConnectivityResult.wifi];
      await ConnectivityService.instance.start();
      fakePlatform.emit([ConnectivityResult.none]);
      await pumpEventQueue();
      expect(ConnectivityService.instance.isOnline.value, isFalse);

      fakePlatform.emit([ConnectivityResult.wifi]);
      await pumpEventQueue();

      expect(ConnectivityService.instance.isOnline.value, isTrue);
    },
  );

  test(
    'B-08 regression: a stream/update error does not force isOnline back '
    'to true as a fallback',
    () async {
      fakePlatform.checkResult = [ConnectivityResult.none];
      await ConnectivityService.instance.start();
      expect(ConnectivityService.instance.isOnline.value, isFalse);

      fakePlatform.emitError(Exception('simulated stream failure'));
      await pumpEventQueue();

      expect(ConnectivityService.instance.isOnline.value, isFalse);
    },
  );

  test(
    'existing isOnline ValueNotifier listener API remains intact',
    () async {
      fakePlatform.checkResult = [ConnectivityResult.wifi];
      final seenValues = <bool>[];
      void listener() {
        seenValues.add(ConnectivityService.instance.isOnline.value);
      }

      ConnectivityService.instance.isOnline.addListener(listener);
      try {
        await ConnectivityService.instance.start();
        fakePlatform.emit([ConnectivityResult.none]);
        await pumpEventQueue();
        fakePlatform.emit([ConnectivityResult.wifi]);
        await pumpEventQueue();
      } finally {
        ConnectivityService.instance.isOnline.removeListener(listener);
      }

      expect(seenValues, containsAllInOrder([false, true]));
    },
  );
}
