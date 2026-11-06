import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Where the install id lives. Abstracted so tests can use an in-memory fake
/// (or one that throws) without a platform channel.
abstract class DeviceIdStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// Production store: the app's existing `shared_preferences` dependency.
///
/// Deliberately NOT `flutter_secure_storage`: the id is not a secret, and on
/// iOS the Keychain survives an uninstall/reinstall, which would make the id
/// outlive the install (we want a reinstall / "clear data" to start a fresh
/// id). `shared_preferences` data is removed with the app on both platforms.
/// (Android Auto Backup can restore it onto the same user's new device; the
/// value is a random number, so that only keeps one person's limiter bucket
/// stable, it identifies nothing else.)
class SharedPreferencesDeviceIdStore implements DeviceIdStore {
  const SharedPreferencesDeviceIdStore();

  static const String key = 'carnet.install_id.v1';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}

/// F-12: a random, per-installation id sent as `X-Device-Id` so the backend can
/// apply a per-install rate limit next to its per-phone / per-account / per-IP
/// limits (many subscribers share one carrier-grade-NAT IP in Iraq).
///
/// Privacy / security properties (keep when changing this file):
///  * A random UUIDv4 from a CSPRNG, generated on first use and persisted
///    locally. It is NOT derived from anything about the hardware or the user:
///    no IMEI, Android ID, MAC address, serial number, advertising id,
///    vendor id, phone number or account id. It is app-private (not shared
///    with other apps or SDKs) and disappears on uninstall / "clear data".
///  * It is only ever used for rate limiting. The backend never logs it, never
///    stores it with an account and never uses it for analytics; this class
///    never logs it either.
///  * It is CLIENT-ASSERTED. The server must never treat it as proof of
///    identity or as an authentication factor, and rotating it (reinstalling,
///    clearing data, or a modified client sending random ids) must not bypass
///    anything: the backend always also applies per-phone / per-account and
///    per-IP ceilings (see `kk/rate_identity.py`).
///  * Storage failure NEVER blocks a request. If the store cannot be read (or
///    times out) the service falls back to an EPHEMERAL per-process random id
///    held in memory only (it dies with the process and is never retried
///    against storage in this process, so a broken store cannot stall
///    requests). If only the write fails, that fresh id is used for this
///    process and a new one is generated next launch.
///
/// Format: lower-case UUIDv4 (36 chars, `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`).
/// The backend accepts `^[A-Za-z0-9._:-]{8,128}$` (`_DEVICE_ID_RE` in
/// `kk/rate_identity.py`) and silently IGNORES anything else; a UUID always
/// satisfies it. [isValidDeviceId] enforces both so the two stay consistent.
class DeviceIdService {
  DeviceIdService({
    DeviceIdStore? store,
    String Function()? generator,
    Duration storageTimeout = const Duration(seconds: 2),
  }) : _store = store ?? const SharedPreferencesDeviceIdStore(),
       _generator = generator ?? generateUuidV4,
       _storageTimeout = storageTimeout;

  /// Process-wide instance used by [ApiService]'s HTTP client.
  static final DeviceIdService instance = DeviceIdService();

  final DeviceIdStore _store;
  final String Function() _generator;
  final Duration _storageTimeout;

  String? _cached;
  Future<String>? _inFlight;

  /// The backend's accepted alphabet/length (mirror of `_DEVICE_ID_RE`).
  static final RegExp _backendPattern = RegExp(r'^[A-Za-z0-9._:\-]{8,128}$');
  static final RegExp _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// True for a canonical lower-case UUIDv4 that the backend will also accept.
  static bool isValidDeviceId(String? value) =>
      value != null && _uuidV4.hasMatch(value) && _backendPattern.hasMatch(value);

  /// The id if it has already been loaded in this process, else null.
  String? get cachedId => _cached;

  /// A random (version 4, RFC 4122 variant) UUID from a CSPRNG.
  static String generateUuidV4([Random? random]) {
    Random rng;
    if (random != null) {
      rng = random;
    } else {
      try {
        rng = Random.secure();
      } catch (_) {
        rng = Random();
      }
    }
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    String hex(int from, int to) => bytes
        .sublist(from, to)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  /// The installation id. Never throws and never returns null: concurrent
  /// first callers share one load, so the id is generated at most once.
  Future<String> getDeviceId() {
    final cached = _cached;
    if (cached != null) return Future<String>.value(cached);
    return _inFlight ??= _load();
  }

  Future<String> _load() async {
    String? stored;
    var storageReadable = true;
    try {
      stored = await _store.read().timeout(_storageTimeout);
    } catch (_) {
      storageReadable = false; // storage broken/hung: ephemeral id below
    }
    if (isValidDeviceId(stored)) {
      return _cached = stored!;
    }

    // First run, or a corrupt/foreign stored value: mint a fresh id.
    var fresh = _generator();
    if (!isValidDeviceId(fresh)) fresh = generateUuidV4();
    if (storageReadable) {
      try {
        await _store.write(fresh).timeout(_storageTimeout);
      } catch (_) {
        // Could not persist: still usable for this process (ephemeral).
      }
    }
    return _cached = fresh;
  }
}
