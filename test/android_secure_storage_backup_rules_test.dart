import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android Auto Backup configuration that keeps flutter_secure_storage
/// files out of backups.
///
/// Why this matters: `FlutterSecureStorage.xml` holds Tink keysets wrapped by an
/// Android Keystore master key. Keystore keys are never backed up or restored,
/// so a restored prefs file can no longer be decrypted and every cold start
/// logs `EncryptedSharedPreferences initialization failed`
/// (`AEADBadTagException`). Keep these rules in place -- and in sync with the
/// plugin's real file names -- or the failure comes back.
void main() {
  const secureFiles = <String>[
    'FlutterSecureStorage.xml', // EncryptedSharedPreferences + keysets
    'FlutterSecureKeyStorage.xml', // legacy RSA-wrapped AES key
  ];

  String read(String path) => File(path).readAsStringSync();

  /// `<exclude domain="sharedpref" path="X" />` entries inside [xml].
  Set<String> sharedPrefExcludes(String xml) {
    final re = RegExp(
      r'<exclude\s+domain="sharedpref"\s+path="([^"]+)"\s*/>',
    );
    return re.allMatches(xml).map((m) => m.group(1)!).toSet();
  }

  String section(String xml, String tag) {
    final m = RegExp('<$tag>([\\s\\S]*?)</$tag>').firstMatch(xml);
    expect(m, isNotNull, reason: '<$tag> section missing');
    return m!.group(1)!;
  }

  group('Android backup rules exclude secure storage', () {
    test('manifest points at our rules and overrides the SDK-injected ones', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      // Third-party SDKs (Airbridge) inject their own rules files; ours must win.
      final replace = RegExp(r'tools:replace="([^"]*)"')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .join(',');
      expect(replace, contains('android:fullBackupContent'));
      expect(replace, contains('android:dataExtractionRules'));
    });

    test('Android <= 11 rules (fullBackupContent)', () {
      final xml = read('android/app/src/main/res/xml/backup_rules.xml');
      final excludes = sharedPrefExcludes(xml);
      for (final f in secureFiles) {
        expect(excludes, contains(f), reason: '$f must not be backed up');
      }
    });

    test('Android 12+ rules exclude from cloud backup AND device transfer', () {
      final xml = read('android/app/src/main/res/xml/data_extraction_rules.xml');
      for (final tag in const ['cloud-backup', 'device-transfer']) {
        final excludes = sharedPrefExcludes(section(xml, tag));
        for (final f in secureFiles) {
          expect(excludes, contains(f), reason: '$f must be excluded in <$tag>');
        }
      }
    });

    test('previously injected Airbridge exclusions are preserved', () {
      const airbridgePrefs = <String>{
        'airbridge-internal',
        'airbridge-install',
        'airbridge-user-info',
        'airbridge-user-alias',
        'airbridge-user-attributes',
        'airbridge-device-alias',
      };
      final legacy = read('android/app/src/main/res/xml/backup_rules.xml');
      expect(sharedPrefExcludes(legacy), containsAll(airbridgePrefs));
      final modern =
          read('android/app/src/main/res/xml/data_extraction_rules.xml');
      for (final tag in const ['cloud-backup', 'device-transfer']) {
        final s = section(modern, tag);
        expect(sharedPrefExcludes(s), containsAll(airbridgePrefs));
        expect(s, contains('domain="database" path="airbridge.db"'));
      }
    });

    test('plugin version still matches the file names excluded above', () {
      // The excluded names come from flutter_secure_storage 9.2.x
      // (SHARED_PREFERENCES_NAME = "FlutterSecureStorage",
      // StorageCipher18Implementation = "FlutterSecureKeyStorage").
      // If the plugin is upgraded, re-verify them before bumping this check.
      final lock = read('pubspec.lock');
      final m = RegExp(
        r'\n  flutter_secure_storage:[^\n]*\n(?:[ \t]+[^\n]*\n)*?[ \t]+version: "([^"]+)"',
      ).firstMatch(lock);
      expect(m, isNotNull);
      expect(
        m!.group(1)!,
        startsWith('9.2.'),
        reason: 'flutter_secure_storage changed: re-check the Android '
            'shared_prefs file names in backup_rules.xml / '
            'data_extraction_rules.xml (and SecureStorageRepair.kt).',
      );
    });
  });
}
