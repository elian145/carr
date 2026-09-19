import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_flow.dart' show HomePage;
import 'package:car_listing_app/l10n/app_localizations.dart';

import 'fake_api_server.dart';

/// Regression coverage for the RC smoke-test finding: tapping Home's Search
/// pill used to feel delayed because the destination's first `build()`
/// eagerly constructed every filter section (via a non-lazy
/// `ListView(children: ...)`) before the very first frame could be
/// painted.
///
/// This does NOT assert on timing (fragile) — instead it proves the fix's
/// actual mechanism: with a lazy `ListView.builder`, a section far below
/// the initial viewport must not exist anywhere in the widget tree until
/// the user scrolls that far, while an early section (and the page's own
/// title/keyword field) must exist immediately.
///
/// Uses the page's public `HomePage.searchFilters()` constructor (see
/// `home_page.dart`) — the same "Search Cars" full-page filters UI reached
/// via `_openHomeSearchFiltersPage` — so this stays a focused widget test
/// without needing to drive Home's own feed/network setup.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Widget harness() {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomePage.searchFilters(),
    );
  }

  testWidgets(
    'opens directly into the Search Cars page with the keyword field ready '
    '(no unrelated intermediate page)',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Search Cars'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    },
  );

  testWidgets(
    'renders the page shell (title/close/keyword field/footer) on the very '
    'first frame, and defers the filter-section list to the frame right '
    'after — instead of paying for its build cost before the route can '
    'even appear',
    (tester) async {
      // `pumpWidget` itself already performs the route's first frame — an
      // extra explicit `pump()` here would let the post-frame callback
      // that flips `_searchFiltersShellReady` take effect *before* the
      // assertions below, defeating the point of this test.
      await tester.pumpWidget(harness());

      // The shell — everything that does not depend on the filter-section
      // list — must already be on screen immediately.
      expect(find.text('Search Cars'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);

      // The filter-section list itself (make/brand row, price/year/mileage
      // cards, ...) must not be built yet on this very first frame — this
      // is the actual first-open delay this fix removes.
      expect(
        find.text('Year Range'),
        findsNothing,
        reason:
            'The filter-section list must not be built on the same frame '
            'as the route\'s first paint — that upfront build cost (e.g. '
            'brand-logo image decode in the make section) is exactly what '
            'made the first open of this page feel delayed.',
      );

      // The very next frame (the post-frame callback set up on the first
      // frame flips the ready flag and calls `setState`) must reveal the
      // real section list — laziness only delays it by one frame, it must
      // never lose it.
      await tester.pump();
      expect(find.text('Year Range'), findsOneWidget);
    },
  );

  testWidgets(
    'builds only visible/near-visible sections up front and defers a '
    'clearly off-screen section until scrolled into view',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Early essential section ("Year Range", the 2nd filter card right
      // after Make/Price) — comfortably inside the first viewport, so it
      // must already be built.
      expect(
        find.text('Year Range'),
        findsOneWidget,
        reason:
            'An early filter section must already be built on the very '
            'first frame — laziness must not delay sections that are '
            'actually near the top of the list.',
      );

      // "Plate city" is the second-to-last section (index ~14 of ~16),
      // several screens below the initial viewport — a clearly
      // off-screen section that a lazy ListView.builder must not have
      // built yet.
      expect(
        find.text('PLATE CITY'),
        findsNothing,
        reason:
            'A section far below the initial viewport must not be built '
            'until the user scrolls to it — this is the exact eager-build '
            'regression this fix addresses (previously a plain '
            'ListView(children: ...) built every section up front).',
      );

      // Scroll the filters page's own (vertical) ListView down far enough
      // to reach the end. Some already-built sections (fuel type, body
      // type, ...) contain their own horizontal `ListView`s for the icon
      // tiles, so the outer vertical one must be targeted explicitly.
      final verticalListFinder = find.byWidgetPredicate(
        (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
      );
      expect(verticalListFinder, findsOneWidget);
      await tester.drag(verticalListFinder, const Offset(0, -4000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('PLATE CITY'),
        findsOneWidget,
        reason:
            'Once scrolled into view, the deferred section must build '
            'normally — laziness must only delay construction, never '
            'drop a section.',
      );
    },
  );
}
