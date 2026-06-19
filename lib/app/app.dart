import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'routes.dart';

/// Refactor / test shell using the same production route map as [ProductionApp].
class CarzoApp extends StatelessWidget {
  const CarzoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CarNetAppShell(routes: buildAppRoutes());
  }
}
