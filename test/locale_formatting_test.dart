import 'package:car_listing_app/globals.dart';
import 'package:car_listing_app/shared/i18n/locale_formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('formatCurrency uses global symbol and formats numbers', (
    tester,
  ) async {
    globalSymbol = r'$';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(formatCurrency(context, 1200), r'$1,200');
            expect(formatCurrency(context, '2500'), r'$2,500');
            expect(formatCurrency(context, 'bad'), r'$0');
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
