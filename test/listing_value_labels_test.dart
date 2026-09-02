import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/shared/i18n/listing_value_labels.dart';
import 'package:car_listing_app/shared/i18n/sort_api_mapping.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _localizedApp(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
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

    testWidgets('maps English labels while locale is Arabic', (tester) async {
      await tester.pumpWidget(
        _localizedApp(
          locale: const Locale('ar'),
          Builder(
            builder: (context) {
              expect(convertSortToApiValue(context, 'Newest'), 'newest');
              expect(
                convertSortToApiValue(context, 'Price (High to Low)'),
                'price_desc',
              );
              expect(convertSortToApiValue(context, 'الأحدث'), 'newest');
              expect(convertSortToApiValue(context, 'newest'), 'newest');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group('localizeSortOption', () {
    testWidgets('rewrites English sort labels into Arabic', (tester) async {
      await tester.pumpWidget(
        _localizedApp(
          locale: const Locale('ar'),
          Builder(
            builder: (context) {
              final loc = AppLocalizations.of(context)!;
              expect(localizeSortOption(context, 'Newest'), loc.sort_newest);
              expect(localizeSortOption(context, 'newest'), loc.sort_newest);
              expect(
                localizeSortOption(context, 'Price (Low to High)'),
                loc.sort_price_low_high,
              );
              expect(localizeSortOption(context, 'unknown-sort'), 'unknown-sort');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
