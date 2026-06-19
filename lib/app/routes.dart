import 'package:flutter/material.dart';

import 'production_routes.dart';

export 'production_routes.dart' show buildProductionRoutes;

/// Modern routes for [CarzoApp] smoke tests (same map as production).
Map<String, WidgetBuilder> buildAppRoutes() => buildProductionRoutes();
