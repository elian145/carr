import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file so setUp/tearDown can use platform channels
/// (SharedPreferences, secure storage, etc.) without per-file boilerplate.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await testMain();
}
