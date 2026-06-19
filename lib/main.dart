import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'app/production_app.dart';
import 'legacy/main_legacy.dart' as legacy;

void main() {
  bootstrapAndRun(
    ProductionApp(
      extraRoutes: legacy.buildLegacyFallbackRoutes(),
    ),
  );
}
