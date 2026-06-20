import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/shared/listings/listing_card_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mapListingToGlobalCarCardData builds card fields', (
    tester,
  ) async {
    late Map<String, dynamic> mapped;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            mapped = mapListingToGlobalCarCardData(context, {
              'public_id': 'car_1',
              'brand': 'toyota',
              'model': 'camry',
              'year': 2020,
              'mileage': 12000,
              'price': 15000,
              'location': 'Erbil',
              'image_url': 'photo.jpg',
            });
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(mapped['id'], 'car_1');
    expect(mapped['title'], contains('Toyota'));
    expect(mapped['mileage'], '12,000');
    expect(mapped['city'], 'Erbil');
  });
}
