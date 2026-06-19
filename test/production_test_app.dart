import 'package:flutter/material.dart';

import 'package:car_listing_app/app/production_app.dart';
import 'package:car_listing_app/legacy/legacy_fallback_routes.dart';

/// Same widget tree as production `main.dart`.
Widget buildProductionTestApp() {
  return ProductionApp(extraRoutes: buildLegacyFallbackRoutes());
}
