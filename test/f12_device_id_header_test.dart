import 'dart:convert';

import 'package:car_listing_app/services/api/device_id_http_client.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/device_id_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore implements DeviceIdStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
}

class _BrokenStore implements DeviceIdStore {
  @override
  Future<String?> read() async => throw StateError('storage unavailable');
  @override
  Future<void> write(String v) async => throw StateError('storage unavailable');
}

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.BaseRequest> seen;
  late http.Client? originalClient;

  http.Response ok(http.Request r) => http.Response(
    jsonEncode(<String, dynamic>{
      'message': 'ok',
      'access_token': 'new-access',
      'refresh_token': 'new-refresh',
    }),
    200,
    headers: {'content-type': 'application/json'},
  );

  setUp(() async {
    // Token persistence uses flutter_secure_storage; answer its channel so the
    // login/phone-verify paths run quietly (no platform plugin in unit tests).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ApiService.clearTokens();
    seen = <http.BaseRequest>[];
    originalClient = ApiService.boundTestHttpClient;
    ApiService.testHttpClient = MockClient((request) async {
      seen.add(request);
      return ok(request);
    });
  });

  tearDown(() {
    ApiService.testDeviceIdService = null;
    ApiService.testHttpClient = originalClient;
  });

  String? headerOf(http.BaseRequest r) => r.headers['X-Device-Id'] ?? r.headers['x-device-id'];

  group('F-12 X-Device-Id on the real ApiService client path', () {
    test('every auth entry point carries the same persisted install id', () async {
      final store = _MemoryStore();
      final svc = DeviceIdService(store: store);
      ApiService.testDeviceIdService = svc;

      await ApiService.login('user', 'pw');
      await ApiService.phoneStart(phoneNumber: '07701234567');
      await ApiService.phoneVerify(phoneNumber: '07701234567', code: '123456');
      await ApiService.sendPhoneVerificationCode('07701234567');
      await ApiService.sendOtpLegacy(phone: '07701234567');
      await ApiService.verifyPhone('07701234567', '123456');
      await ApiService.signupLegacy(<String, dynamic>{'phone': '07701234567'});
      await ApiService.forgotPassword('07701234567');
      await ApiService.resetPassword('123456789012', 'Str0ng!Passw0rd');
      await ApiService.verifyEmail('tok');
      // refresh: stored refresh token -> POST /auth/refresh
      await ApiService.setTokens(accessToken: 'a', refreshToken: 'r');
      final refreshed = await ApiService.refreshAccessTokenForSession(
        ApiService.captureSession(authenticated: true),
      );
      expect(refreshed, isTrue);

      final paths = seen.map((r) => r.url.path).toList();
      for (final expected in <String>[
        '/api/auth/login',
        '/api/auth/phone/start',
        '/api/auth/phone/verify',
        '/api/auth/send-verification',
        '/api/auth/send_otp',
        '/api/auth/verify-phone',
        '/api/auth/signup',
        '/api/auth/forgot-password',
        '/api/auth/reset-password',
        '/api/auth/verify-email',
        '/api/auth/refresh',
      ]) {
        expect(paths.any((p) => p.endsWith(expected.replaceFirst('/api', ''))), isTrue, reason: 'missing $expected in $paths');
      }

      final ids = seen.map(headerOf).toSet();
      expect(ids.length, 1, reason: 'one install id for every request: $ids');
      final id = ids.single;
      expect(id, isNotNull);
      expect(_uuidV4.hasMatch(id!), isTrue, reason: id);
      expect(store.value, id, reason: 'persisted exactly what was sent');
    });

    test('authenticated requests also carry it, next to Authorization', () async {
      ApiService.testDeviceIdService = DeviceIdService(store: _MemoryStore());
      await ApiService.setTokens(accessToken: 'access', refreshToken: 'refresh');
      await ApiService.getHttp(
        Uri.parse('${ApiService.baseUrl}/auth/me'),
        headers: ApiService.defaultHeaders(includeAuth: true),
      );
      final r = seen.single;
      expect(_uuidV4.hasMatch(headerOf(r)!), isTrue);
      expect(r.headers['Authorization'], 'Bearer access');
    });

    test('the id is stable across a simulated app restart', () async {
      final store = _MemoryStore();
      ApiService.testDeviceIdService = DeviceIdService(store: store);
      await ApiService.login('u', 'p');
      ApiService.testDeviceIdService = DeviceIdService(store: store); // "restart"
      await ApiService.login('u', 'p');
      expect(_uuidV4.hasMatch(headerOf(seen[0])!), isTrue);
      expect(headerOf(seen[0]), headerOf(seen[1]));
    });

    test('storage failure never breaks the request (ephemeral id is sent)', () async {
      ApiService.testDeviceIdService = DeviceIdService(store: _BrokenStore());
      final data = await ApiService.login('u', 'p');
      expect(data['message'], 'ok');
      final id = headerOf(seen.single);
      expect(id, isNotNull);
      expect(_uuidV4.hasMatch(id!), isTrue);
    });

    test('a failing id service sends the request WITHOUT the header', () async {
      final client = DeviceIdHttpClient(
        MockClient((request) async {
          seen.add(request);
          return ok(request);
        }),
        service: _ThrowingService(),
        isFirstParty: (_) => true,
      );
      final res = await client.post(Uri.parse('https://api.example.test/api/auth/login'), body: '{}');
      expect(res.statusCode, 200);
      expect(headerOf(seen.single), isNull);
    });

    test('third-party hosts never receive the install id', () async {
      ApiService.testDeviceIdService = DeviceIdService(store: _MemoryStore());
      await ApiService.getHttp(Uri.parse('https://cdn.example.org/asset.json'));
      expect(seen.single.url.host, 'cdn.example.org');
      expect(headerOf(seen.single), isNull);
    });

    test('an explicit X-Device-Id on the request is not overwritten', () async {
      ApiService.testDeviceIdService = DeviceIdService(store: _MemoryStore());
      await ApiService.getHttp(
        Uri.parse('${ApiService.baseUrl}/auth/me'),
        headers: <String, String>{'x-device-id': 'custom-device-0001'},
      );
      expect(headerOf(seen.single), 'custom-device-0001');
    });

    test('without the opt-in hook a bound test client is left untouched', () async {
      await ApiService.login('u', 'p');
      expect(headerOf(seen.single), isNull);
    });

    test('production client (no test client bound) is the device-id wrapper', () {
      ApiService.testHttpClient = null;
      expect(ApiService.effectiveHttpClient, isA<DeviceIdHttpClient>());
      // cached wrapper, not re-created per request
      expect(identical(ApiService.effectiveHttpClient, ApiService.effectiveHttpClient), isTrue);
    });

    test('recycling the production client keeps the header on the new client', () {
      ApiService.testHttpClient = null;
      final before = ApiService.effectiveHttpClient;
      ApiService.recycleProductionHttpClient();
      final after = ApiService.effectiveHttpClient;
      expect(after, isA<DeviceIdHttpClient>());
      expect(identical(before, after), isFalse);
    });

    test('request body/headers other than X-Device-Id are unchanged', () async {
      ApiService.testDeviceIdService = DeviceIdService(store: _MemoryStore());
      await ApiService.login('user', 'pw');
      final r = seen.single as http.Request;
      expect(jsonDecode(r.body), <String, dynamic>{'username': 'user', 'password': 'pw'});
      expect(r.headers['Content-Type'], contains('application/json'));
      expect(r.headers.containsKey('Accept-Language'), isTrue);
    });
  });
}

class _ThrowingService extends DeviceIdService {
  @override
  String? get cachedId => null;
  @override
  Future<String> getDeviceId() => Future<String>.error(StateError('boom'));
}
