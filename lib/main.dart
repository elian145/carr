import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'legacy/main_legacy.dart' as legacy;

void main() {
  // Production UI (bottom nav, signup, profile, etc.) lives in
  // `legacy/main_legacy.dart` — not in `lib/pages/auth_pages.dart` / `profile_page.dart`.
  bootstrapAndRun(const legacy.MyApp());
}

