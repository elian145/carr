import 'package:car_listing_app/shared/listings/listing_uploaded_ago.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('listingUploadedAgo returns just now for recent listings', (
    tester,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            final text = listingUploadedAgo(context, {'created_at': now});
            expect(text, 'Just now');
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
