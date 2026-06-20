import 'package:car_listing_app/shared/i18n/listing_field_labels.dart';
import 'package:car_listing_app/shared/listings/transmission_filter.dart';
import 'package:car_listing_app/shared/navigation/route_args.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readRouteArgs', () {
    testWidgets('normalizes string-keyed route maps', (tester) async {
      late Map<String, dynamic>? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      settings: RouteSettings(
                        arguments: {'carId': 42, 'label': 'test'},
                      ),
                      builder: (ctx) {
                        captured = readRouteArgs(ctx);
                        return const Scaffold(body: Text('child'));
                      },
                    ),
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(captured?['carId'], 42);
      expect(captured?['label'], 'test');
    });
  });

  group('navigationErrorScaffold', () {
    testWidgets('shows navigation error message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: navigationErrorScaffold('Missing listing id')),
      );
      expect(find.text('Missing listing id'), findsOneWidget);
      expect(find.text('Navigation error'), findsOneWidget);
    });
  });

  group('translatePlateTypeLabel', () {
    testWidgets('translates known plate types', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(translatePlateTypeLabel(context, 'private'), 'Private');
              expect(translatePlateTypeLabel(context, 'TAXI'), 'Taxi');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group('isExcludedTransmissionFilter', () {
    test('excludes semi-automatic variants and cvt', () {
      expect(isExcludedTransmissionFilter('Semi Automatic'), isTrue);
      expect(isExcludedTransmissionFilter('semi-auto'), isTrue);
      expect(isExcludedTransmissionFilter('CVT'), isTrue);
      expect(isExcludedTransmissionFilter('Automatic'), isFalse);
    });
  });
}
