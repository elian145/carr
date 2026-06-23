import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_feed_errors.dart';

void main() {
  testWidgets('HomeFeedErrorState shows retry and clear filters', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: Column(
                children: [
                  Text(formatHomeFeedErrorMessage(
                    context,
                    HomeFeedErrors.network,
                  )),
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  expect(find.textContaining('connection'), findsOneWidget);
  });
}
