import 'package:flutter/material.dart';

Map<String, dynamic>? readRouteArgs(BuildContext context) {
  final args = ModalRoute.of(context)?.settings.arguments;
  if (args is Map<String, dynamic>) return args;
  if (args is Map) {
    return args.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

Widget navigationErrorScaffold(String message) {
  return Scaffold(
    appBar: AppBar(title: const Text('Navigation error')),
    body: Center(child: Text(message)),
  );
}
