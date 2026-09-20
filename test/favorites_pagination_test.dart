// CarNet V1 feature-completeness batch 2 -- item 2 (favorites pagination).
//
// Bug: the backend's `GET /api/user/favorites` was already paginated
// (`{cars, pagination: {has_next, page, per_page}}`), but the Flutter
// Favorites page (`lib/pages/production_favorites_page.dart`) always
// requested page 1 and never loaded page 2+, so a user with more than one
// page of favorites could never see the rest.
//
// Fix: `_FavoritesPageState` now mirrors the same load-more pattern used by
// `MyListingsPage`/`ChatNotificationsPage` -- a `ScrollController` that
// requests the next page near the bottom, a footer spinner while
// `_loadingMore`, `_hasNext` end-of-list tracking, de-duped appends, and
// pull-to-refresh resetting back to page 1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

Map<String, dynamic> _favoriteCar(String id, {required String favoritedAt}) => {
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
      'favorited_at': favoritedAt,
      'seller': {'id': 'seller_1', 'username': 'seller'},
    };

/// [count] favorites, newest-favorited first (matches backend ordering), so
/// a default `per_page=20` split yields a full page 1 (20) + a partial page
/// 2 with `has_next: false` on that final page.
List<Map<String, dynamic>> _manyFavorites(int count) => List.generate(
      count,
      (i) => _favoriteCar(
        'fav_$i',
        favoritedAt: DateTime(2026, 1, 1)
            .subtract(Duration(minutes: i))
            .toIso8601String(),
      ),
    );

/// The real (scrollable) favorites grid -- distinct from the shrink-wrapped,
/// non-scrollable `GridView` the loading skeleton renders underneath it.
Finder _favoritesGridFinder() => find.byWidgetPredicate(
      (w) => w is GridView && w.physics is AlwaysScrollableScrollPhysics,
    );

/// `GridView.builder`'s item count (real favorites + 1 more for the
/// load-more footer spinner when `_hasNext` is true) read straight off the
/// widget's build delegate -- robust to `GridView.builder` only actually
/// *building* the handful of items that fit on screen.
int _favoritesGridItemCount(WidgetTester tester) {
  final gridView = tester.widget<GridView>(_favoritesGridFinder());
  final delegate = gridView.childrenDelegate;
  expect(delegate, isA<SliverChildBuilderDelegate>());
  return (delegate as SliverChildBuilderDelegate).childCount!;
}

Future<void> _scrollGridToBottom(WidgetTester tester) async {
  final gridView = tester.widget<GridView>(_favoritesGridFinder());
  final controller = gridView.controller!;
  controller.jumpTo(controller.position.maxScrollExtent);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
    await ApiService.clearTokens();
    await AuthService().adoptTestSession(
      user: {
        'id': 1,
        'username': 'buyer',
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.favoritesAllItems = null;
    FakeApiServer.favoritesRequestedPages.clear();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Future<void> openFavorites(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/favorites');
    await tester.pump();
    // Wait for the initial page-1 fetch to resolve and the skeleton loader
    // to be replaced by the real grid/empty state.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (_favoritesGridFinder().evaluate().isNotEmpty ||
          find.byIcon(Icons.favorite_border).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('initial load shows page 1 (20 of 25 favorites) plus a '
      'load-more footer since has_next is true', (tester) async {
    FakeApiServer.favoritesAllItems = _manyFavorites(25);
    await openFavorites(tester);

    expect(FakeApiServer.favoritesRequestedPages, [1]);
    // 20 real cards + 1 footer spinner slot.
    expect(_favoritesGridItemCount(tester), 21);
  });

  testWidgets(
    'scrolling near the bottom loads page 2 and appends it with no '
    'duplicates',
    (tester) async {
      FakeApiServer.favoritesAllItems = _manyFavorites(25);
      await openFavorites(tester);
      expect(_favoritesGridItemCount(tester), 21);

      await _scrollGridToBottom(tester);

      expect(FakeApiServer.favoritesRequestedPages, [1, 2]);
      // All 25 favorites now in the list exactly once each (has_next is now
      // false on the final/short page, so no more footer slot).
      expect(_favoritesGridItemCount(tester), 25);
    },
  );

  testWidgets(
    'end of list: after the last page loads, scrolling again does not '
    'request more pages',
    (tester) async {
      FakeApiServer.favoritesAllItems = _manyFavorites(25);
      await openFavorites(tester);
      await _scrollGridToBottom(tester);
      expect(FakeApiServer.favoritesRequestedPages, [1, 2]);
      expect(_favoritesGridItemCount(tester), 25);

      await _scrollGridToBottom(tester);
      expect(FakeApiServer.favoritesRequestedPages, [1, 2]);
      expect(_favoritesGridItemCount(tester), 25);
    },
  );

  testWidgets('pull-to-refresh resets pagination back to page 1', (
    tester,
  ) async {
    FakeApiServer.favoritesAllItems = _manyFavorites(25);
    await openFavorites(tester);
    await _scrollGridToBottom(tester);
    expect(FakeApiServer.favoritesRequestedPages, [1, 2]);
    expect(_favoritesGridItemCount(tester), 25);

    // Pull-to-refresh only triggers from the top of the scroll view.
    final gridView = tester.widget<GridView>(_favoritesGridFinder());
    gridView.controller!.jumpTo(0);
    await tester.pump();

    await tester.fling(_favoritesGridFinder(), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // Refresh re-requested page 1 (pagination reset, not resumed at page 3).
    expect(FakeApiServer.favoritesRequestedPages.last, 1);
    // A full 25-item catalog still only has 20 on the (reset) first page,
    // plus the load-more footer slot.
    expect(_favoritesGridItemCount(tester), 21);
  });

  testWidgets(
    'a single short page (fewer than per_page items) has no load-more '
    'footer slot and only one request is made',
    (tester) async {
      FakeApiServer.favoritesAllItems = _manyFavorites(3);
      await openFavorites(tester);

      expect(_favoritesGridItemCount(tester), 3);

      await _scrollGridToBottom(tester);
      expect(FakeApiServer.favoritesRequestedPages, [1]);
      expect(_favoritesGridItemCount(tester), 3);
    },
  );

  testWidgets('no favorites shows the empty state, not a spinner forever', (
    tester,
  ) async {
    FakeApiServer.favoritesAllItems = _manyFavorites(0);
    await openFavorites(tester);

    expect(find.byIcon(Icons.favorite_border), findsWidgets);
    expect(_favoritesGridFinder(), findsNothing);
  });
}
