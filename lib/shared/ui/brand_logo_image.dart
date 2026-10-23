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
  // Second round (found on the physical phone): Huanghai had no file at all,
  // KAWEI / Polarsun / Zimmer were opaque white rectangles and XEV was a
  // dark-background lock-up whose white "EV" vanished on the coin (now XEV's
  // official light-background lock-up).
  'huanghai',
  'kawei',
  'polarsun',
  'xev',
  'zimmer',
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
  // Second round. Both are tightly cropped wide artwork (aspect ~2.5) that
  // crossed the rim of the circle on the phone.
  'kawei': 0.74,
  // XEV's full official lock-up (blue X + grey EV, aspect ~3.4): the X touches
  // the corners of the bounding box, so the width is capped for rim clearance.
  'xev': 0.76,
  'zyle-daewoo-commercial-vehicle': 0.74,
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

/// Width of the logo box the Search Cars picker has always used for brands that
/// are not in [kBrandLogoCircleFill]: tile 72 dp - 2 x 1 dp ring - 2 x 8 dp
/// padding. That wider-than-tall box is what makes ordinary 4:3 logo canvases
/// (Toyota, Hyundai, ...) look the way they do on the phone today, so it is
/// kept as is; [BrandLogoCircle] just no longer lets anything leave the circle.
const double kSearchLogoBoxWidth = 54;

/// The round white brand "coin" used by the brand pickers (Sell, Search,
/// Filters, keyword search).
///
/// The coin is ALWAYS exactly [size] x [size], centred in whatever space the
/// parent offers. (The first version was a bare `SizedBox(size)`: inside the
/// Search tile, whose Column uses `CrossAxisAlignment.stretch`, the parent's
/// tight 70 dp width overrode it, producing a 70 x 52 box. `ClipOval` then
/// clipped to a 70 x 52 *ellipse* and the padding was measured against 70 dp,
/// so wide wordmarks extended past the 52 dp circle. Isolated widget tests
/// never saw it because they gave the coin an explicit size.)
///
/// Logos are drawn with [BoxFit.contain] (aspect ratio is always preserved) in
/// a box of [padding]-inset height and [logoBoxWidth] width, or, for the wide
/// wordmarks in [kBrandLogoCircleFill], a square box sized from that table;
/// the coin is clipped to its circle, so nothing can ever paint outside it.
class BrandLogoCircle extends StatelessWidget {
  const BrandLogoCircle({
    super.key,
    required this.brand,
    this.size = 52,
    this.padding = 8,
    this.logoBoxWidth,
    this.placeholderSize = 20,
    this.errorIconSize = 22,
    this.errorIconColor = AppColors.brandOrange,
  });

  final String brand;
  final double size;
  final double padding;

  /// Width of the logo box for brands that are not in [kBrandLogoCircleFill];
  /// defaults to the square `size - 2 * padding`.
  final double? logoBoxWidth;
  final double placeholderSize;
  final double errorIconSize;
  final Color errorIconColor;

  /// Inset between the circle edge and the logo box for [brand].
  double insetFor(String brand) {
    final fill = kBrandLogoCircleFill[brandLogoSlug(brand)];
    if (fill == null) return padding;
    return size * (1 - fill) / 2;
  }

  /// The box (centred in the coin) the logo of [brand] is fitted into.
  Size logoBoxFor(String brand) {
    final fill = kBrandLogoCircleFill[brandLogoSlug(brand)];
    if (fill != null) return Size.square(size * fill);
    final h = size - 2 * padding;
    return Size(logoBoxWidth ?? h, h);
  }

  @override
  Widget build(BuildContext context) {
    final box = logoBoxFor(brand);
    // Align(widthFactor/heightFactor: 1) loosens any tight incoming
    // constraints, so the coin keeps its own size and is centred.
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: ClipOval(
            child: OverflowBox(
              minWidth: box.width,
              maxWidth: box.width,
              minHeight: box.height,
              maxHeight: box.height,
              child: BrandLogoImage(
                brand: brand,
                placeholderSize: placeholderSize,
                errorIconSize: errorIconSize,
                errorIconColor: errorIconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
