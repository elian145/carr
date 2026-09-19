import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/brand_logo_filenames.dart';
import 'package:car_listing_app/data/car_catalog.dart';

/// First 8 bytes every valid PNG file must start with.
const List<int> _pngSignature = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
];

bool _looksLikeValidPng(File f) {
  if (!f.existsSync() || f.lengthSync() < 8) return false;
  final bytes = f.openSync().readSync(8);
  return _bytesEqual(bytes, Uint8List.fromList(_pngSignature));
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Brands that are *known and expected* to have no logo file right now.
///
/// Every brand in this set must have a reason documented below. The
/// coverage test fails if:
///   - a brand NOT in this set has no logo (regression / new gap), OR
///   - a brand IN this set actually has a valid logo now (stale allowlist
///     entry that should be removed).
///
/// Both current entries are deliberately rejected supplied assets
/// (2026-09-19), from `D:\car logos scraper\logos\requested`
/// (manifest.json listed both, but visual + manifest inspection ruled out
/// using the supplied files as the brand logo):
///   - CEVO Mobility: supplied file `cevo-mobility.jpg` is a CEVO-C vehicle
///     interior/dashboard PHOTOGRAPH, not a brand mark. No clean logo was
///     supplied. Rejected per explicit instruction -- do not fabricate one.
///   - Huanghai: supplied file `huanghai.png` renders as the
///     "LIAONING SG AUTOMOTIVE GROUP CO.,LTD." parent-group corporate mark,
///     not a Huanghai-branded logo. Rejected per explicit instruction --
///     do not substitute a parent-company logo for a distinct consumer
///     brand.
///
/// The other 46 brands that were previously missing (Austin, Avatr,
/// Borgward, ... Zotye, plus Ineos/Neta/OMODA/XEV/Renault Samsung Motors)
/// have been restored from `D:\car logos scraper\logos` and
/// `D:\car logos scraper\logos\carbrandlogos` and are no longer in this
/// allowlist. Current coverage is 144/146.
const Set<String> knownMissingBrandLogos = {
  'CEVO Mobility',
  'Huanghai',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every production brand has a bundled or backend-static logo file, '
    'except the documented known-missing allowlist',
    () {
      final brands = CarCatalog.brands;

      expect(
        brands.length,
        greaterThan(100),
        reason:
            'CarCatalog.brands looks too small (${brands.length}) — '
            'assets/car_catalog.json may not have loaded for this test run.',
      );

      final bundledDir = Directory('assets/brand_logos');
      final backendDir = Directory('kk/static/images/brands');

      expect(
        backendDir.existsSync(),
        isTrue,
        reason: 'Expected backend logo directory at ${backendDir.path}',
      );

      final unexpectedlyMissing = <String>[];
      final invalidFormat = <String>[];
      final staleAllowlistEntries = <String>[];
      final seenAllowlistBrands = <String>{};

      for (final brand in brands) {
        final slug = brandLogoSlug(brand);
        final expectedFilename = '$slug.png';

        final bundledFile = File('${bundledDir.path}/$expectedFilename');
        final backendFile = File('${backendDir.path}/$expectedFilename');

        final hasBundled = bundledFile.existsSync();
        final hasBackend = backendFile.existsSync();
        final isAllowlisted = knownMissingBrandLogos.contains(brand);
        if (isAllowlisted) seenAllowlistBrands.add(brand);

        if (!hasBundled && !hasBackend) {
          if (!isAllowlisted) {
            unexpectedlyMissing.add(
              '$brand -> expected "$expectedFilename" '
              '(checked ${bundledFile.path} and ${backendFile.path})',
            );
          }
          continue;
        }

        final activeFile = hasBackend ? backendFile : bundledFile;
        if (!_looksLikeValidPng(activeFile)) {
          invalidFormat.add(
            '$brand -> ${activeFile.path} does not look like a valid PNG '
            '(bad signature or empty file)',
          );
        } else if (isAllowlisted) {
          // Brand now has a valid logo but is still listed as known-missing.
          staleAllowlistEntries.add(brand);
        }
      }

      // Every allowlist entry must correspond to a real catalog brand,
      // otherwise it's dead weight that could hide a real regression.
      final unknownAllowlistEntries = knownMissingBrandLogos.difference(
        brands.toSet(),
      );

      if (unexpectedlyMissing.isNotEmpty) {
        print(
          'Unexpected missing brand logo coverage for '
          '${unexpectedlyMissing.length}/${brands.length} brands:\n'
          '${unexpectedlyMissing.join('\n')}',
        );
      }
      if (invalidFormat.isNotEmpty) {
        print(
          'Invalid/corrupt logo files for ${invalidFormat.length} brand(s):\n'
          '${invalidFormat.join('\n')}',
        );
      }
      if (staleAllowlistEntries.isNotEmpty) {
        print(
          'Stale allowlist entries (now have a valid logo, remove from '
          'knownMissingBrandLogos): ${staleAllowlistEntries.join(', ')}',
        );
      }
      if (unknownAllowlistEntries.isNotEmpty) {
        print(
          'Allowlist entries that do not match any catalog brand name: '
          '${unknownAllowlistEntries.join(', ')}',
        );
      }

      expect(
        unexpectedlyMissing,
        isEmpty,
        reason:
            '${unexpectedlyMissing.length} production brand(s) have no logo '
            'in assets/brand_logos/ or kk/static/images/brands/ and are not '
            'in the documented knownMissingBrandLogos allowlist. See printed '
            'output above for the exact brand + expected filename.',
      );
      expect(
        invalidFormat,
        isEmpty,
        reason: '${invalidFormat.length} brand logo file(s) are not valid '
            'PNGs. See printed output above.',
      );
      expect(
        staleAllowlistEntries,
        isEmpty,
        reason:
            '${staleAllowlistEntries.length} brand(s) in knownMissingBrandLogos '
            'now have a valid logo file. Remove them from the allowlist. See '
            'printed output above.',
      );
      expect(
        unknownAllowlistEntries,
        isEmpty,
        reason:
            'knownMissingBrandLogos contains brand name(s) that do not match '
            'any entry in CarCatalog.brands: '
            '${unknownAllowlistEntries.join(', ')}',
      );
    },
  );

  test(
    'no two production brands resolve to the same canonical logo slug',
    () {
      final brands = CarCatalog.brands;
      final slugToBrands = <String, List<String>>{};
      for (final brand in brands) {
        final slug = brandLogoSlug(brand);
        slugToBrands.putIfAbsent(slug, () => []).add(brand);
      }

      final collisions = <String>[];
      slugToBrands.forEach((slug, brandsForSlug) {
        if (brandsForSlug.length > 1) {
          collisions.add('"$slug" <- $brandsForSlug');
        }
      });

      if (collisions.isNotEmpty) {
        print('Slug collisions detected:\n${collisions.join('\n')}');
      }

      expect(
        collisions,
        isEmpty,
        reason:
            'Two or more catalog brands normalize to the same logo slug, '
            "so they would silently render the same image (or overwrite "
            "each other's file on disk). See printed output above.",
      );
    },
  );
}
