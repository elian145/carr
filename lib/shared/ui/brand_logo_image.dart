import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/app_api_base.dart' show getApiBase;
import '../../data/brand_logo_filenames.dart';

/// Brand logos shipped in the app so they still show when the API CDN 404s.
const Set<String> kBundledBrandLogoSlugs = {
  'jetour',
  'soueast',
};

String brandLogoAssetPath(String slug) => 'assets/brand_logos/$slug.png';

String brandLogoNetworkUrl(String brand) {
  final slug = brandLogoSlug(brand);
  return '${getApiBase()}/static/images/brands/$slug.png';
}

/// Renders a brand logo from a bundled asset when available, otherwise CDN.
class BrandLogoImage extends StatelessWidget {
  const BrandLogoImage({
    super.key,
    required this.brand,
    this.fit = BoxFit.contain,
    this.placeholderSize = 20,
    this.errorIconSize = 22,
    this.errorIconColor = const Color(0xFFFF6B00),
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
