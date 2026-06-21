#!/usr/bin/env python3
"""One-shot migration: lib/pages/production part library -> lib/pages + lib/app/carzo_shared.dart"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROD = ROOT / "lib" / "pages" / "production"
APP = ROOT / "lib" / "app"
PAGES = ROOT / "lib" / "pages"
CARZO_APP = PAGES / "carzo_app"

PART_MAP = {
    "home_page_part.dart": "home_page.dart",
    "sell_flow_part.dart": "sell_flow_page.dart",
    "car_detail_part.dart": "car_details_page.dart",
    "saved_searches_part.dart": "saved_searches_page.dart",
    "comparison_part.dart": "comparison_page.dart",
    "auth_pages_part.dart": "production_auth_pages.dart",
    "account_pages_part.dart": "production_account_pages.dart",
    "legacy_routes_part.dart": "legacy_fallback_routes.dart",
}

STUBS_TO_CARZO_APP = [
    "home_page.dart",
    "sell_page.dart",
    "car_detail_page.dart",
    "comparison_page.dart",
    "profile_page.dart",
    "settings_page.dart",
    "favorites_page.dart",
]


def fix_imports(text: str) -> str:
    text = text.replace("import '../../", "import '../")
    page_imports = (
        "analytics_page.dart",
        "edit_profile_page.dart",
        "auth_pages.dart",
        "chat_pages.dart",
        "reset_password_page.dart",
        "change_password_page.dart",
        "verify_email_page.dart",
        "admin_dealers_page.dart",
        "dealer_profile_page.dart",
        "dealers_directory_page.dart",
        "edit_dealer_page.dart",
        "my_listings_page.dart",
        "edit_listing_page.dart",
        "recently_viewed_page.dart",
        "help_center_page.dart",
        "legal_document_page.dart",
        "admin_reports_page.dart",
        "listing_image_gallery_page.dart",
        "tiktok_scroll_page.dart",
    )
    for name in page_imports:
        text = text.replace(f"import '../{name}'", f"import '../pages/{name}'")
    return text


def strip_main_and_myapp(text: str) -> str:
    # Remove dead `void main()` block (bootstrap lives in lib/main.dart).
    text = re.sub(
        r"\nvoid main\(\) \{.*?\n\}\n\nFuture<void> _initPushToken",
        "\nFuture<void> _initPushToken",
        text,
        count=1,
        flags=re.DOTALL,
    )
    # Remove MyApp shell (moved to production_app.dart).
    text = re.sub(
        r"\n/// Wraps \[MaterialApp\].*?class MyApp extends StatelessWidget \{.*?\n\}\n\n// Theme Toggle Widget",
        "\n// Theme Toggle Widget",
        text,
        count=1,
        flags=re.DOTALL,
    )
    return text


def main() -> None:
    CARZO_APP.mkdir(parents=True, exist_ok=True)

    for stub in STUBS_TO_CARZO_APP:
        src = PAGES / stub
        if src.exists():
            dst = CARZO_APP / stub
            if dst.exists():
                dst.unlink()
            shutil.move(str(src), str(dst))

    src_lib = PROD / "carzo_pages.dart"
    shared = APP / "carzo_shared.dart"
    text = src_lib.read_text(encoding="utf-8")
    marker = "import '../../widgets/edge_swipe_back.dart';\n"
    text = fix_imports(text)
    text = strip_main_and_myapp(text)
    text = text.replace(
        "_appNavigatorKey",
        "productionNavigatorKey",
    )
    text = re.sub(
        r"part '[^']+\.dart';\n",
        "",
        text,
    )
    marker_fixed = "import '../widgets/edge_swipe_back.dart';\n"
    if marker_fixed not in text:
        raise SystemExit("Could not find import marker in carzo_pages.dart")
    part_lines = "\n".join(
        f"part '../pages/{dest}';" if dest != "legacy_fallback_routes.dart"
        else "part 'legacy_fallback_routes.dart';"
        for dest in PART_MAP.values()
    )
    text = text.replace(
        marker_fixed,
        marker_fixed + part_lines + "\n",
    )
    shared.write_text(text, encoding="utf-8")

    for src_name, dest_name in PART_MAP.items():
        src = PROD / src_name
        if dest_name == "legacy_fallback_routes.dart":
            dest = APP / dest_name
            part_of = "part of 'carzo_shared.dart';"
        else:
            dest = PAGES / dest_name
            part_of = "part of '../app/carzo_shared.dart';"
        content = src.read_text(encoding="utf-8")
        content = content.replace(
            "part of 'carzo_pages.dart';",
            part_of,
        )
        dest.write_text(content, encoding="utf-8")

    print("Wrote", shared)
    for dest in PART_MAP.values():
        print("  part ->", dest)


if __name__ == "__main__":
    main()
