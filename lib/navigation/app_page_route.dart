import 'package:flutter/material.dart';

/// App-wide [MaterialPageRoute] with live under-route painting during swipe-back.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
    super.maintainState,
  }) : super(allowSnapshotting: false);

  AnimationController? get routeAnimationController => controller;
}

Route<dynamic>? appOnGenerateRoute(
  RouteSettings settings,
  Map<String, WidgetBuilder> routes,
) {
  final builder = routes[settings.name];
  if (builder == null) return null;
  return AppPageRoute<void>(settings: settings, builder: builder);
}
