import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:car_listing_app/app/app_shell.dart';
import 'package:car_listing_app/app/providers.dart';
import 'package:car_listing_app/pages/chat_pages.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/auth/auth_guard.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    await AuthService().adoptTestSession();
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Chat list shows empty state when authenticated', (tester) async {
    expect(await ApiService.getChats(), isEmpty);

    await tester.pumpWidget(
      MultiProvider(
        providers: buildAppProviders(),
        child: MaterialApp(
          localizationsDelegates: CarNetAppShell.localizationDelegates,
          supportedLocales: CarNetAppShell.supportedLocales,
          home: const AuthGuard(child: ChatListPage()),
        ),
      ),
    );

    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .text('No messages yet. Start a conversation!')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(find.text('Chat'), findsOneWidget);
    expect(
      find.text('No messages yet. Start a conversation!'),
      findsOneWidget,
    );
  });
}
