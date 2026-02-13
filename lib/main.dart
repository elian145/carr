import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'legacy/main_legacy.dart' as legacy;

void main() {
  // Use the legacy app shell to preserve the original look & flows,
  // while keeping all backend/client fixes elsewhere in the codebase.
  bootstrapAndRun(const legacy.MyApp());
}

