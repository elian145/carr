#!/usr/bin/env python3
"""Split listing widgets out of lib/app/carzo_shared.dart into standalone modules."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "lib/app/carzo_shared.dart"

# 1-based inclusive line ranges in the original carzo_shared.dart
RANGES = [
    ("lib/app/app_api_base.dart", 419, 422, "APP_API_BASE"),
    ("lib/app/widgets/listing_network_image.dart", 424, 566, "LISTING_NETWORK_IMAGE"),
    ("lib/data/brand_logo_filenames.dart", 3161, 3238, "BRAND_LOGOS"),
    ("lib/app/widgets/global_listing_card.dart", 990, 1779, "GLOBAL_LISTING_CARD"),
    ("lib/app/widgets/listing_galleries.dart", 1834, 2131, "LISTING_GALLERIES"),
    ("lib/app/widgets/home_search_dialog.dart", 2386, 2757, "HOME_SEARCH_DIALOG"),
]

HEADERS = {
    "APP_API_BASE": """import '../services/config.dart';

""",
    "LISTING_NETWORK_IMAGE": """import 'package:flutter/material.dart';

import '../../shared/debug/app_log.dart';

""",
    "BRAND_LOGOS": "",
    "GLOBAL_LISTING_CARD": """import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/brand_logo_filenames.dart';
import '../../data/car_name_translations.dart';
import '../../l10n/app_localizations.dart';
import '../../services/recently_viewed_service.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/listings/listing_card_data.dart' as listing_card_data;
import '../../shared/listings/listing_card_media.dart';
import '../../shared/listings/listing_status.dart';
import '../../shared/listings/listing_sold_badge.dart';
import '../../shared/listings/listing_uploaded_ago.dart';
import '../../shared/media/media_url.dart';
import '../../shared/text/pretty_title_case.dart';
import '../../theme_provider.dart';
import '../app_api_base.dart';
import 'listing_network_image.dart';

""",
    "LISTING_GALLERIES": """import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/media/media_url.dart';
import '../../widgets/in_app_video_screen.dart';
import 'listing_network_image.dart';

""",
    "HOME_SEARCH_DIALOG": """import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/brand_logo_filenames.dart';
import '../../data/car_name_translations.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import '../app_api_base.dart';

""",
}

TRANSFORMS = {
    "LISTING_NETWORK_IMAGE": [
        ("Widget _listingNetworkImage(", "Widget listingNetworkImage("),
    ],
    "GLOBAL_LISTING_CARD": [
        ("String? _translateValueGlobal(BuildContext context, String? raw) =>\n    translateListingValue(context, raw);\n\n", ""),
        ("String _localizedCarTitleForCard(", "String localizedCarTitleForCard("),
        ("String _localizedTrimForCard(", "String localizedTrimForCard("),
        ("String _listingUploadedAgo(BuildContext context, Map car) =>\n    listingUploadedAgo(context, car);\n\n", ""),
        ("String _localizeDigitsGlobal(BuildContext context, String input) =>\n    localizeDigits(context, input);", ""),
        ("NumberFormat _decimalFormatterGlobal(BuildContext context) =>\n    decimalFormatter(context);", ""),
        ("String _formatCurrencyGlobal(BuildContext context, dynamic raw) =>\n    formatCurrency(context, raw);", ""),
        ("_translateValueGlobal(", "translateListingValue("),
        ("_localizeDigitsGlobal(", "localizeDigits("),
        ("_decimalFormatterGlobal(", "decimalFormatter("),
        ("_formatCurrencyGlobal(", "formatCurrency("),
        ("_localizedCarTitleForCard(", "localizedCarTitleForCard("),
        ("_localizedTrimForCard(", "localizedTrimForCard("),
        ("_listingUploadedAgo(", "listingUploadedAgo("),
        ("_buildFullImageUrl", "buildLegacyFullImageUrl"),
        ("_listingNetworkImage", "listingNetworkImage"),
    ],
    "LISTING_GALLERIES": [
        ("class _FullscreenZoomableSlide", "class FullscreenZoomableSlide"),
        ("_FullscreenZoomableSlide", "FullscreenZoomableSlide"),
        ("_listingNetworkImage", "listingNetworkImage"),
        ("_buildFullImageUrl", "buildLegacyFullImageUrl"),
    ],
    "HOME_SEARCH_DIALOG": [
        ("class _SearchDialog", "class HomeSearchDialog"),
        ("_SearchDialog", "HomeSearchDialog"),
        ("_SearchDialogState", "HomeSearchDialogState"),
        ("_trLegacyText(", "trLegacyText("),
    ],
    "BRAND_LOGOS": [
        ("// Global brand logo filenames map accessible to all classes\n", ""),
    ],
}

IMPORT_BLOCK = """
import 'app_api_base.dart';
import '../data/brand_logo_filenames.dart';
import 'widgets/global_listing_card.dart';
import 'widgets/home_search_dialog.dart';
import 'widgets/listing_galleries.dart';
import 'widgets/listing_network_image.dart';

"""

WRAPPER_BLOCK = """
String _buildFullImageUrl(String rel) => buildLegacyFullImageUrl(rel);

Widget _listingNetworkImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) =>
    listingNetworkImage(url, fit: fit, width: width, height: height);

String? _translateValueGlobal(BuildContext context, String? raw) =>
    translateListingValue(context, raw);

String _localizedCarTitleForCard(BuildContext context, Map car) =>
    localizedCarTitleForCard(context, car);

String _listingUploadedAgo(BuildContext context, Map car) =>
    listingUploadedAgo(context, car);

/// Normalizes API listing / favorite payloads into the shape expected by [buildGlobalCarCard].
Map<String, dynamic> mapListingToGlobalCarCardData(
  BuildContext context,
  Map<String, dynamic> listing,
) =>
    listing_card_data.mapListingToGlobalCarCardData(context, listing);

"""


def main() -> None:
    text = SHARED.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)

    remove: set[int] = set()
    for _, start, end, _ in RANGES:
        remove.update(range(start, end + 1))

    for rel_path, start, end, key in RANGES:
        chunk = "".join(lines[start - 1 : end])
        for old, new in TRANSFORMS.get(key, []):
            chunk = chunk.replace(old, new)
        out = ROOT / rel_path
        out.parent.mkdir(parents=True, exist_ok=True)
        header = HEADERS[key]
        if key == "BRAND_LOGOS":
            header = "// Brand logo filename slugs for static CDN paths.\n\n"
        out.write_text(header + chunk.rstrip() + "\n", encoding="utf-8")
        print(f"wrote {rel_path} ({end - start + 1} lines)")

    new_lines: list[str] = []
    inserted_imports = False
    inserted_wrappers = False
    for i, line in enumerate(lines, start=1):
        if i in remove:
            continue
        if not inserted_imports and line.startswith("part '../pages/home_page.dart';"):
            # Imports must precede all part directives.
            new_lines.append(IMPORT_BLOCK)
            new_lines.append(line)
            inserted_imports = True
            continue
        if not inserted_wrappers and line.startswith(
            "String _localizeDigitsGlobal(BuildContext context, String input) =>"
        ):
            new_lines.append(WRAPPER_BLOCK)
            inserted_wrappers = True
        new_lines.append(line)

    if not inserted_imports:
        raise SystemExit("failed to insert imports")
    if not inserted_wrappers:
        raise SystemExit("failed to insert wrappers")

    SHARED.write_text("".join(new_lines), encoding="utf-8")
    print(f"updated {SHARED.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
