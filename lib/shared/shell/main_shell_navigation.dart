import 'package:flutter/material.dart';

/// Zero-animation tab switch for main shell routes (home, favorites, dealers, profile).
void navigateMainShellTab(BuildContext context, String routeName) {
  final currentRoute = ModalRoute.of(context)?.settings.name;
  if (currentRoute == routeName) return;
  Navigator.of(context).pushReplacementNamed(routeName);
}

void navigateMainShellTabIndex(BuildContext context, int index) {
  final route = switch (index) {
    0 => '/',
    1 => '/favorites',
    2 => '/dealers',
    3 => '/profile',
    _ => '/',
  };
  navigateMainShellTab(context, route);
}
