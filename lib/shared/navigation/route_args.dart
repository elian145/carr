import 'package:flutter/material.dart';

/// Normalizes [ModalRoute.settings.arguments] into a string-keyed map.
Map<String, dynamic>? readRouteArgs(BuildContext context) {
  final args = ModalRoute.of(context)?.settings.arguments;
  if (args is Map<String, dynamic>) return args;
  if (args is Map) {
    return args.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

/// Standard scaffold shown when a named route is missing required arguments.
Widget navigationErrorScaffold(String message) {
  return Scaffold(
    appBar: AppBar(title: const Text('Navigation error')),
    body: Center(child: Text(message)),
  );
}
