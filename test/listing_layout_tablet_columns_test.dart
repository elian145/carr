import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/prefs/listing_layout_prefs.dart';
import 'package:car_listing_app/shared/ui/responsive.dart';

void main() {
  group('ListingLayoutPrefs.effectiveColumnsForWidth (UI-04)', () {
    test('list mode stays single column at any width', () {
      expect(ListingLayoutPrefs.effectiveColumnsForWidth(1, 1200), 1);
      expect(ListingLayoutPrefs.effectiveColumnsForWidth(1, 320), 1);
    });

    test('grid stays two columns on narrow phones when user picks grid', () {
      expect(ListingLayoutPrefs.effectiveColumnsForWidth(2, 320), 2);
      expect(ListingLayoutPrefs.effectiveColumnsForWidth(2, 330), 2);
      expect(ListingLayoutPrefs.effectiveColumnsForWidth(2, 390), 2);
      expect(ListingLayoutPrefs.effectiveColumnsForWidth(2, 719), 2);
      expect(ListingLayoutPrefs.effectiveColumnsForWidth(2, 720), 3);
      expect(ListingLayoutPrefs.effectiveColumnsForWidth(2, 999), 3);
      expect(ListingLayoutPrefs.effectiveColumnsForWidth(2, 1000), 4);
    });

    test('narrow two-column grid uses card aspect ratio not list ratio', () {
      expect(
        ListingLayoutPrefs.gridChildAspectRatioForWidth(2, 330),
        0.59,
      );
      expect(
        ListingLayoutPrefs.gridChildAspectRatioForWidth(2, 310),
        0.57,
      );
    });

    test('tablet grid aspect ratios stay card-shaped', () {
      expect(
        ListingLayoutPrefs.gridChildAspectRatioForWidth(3, 800),
        0.68,
      );
      expect(
        ListingLayoutPrefs.gridChildAspectRatioForWidth(4, 1100),
        0.70,
      );
    });
  });

  group('AppResponsive tablet helpers (UI-04)', () {
    testWidgets('isTablet / pagePadding / constrainContent', (tester) async {
      var tablet = false;
      var padPhone = EdgeInsets.zero;
      var padTablet = EdgeInsets.zero;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 800)),
            child: Builder(
              builder: (context) {
                tablet = AppResponsive.isTablet(context);
                padPhone = AppResponsive.pagePadding(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(tablet, isFalse);
      expect(padPhone.horizontal, 32); // 16 * 2

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(900, 1200)),
            child: Builder(
              builder: (context) {
                tablet = AppResponsive.isTablet(context);
                padTablet = AppResponsive.pagePadding(context);
                return AppResponsive.constrainContent(
                  const SizedBox(height: 10, child: Text('form')),
                );
              },
            ),
          ),
        ),
      );
      expect(tablet, isTrue);
      expect(padTablet.left, 24);
      expect(find.text('form'), findsOneWidget);
    });
  });
}
