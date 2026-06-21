import subprocess

header = """import 'package:flutter/material.dart';

import '../pages/admin_dealers_page.dart';
import '../pages/admin_reports_page.dart';
import '../pages/analytics_page.dart';
import '../pages/auth_pages.dart' as auth_pages;
import '../pages/change_password_page.dart';
import '../pages/chat_pages.dart' as carzo_chat;
import '../pages/dealer_profile_page.dart';
import '../pages/dealers_directory_page.dart';
import '../pages/edit_dealer_page.dart';
import '../pages/edit_listing_page.dart' as modern_edit;
import '../pages/edit_profile_page.dart';
import '../pages/help_center_page.dart';
import '../pages/my_listings_page.dart' as modern_listings;
import '../pages/recently_viewed_page.dart';
import '../pages/reset_password_page.dart';
import '../pages/tiktok_scroll_page.dart';
import '../pages/verify_email_page.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/navigation/route_args.dart';
import 'carzo_shared.dart';

Map<String, WidgetBuilder> buildProductionRoutes() {
  return """
footer = """;
}
"""

src = subprocess.check_output(
    ["git", "show", "HEAD:lib/pages/production/carzo_pages.dart"],
    text=True,
    encoding="utf-8",
)
start = src.index("routes: {")
chunk = src[start:]
depth = 0
end = 0
for i, ch in enumerate(chunk):
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break
routes = chunk[:end].replace("routes: {", "{")
from pathlib import Path

Path("lib/app/production_routes.dart").write_text(
    header + routes + footer, encoding="utf-8"
)
print("wrote", len(routes), "chars")
