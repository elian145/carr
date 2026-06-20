import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/shared/errors/user_error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('userErrorText hides transport errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              userErrorText(context, Exception('SocketException: failed')),
              'Error',
            );
            expect(
              userErrorText(context, Exception('visible'), fallback: 'Oops'),
              'Oops',
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('userErrorText surfaces 4xx ApiException messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final err = ApiException(
              statusCode: 400,
              message: 'Invalid listing payload',
            );
            expect(userErrorText(context, err), 'Invalid listing payload');
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
