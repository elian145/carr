import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/shared/i18n/listing_value_labels.dart';
import 'package:car_listing_app/shared/i18n/sort_api_mapping.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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
  group('translateListingValue', () {
    testWidgets('translates known filter values', (tester) async {
      await tester.pumpWidget(
        _localizedApp(
          Builder(
            builder: (context) {
              expect(translateListingValue(context, 'automatic'), isNotNull);
              expect(translateListingValue(context, 'sedan'), isNotNull);
              expect(translateListingValue(context, 'baghdad'), 'Baghdad');
              expect(translateListingValue(context, 'unknown'), 'unknown');
              expect(translateListingValue(context, null), isNull);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group('convertSortToApiValue', () {
    testWidgets('maps localized sort labels to API values', (tester) async {
      await tester.pumpWidget(
        _localizedApp(
          Builder(
            builder: (context) {
              final loc = AppLocalizations.of(context)!;
              expect(convertSortToApiValue(context, null), isNull);
              expect(convertSortToApiValue(context, ''), isNull);
              expect(convertSortToApiValue(context, loc.defaultSort), isNull);
              expect(
                convertSortToApiValue(context, loc.sort_newest),
                'newest',
              );
              expect(
                convertSortToApiValue(context, loc.sort_price_low_high),
                'price_asc',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
