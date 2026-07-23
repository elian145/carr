import 'package:car_listing_app/features/chat/chat_strings.dart';
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

  testWidgets('userErrorText surfaces short 5xx ApiException messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final err = ApiException(
              statusCode: 500,
              message: 'Failed to send verification code',
            );
            expect(
              userErrorText(context, err, fallback: 'Failed to send OTP'),
              'Failed to send verification code',
            );
            final leaky = ApiException(
              statusCode: 500,
              message: 'Exception: traceback dump',
            );
            expect(
              userErrorText(context, leaky, fallback: 'Failed to send OTP'),
              'Failed to send OTP',
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  test('formatSocketErrorForUser never returns raw internals', () {
    expect(
      formatSocketErrorForUser('SocketException: Connection reset by peer'),
      isNot(contains('SocketException')),
    );
    expect(
      formatSocketErrorForUser('failed host lookup: example.com'),
      contains('Cannot reach CarNet'),
    );
  });
}
