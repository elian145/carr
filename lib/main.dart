import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'app/production_app.dart';
import 'legacy/legacy_fallback_routes.dart';

void main() {
  bootstrapAndRun(
    ProductionApp(
      extraRoutes: buildLegacyFallbackRoutes(),
    ),
  );
}
