import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'production_routes.dart';

/// Production app entry widget (`main.dart`).
class ProductionApp extends StatelessWidget {
  const ProductionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CarNetAppShell(routes: buildProductionRoutes());
  }
}
