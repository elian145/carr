import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

import '../../app/app_api_base.dart' show getApiBase;
import '../../data/brand_logo_filenames.dart';

/// Brand logos shipped in the app so they still show when the API CDN 404s.
///
/// The second group are logos that were re-cut (tight transparent canvas,
/// emblem-only where the supplied lock-up was unreadable inside a circle).
/// They are bundled so the corrected artwork shows immediately and can never be
/// replaced by a stale copy of the old image in the network image cache. The
/// same files are also served from `kk/static/images/brands/` for older app
/// versions and the legacy web pages. `tools/brand_logos/build_brand_logos.py`
/// writes both copies.
const Set<String> kBundledBrandLogoSlugs = {
  'jetour',
  'soueast',
  // Re-cut logos (see tools/brand_logos).
  'baw',
  'forthing',
  'hyptec',
  'ineos',
  'jaecoo',
  'jonway',
  'karry',
  'kawasaki',
  'poer',
  'polaris',
  'vanderhall',
};

String brandLogoAssetPath(String slug) => 'assets/brand_logos/$slug.png';

String brandLogoNetworkUrl(String brand) {
  final slug = brandLogoSlug(brand);
  return '${getApiBase()}/static/images/brands/$slug.png';
}

/// Wide, short wordmarks (no emblem exists) leave a lot of a circle unused when
/// they are squeezed into the default square box, so these few slugs are allowed
/// to span more of the coin: the value is the width of the logo as a fraction of
/// the circle diameter.
///
/// Each value is the widest rectangle of that logo's aspect ratio that still
/// keeps >= 5 dp of clear space to the circle rim on a 52 dp coin
/// (`test/brand_logo_fit_test.dart` enforces this against the real PNGs).
/// Brands that are not listed keep the standard padded box, i.e. are unchanged.
const Map<String, double> kBrandLogoCircleFill = {
  'baw': 0.75,
  'ineos': 0.75,
  'jaecoo': 0.78,
  'kawasaki': 0.77,
  'polaris': 0.77,
};

/// Test hook: supply an [ImageProvider] per logo slug so widget tests and the
/// visual contact sheet can render the real widgets without network access.
/// Always null in production.
@visibleForTesting
ImageProvider? Function(String slug)? debugBrandLogoImageOverride;

/// Renders a brand logo from a bundled asset when available, otherwise CDN.
class BrandLogoImage extends StatelessWidget {
  const BrandLogoImage({
    super.key,
    required this.brand,
    this.fit = BoxFit.contain,
    this.placeholderSize = 20,
    this.errorIconSize = 22,
    this.errorIconColor = AppColors.brandOrange,
  });

  final String brand;
  final BoxFit fit;
  final double placeholderSize;
  final double errorIconSize;
  final Color errorIconColor;

  @override
  Widget build(BuildContext context) {
    final slug = brandLogoSlug(brand);
    if (slug.isEmpty) {
      return Icon(
        Icons.directions_car,
        size: errorIconSize,
        color: errorIconColor,
      );
    }

    final override = debugBrandLogoImageOverride?.call(slug);
    if (override != null) {
      return Image(
        image: override,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.directions_car,
          size: errorIconSize,
          color: errorIconColor,
        ),
      );
    }

    if (kBundledBrandLogoSlugs.contains(slug)) {
      return Image.asset(
        brandLogoAssetPath(slug),
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.directions_car,
          size: errorIconSize,
          color: errorIconColor,
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: '${getApiBase()}/static/images/brands/$slug.png',
      placeholder: (context, url) => SizedBox(
        width: placeholderSize,
        height: placeholderSize,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: (context, url, error) => Icon(
        Icons.directions_car,
        size: errorIconSize,
        color: errorIconColor,
      ),
      fit: fit,
    );
  }
}

/// The round white brand "coin" used by the brand pickers (Sell, Search,
/// Filters, keyword search).
///
/// Logos are drawn with [BoxFit.contain] (aspect ratio is always preserved) in
/// the square left after [padding], and the whole coin is clipped to its
/// circle, so no logo, matte or stray transparent-edge artefact can ever paint
/// outside the circular boundary.
class BrandLogoCircle extends StatelessWidget {
  const BrandLogoCircle({
    super.key,
    required this.brand,
    this.size = 52,
    this.padding = 8,
    this.placeholderSize = 20,
    this.errorIconSize = 22,
    this.errorIconColor = AppColors.brandOrange,
  });

  final String brand;
  final double size;
  final double padding;
  final double placeholderSize;
  final double errorIconSize;
  final Color errorIconColor;

  /// Inset between the circle edge and the logo box for [brand].
  double insetFor(String brand) {
    final fill = kBrandLogoCircleFill[brandLogoSlug(brand)];
    if (fill == null) return padding;
    return size * (1 - fill) / 2;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: ClipOval(
          child: Padding(
            padding: EdgeInsets.all(insetFor(brand)),
            child: BrandLogoImage(
              brand: brand,
              placeholderSize: placeholderSize,
              errorIconSize: errorIconSize,
              errorIconColor: errorIconColor,
            ),
          ),
        ),
      ),
    );
  }
}
