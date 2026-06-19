import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'production_routes.dart';

/// Production app entry widget (`main.dart`).
///
/// Merges modern routes with optional legacy fallback routes from
/// [buildLegacyFallbackRoutes] in `legacy/main_legacy.dart`.
class ProductionApp extends StatelessWidget {
  const ProductionApp({
    super.key,
    this.extraRoutes = const {},
  });

  final Map<String, WidgetBuilder> extraRoutes;

  @override
  Widget build(BuildContext context) {
    return CarNetAppShell(
      routes: {
        ...buildProductionRoutes(),
        ...extraRoutes,
      },
    );
  }
}
