// CarNet V1 feature-completeness batch 2 -- item 3 (rejected/hidden vs
// pending listing status UX).
//
// Bug: `isListingPendingReview`/`listingShowsPendingBadge` lumped
// `pending`, `draft`, AND `hidden` together, so a listing an admin hid
// after moderation rendered the exact same amber "Under review" badge as a
// brand-new listing that had simply never been reviewed yet -- a seller
// could not tell the two apart, and `MyListingsPage` had no way to filter
// down to just the hidden ones.
//
// Fix: `isListingPending`/`isListingHidden` (lib/shared/listings/
// listing_status.dart) are now distinct, `buildListingStatusBadge` renders
// a red "Hidden" badge for a hidden listing vs. the amber "Under review"
// badge for pending/draft, and `MyListingsPage` gained a "Hidden" filter
// tab + explainer banner + empty state (mirroring the existing "Pending"
// ones). No rejection *reason* is fabricated -- the backend does not store
// one (`Car` has no such column), so only the hidden/pending distinction
// itself is surfaced.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/listings/listing_status.dart';

import 'fake_api_server.dart';

Map<String, dynamic> _car(String id, {required String status}) => {
      'id': id,
      'public_id': id,
      'title': 'Test car $id',
      'brand': 'toyota',
      'model': 'camry',
      'year': 2020,
      'price': 10000,
      'currency': 'USD',
      'location': 'Erbil',
      'image_url': '',
      'images': <dynamic>[],
      'videos': <dynamic>[],
      'status': status,
      'seller': {'id': 'seller_1', 'username': 'seller'},
    };

void main() {
  group('isListingPending / isListingHidden (unit)', () {
    test('pending and draft are "pending", not "hidden"', () {
      expect(isListingPending({'status': 'pending'}), isTrue);
      expect(isListingPending({'status': 'draft'}), isTrue);
      expect(isListingPending({'status': 'hidden'}), isFalse);
      expect(isListingHidden({'status': 'pending'}), isFalse);
      expect(isListingHidden({'status': 'draft'}), isFalse);
    });

    test('hidden is "hidden", not "pending"', () {
      expect(isListingHidden({'status': 'hidden'}), isTrue);
      expect(isListingPending({'status': 'hidden'}), isFalse);
    });

    test('active/sold are neither pending nor hidden', () {
      for (final status in ['active', 'sold']) {
        expect(isListingPending({'status': status}), isFalse);
        expect(isListingHidden({'status': status}), isFalse);
      }
    });

    test(
      'isListingPendingReview stays a superset (pending OR hidden) for '
      'existing call sites that only care "is this publicly visible"',
      () {
        expect(isListingPendingReview({'status': 'pending'}), isTrue);
        expect(isListingPendingReview({'status': 'draft'}), isTrue);
        expect(isListingPendingReview({'status': 'hidden'}), isTrue);
        expect(isListingPendingReview({'status': 'active'}), isFalse);
        expect(isListingPendingReview({'status': 'sold'}), isFalse);
      },
    );
  });

  group('MyListingsPage hidden vs pending UX (widget)', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await FakeApiServer.ensureStarted();
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({'push_enabled': false});
      await ApiService.clearTokens();
      await AuthService().adoptTestSession(
        user: {
          'id': 1,
          'username': 'seller',
          'is_admin': false,
          'is_verified': true,
          'account_type': 'individual',
        },
      );
    });

    tearDown(() async {
      await ApiService.clearTokens();
      AuthService().resetTestSession();
      FakeApiServer.myListingsByStatus = null;
    });

    tearDownAll(() async {
      await FakeApiServer.stop();
    });

    // The "Hidden" filter *chip* and the red "Hidden" status *badge* share
    // the same fallback label text, so plain `find.text('Hidden')` matches
    // both. The badge (see `_buildStatusBadge` in
    // `listing_pending_badge.dart`) is the only "Hidden" text rendered in
    // bold white -- use that to find it unambiguously.
    Finder hiddenBadgeFinder() => find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data == 'Hidden' &&
              w.style?.color == Colors.white &&
              w.style?.fontWeight == FontWeight.w800,
        );

    Future<void> openMyListings(WidgetTester tester) async {
      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed('/my_listings');
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Active').evaluate().isNotEmpty) break;
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
      'the "All" tab shows a red Hidden badge for a hidden listing and an '
      'amber Under review badge for a pending one -- not the same badge',
      (tester) async {
        FakeApiServer.myListingsByStatus = {
          '': [_car('p1', status: 'pending'), _car('h1', status: 'hidden')],
        };
        await openMyListings(tester);

        expect(find.text('Under review'), findsOneWidget);
        expect(hiddenBadgeFinder(), findsOneWidget);
      },
    );

    testWidgets(
      'switching to the Hidden filter tab requests status=hidden and shows '
      'the hidden-specific explainer banner',
      (tester) async {
        FakeApiServer.myListingsByStatus = {
          '': [_car('p1', status: 'pending')],
          'hidden': [_car('h1', status: 'hidden')],
        };
        await openMyListings(tester);
        expect(find.text('Under review'), findsOneWidget);

        // The filter chip row scrolls horizontally; Hidden sits after
        // Pending, so scroll it into view like the existing Draft-tab test.
        await tester.drag(
          find.byKey(const ValueKey<String>('my-listings-filter-list')),
          const Offset(-300, 0),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey<String>('my-listings-filter-hidden')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Now only the hidden car is shown (fetched with status=hidden).
        expect(find.text('Under review'), findsNothing);
        expect(hiddenBadgeFinder(), findsOneWidget);
        expect(
          find.textContaining('hidden by our moderation team'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the Hidden filter tab empty state does not fabricate a reason',
      (tester) async {
        FakeApiServer.myListingsByStatus = {'': [], 'hidden': []};
        await openMyListings(tester);

        await tester.drag(
          find.byKey(const ValueKey<String>('my-listings-filter-list')),
          const Offset(-300, 0),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey<String>('my-listings-filter-hidden')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('No hidden listings'), findsOneWidget);
      },
    );
  });
}
