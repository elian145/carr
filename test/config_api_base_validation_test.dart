// F-02: unit tests for the pure API_BASE release-build validation logic.
//
// These tests exercise `validateReleaseApiBase()` directly — they do NOT
// depend on `kReleaseMode` (which is always false under `flutter test`) so
// they can actually cover the release-mode rules that `effectiveApiBase()`
// enforces at runtime in a real release build.
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/config.dart';

void main() {
  group('validateReleaseApiBase', () {
    test('valid HTTPS is accepted for normal production (no escape hatches)', () {
      final result = validateReleaseApiBase('https://carr-5hrm.onrender.com');
      expect(result.status, ApiBaseValidationStatus.valid);
      expect(result.isValid, isTrue);
      expect(result.base, 'https://carr-5hrm.onrender.com');
    });

    test('missing (empty string) value is rejected', () {
      final result = validateReleaseApiBase('');
      expect(result.status, ApiBaseValidationStatus.missing);
      expect(result.isValid, isFalse);
    });

    test('missing (whitespace-only) value is rejected as missing, not insecure', () {
      final result = validateReleaseApiBase('   ');
      expect(result.status, ApiBaseValidationStatus.missing);
    });

    test('HTTP is rejected for normal production (no escape hatches enabled)', () {
      final result = validateReleaseApiBase('http://carr-5hrm.onrender.com');
      expect(result.status, ApiBaseValidationStatus.insecureHttp);
      expect(result.isValid, isFalse);
    });

    test('non-HTTPS/HTTP scheme is rejected as insecure (not treated as missing)', () {
      final result = validateReleaseApiBase('ftp://example.com');
      expect(result.status, ApiBaseValidationStatus.insecureHttp);
    });

    test('iOS sideload HTTP escape hatch allows http:// when enabled', () {
      final result = validateReleaseApiBase(
        'http://192.168.1.10:5003',
        allowIosSideloadHttp: true,
      );
      expect(result.status, ApiBaseValidationStatus.valid);
      expect(result.base, 'http://192.168.1.10:5003');
    });

    test('iOS sideload escape hatch does NOT allow http:// when disabled', () {
      final result = validateReleaseApiBase(
        'http://192.168.1.10:5003',
        allowIosSideloadHttp: false,
      );
      expect(result.status, ApiBaseValidationStatus.insecureHttp);
    });

    test('Android insecure-HTTP escape hatch allows http:// when enabled', () {
      final result = validateReleaseApiBase(
        'http://10.0.2.2:5003',
        allowAndroidInsecureHttp: true,
      );
      expect(result.status, ApiBaseValidationStatus.valid);
      expect(result.base, 'http://10.0.2.2:5003');
    });

    test('Android insecure-HTTP escape hatch does NOT allow http:// when disabled', () {
      final result = validateReleaseApiBase(
        'http://10.0.2.2:5003',
        allowAndroidInsecureHttp: false,
      );
      expect(result.status, ApiBaseValidationStatus.insecureHttp);
    });

    test('HTTPS is still accepted even when an escape hatch flag is true', () {
      final result = validateReleaseApiBase(
        'https://carr-5hrm.onrender.com',
        allowIosSideloadHttp: true,
        allowAndroidInsecureHttp: true,
      );
      expect(result.status, ApiBaseValidationStatus.valid);
    });

    test('escape hatches only apply to http:// — a non-http scheme is still insecure', () {
      final result = validateReleaseApiBase(
        'ftp://example.com',
        allowIosSideloadHttp: true,
        allowAndroidInsecureHttp: true,
      );
      expect(result.status, ApiBaseValidationStatus.insecureHttp);
    });

    test('leading/trailing whitespace is trimmed before validation', () {
      final result = validateReleaseApiBase('  https://carr-5hrm.onrender.com  ');
      expect(result.status, ApiBaseValidationStatus.valid);
      expect(result.base, 'https://carr-5hrm.onrender.com');
    });
  });

  group('effectiveApiBase debug/profile fallback (unchanged by this refactor)', () {
    // `flutter test` always runs with kReleaseMode == false, so these calls
    // exercise the *same* debug-fallback branch of effectiveApiBase() that
    // existed before F-02 — this refactor did not touch that branch at all.
    setUp(() {
      // Ensure no runtime override leaks between tests (allowed in
      // debug/test mode by allowRuntimeApiBaseOverride()).
      setRuntimeApiBaseOverride(null);
    });

    tearDown(() {
      setRuntimeApiBaseOverride(null);
    });

    test('empty API_BASE still falls back to a local dev default (no throw)', () {
      // On whichever host OS runs this test, effectiveApiBase() must not
      // throw in debug/test mode even though base is empty — that is the
      // pre-existing (and still current) release-only fail-fast behavior.
      expect(() => effectiveApiBase(), returnsNormally);
      final base = effectiveApiBase();
      expect(base, isNotEmpty);
      expect(base.startsWith('http://'), isTrue);
    });

    test('a runtime override is still honored in debug/test mode', () {
      setRuntimeApiBaseOverride('http://example.test:5003');
      expect(effectiveApiBase(), 'http://example.test:5003');
    });
  });
}
