import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_feed_errors.dart';
import 'package:car_listing_app/features/home/widgets/home_feed_states.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';

Widget _localizedApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: child,
  );
}

void main() {
  testWidgets('HomeFeedErrorState shows retry and clear filters', (tester) async {
    var retried = false;
    var cleared = false;

    await tester.pumpWidget(
      _localizedApp(
        Builder(
          builder: (context) {
            return Scaffold(
              body: HomeFeedErrorState(
                message: formatHomeFeedErrorMessage(
                  context,
                  HomeFeedErrors.network,
                ),
                onRetry: () => retried = true,
                onClearFilters: () => cleared = true,
              ),
            );
          },
        ),
      ),
    );

    expect(find.textContaining('connection'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Clear Filters'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Clear Filters'));
    expect(retried, isTrue);
    expect(cleared, isTrue);
  });
}
