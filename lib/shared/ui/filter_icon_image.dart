import 'package:flutter/material.dart';

/// Opaque fill shared by filter icon tiles and dark-mode icon artwork.
const Color kFilterIconTileDarkFill = Color(0xFF1C1F28);

/// Opaque backdrop matching search-filter icon tiles on the dark shell.
Color filterIconTileBackdropColor(BuildContext context) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  if (isLight) {
    return Colors.white;
  }
  return kFilterIconTileDarkFill;
}

bool _isFilterIconDarkVariantCandidate(String asset) {
  return asset.endsWith('.png') &&
      !asset.contains('reference_sheet') &&
      !asset.endsWith('_dark.png') &&
      (asset.startsWith('assets/body_types_png/') ||
          asset.startsWith('assets/drive_types/') ||
          asset.startsWith('assets/transmission_types/') ||
          asset.startsWith('assets/plate_types/'));
}

/// Resolves filter artwork to a dark-mode variant (same pixels, transparent outer bg).
String filterIconAssetForTheme(BuildContext context, String asset) {
  if (Theme.of(context).brightness == Brightness.light) {
    return asset;
  }
  if (!_isFilterIconDarkVariantCandidate(asset)) {
    return asset;
  }
  return asset.replaceAll('.png', '_dark.png');
}

Widget buildFilterIconImage({
  required BuildContext context,
  required String imageAsset,
  required double width,
  required double height,
  BoxFit fit = BoxFit.contain,
  double borderRadius = 0,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final resolvedAsset = filterIconAssetForTheme(context, imageAsset);
  final backdrop = filterIconTileBackdropColor(context);

  Widget image = Image.asset(
    resolvedAsset,
    width: width,
    height: height,
    fit: fit,
    filterQuality: FilterQuality.high,
    errorBuilder: (context, error, stackTrace) {
      if (resolvedAsset != imageAsset) {
        return Image.asset(
          imageAsset,
          width: width,
          height: height,
          fit: fit,
          filterQuality: FilterQuality.high,
        );
      }
      return SizedBox(width: width, height: height);
    },
  );

  if (isDark) {
    image = ColoredBox(color: backdrop, child: image);
  }

  if (borderRadius > 0) {
    image = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: image,
    );
  }

  return image;
}
