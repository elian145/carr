import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/prefs/listing_layout_prefs.dart';
import 'package:car_listing_app/shared/ui/responsive.dart';

void main() {
  test('grid card ratios keep the white details area compact', () {
    expect(ListingLayoutPrefs.gridChildAspectRatio(2), 0.66);
    expect(ListingLayoutPrefs.gridChildAspectRatioForWidth(2, 370), 0.63);
  });

  testWidgets('listing grid uses a 4:3 cover frame', (tester) async {
    late List<double> imageHeights;
    late double horizontalImageWidth;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            imageHeights = [168.0, 200.0, 300.0]
                .map(
                  (width) => AppResponsive.listingGridImageHeight(
                    context,
                    cardWidth: width,
                  ),
                )
                .toList();
            horizontalImageWidth = AppResponsive.listingHorizontalImageWidth(
              context,
              cardWidth: 390,
              cardHeight: 153,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(imageHeights, [126, 150, 225]);
    expect(horizontalImageWidth, closeTo(179.4, 0.01));
  });
}
