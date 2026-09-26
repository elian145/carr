// Localization coverage for the Sell-video compression feature (real-device
// evidence: a 6s .mov at 112,329,351 bytes was rejected by the backend's
// exact 100MB limit -- see `lib/features/sell/sell_video_compression.dart`).
//
// Three user-visible strings were added:
//   - sellPreparingVideo               ("Preparing video…" overlay while
//                                        compressing, before durable
//                                        persistence/upload begins)
//   - sellVideoCompressionFailed       (compression failed -> original kept,
//                                        oversized upload never happens)
//   - sellVideoTooLargeAfterCompression (compressed output STILL exceeds the
//                                        backend limit -> exact required
//                                        wording: "Video is too large.
//                                        Please choose a shorter video.")
//
// This test asserts all three keys exist with non-empty values in EVERY
// required locale's `.arb` source (en/ar/ku) -- not just the default locale
// -- and separately (via `AppLocalizations`) that the generated getters
// actually resolve to those exact source strings, so a future `flutter
// gen-l10n` regeneration or a hand-edit can't silently drop a locale.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/l10n/app_localizations_ar.dart';
import 'package:car_listing_app/l10n/app_localizations_en.dart';
import 'package:car_listing_app/l10n/app_localizations_ku.dart';
import 'package:flutter_test/flutter_test.dart';

const _requiredKeys = <String>[
  'sellPreparingVideo',
  'sellVideoCompressionFailed',
  'sellVideoTooLargeAfterCompression',
];

Map<String, dynamic> _loadArb(String locale) {
  final file = File('lib/l10n/app_$locale.arb');
  expect(
    file.existsSync(),
    isTrue,
    reason: 'lib/l10n/app_$locale.arb must exist',
  );
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('Sell-video compression localization keys exist (en/ar/ku)', () {
    for (final locale in ['en', 'ar', 'ku']) {
      test(
        '$locale.arb has all 3 sell-video-compression keys, non-empty',
        () {
          final arb = _loadArb(locale);
          for (final key in _requiredKeys) {
            expect(
              arb.containsKey(key),
              isTrue,
              reason: 'app_$locale.arb is missing required key "$key"',
            );
            final value = arb[key];
            expect(
              value,
              isA<String>(),
              reason: '"$key" in app_$locale.arb must be a string',
            );
            expect(
              (value as String).trim(),
              isNotEmpty,
              reason: '"$key" in app_$locale.arb must not be empty',
            );
          }
        },
      );
    }

    test(
      'the exact required English wording for "compressed output still too '
      'large" is preserved verbatim: "Video is too large. Please choose a '
      'shorter video."',
      () {
        final arb = _loadArb('en');
        expect(
          arb['sellVideoTooLargeAfterCompression'],
          'Video is too large. Please choose a shorter video.',
        );
      },
    );

    test(
      'generated AppLocalizations getters resolve to the exact same source '
      'strings for every required locale (catches a stale/un-regenerated '
      'app_localizations_*.dart after an .arb edit)',
      () {
        final AppLocalizations en = AppLocalizationsEn();
        final AppLocalizations ar = AppLocalizationsAr();
        final AppLocalizations ku = AppLocalizationsKu();

        final enArb = _loadArb('en');
        final arArb = _loadArb('ar');
        final kuArb = _loadArb('ku');

        expect(en.sellPreparingVideo, enArb['sellPreparingVideo']);
        expect(
          en.sellVideoCompressionFailed,
          enArb['sellVideoCompressionFailed'],
        );
        expect(
          en.sellVideoTooLargeAfterCompression,
          enArb['sellVideoTooLargeAfterCompression'],
        );

        expect(ar.sellPreparingVideo, arArb['sellPreparingVideo']);
        expect(
          ar.sellVideoCompressionFailed,
          arArb['sellVideoCompressionFailed'],
        );
        expect(
          ar.sellVideoTooLargeAfterCompression,
          arArb['sellVideoTooLargeAfterCompression'],
        );

        expect(ku.sellPreparingVideo, kuArb['sellPreparingVideo']);
        expect(
          ku.sellVideoCompressionFailed,
          kuArb['sellVideoCompressionFailed'],
        );
        expect(
          ku.sellVideoTooLargeAfterCompression,
          kuArb['sellVideoTooLargeAfterCompression'],
        );
      },
    );
  });
}
