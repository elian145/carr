import 'package:flutter/material.dart';

/// Registered [MaterialApp.routes] builders for zero-animation main-tab switches.
final Map<String, WidgetBuilder> appRouteBuilders = <String, WidgetBuilder>{};

void registerAppRoutes(Map<String, WidgetBuilder> routes) {
  appRouteBuilders
    ..clear()
    ..addAll(routes);
}
