import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'production_routes.dart';

/// Production app entry widget (`main.dart`).
///
/// Merges modern routes with optional legacy URL aliases from
/// `lib/legacy/legacy_fallback_routes.dart`.
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
