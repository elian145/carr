import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_flow.dart' show HomePage;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/navigation/app_page_route.dart';

import 'fake_api_server.dart';

/// Regression coverage for the RC smoke-test finding: tapping Home's Search
/// pill used to feel delayed because the destination's first `build()`
/// eagerly constructed every filter section (via a non-lazy
/// `ListView(children: ...)`) before the very first frame could be
/// painted.
///
/// Round 1 of this fix (deferring the section list by exactly one frame)
/// was insufficient: on a real device the section list's own expensive
/// first build (brand-logo image decode, ...) still competed for frames
/// with the route's *own push transition*, which was still animating in
/// at that point. Round 2 (covered below) instead watches the pushed
/// route's own entrance-transition `Animation` and only builds the section
/// list once it reports `AnimationStatus.completed`.
///
/// None of this asserts on wall-clock timing (fragile) — instead it proves
/// the fix's actual mechanism structurally:
///   - the page shell (title/keyword field) and the filter-section list's
///     build state are asserted directly against the real push route's own
///     `Animation.status`, not a guessed delay;
///   - with a lazy `ListView.builder`, a section far below the initial
///     viewport must not exist anywhere in the widget tree until the user
///     scrolls that far, while an early section must exist as soon as the
///     transition completes.
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
    'while a real push transition into the Search Cars page is still '
    'animating, the shell (title/keyword field) is already visible but the '
    'filter-section list stays unbuilt — it only builds once the route\'s '
    'own entrance Animation reports AnimationStatus.completed',
    (tester) async {
      late final AppPageRoute<void> searchRoute;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          // A plain first screen with a real push, matching how Home
          // actually opens this page via `_openHomeSearchFiltersPage`
          // (an `AppPageRoute` pushed on top of an already-settled route)
          // — unlike `harness()` above, whose `HomePage.searchFilters()`
          // is the app's *initial* route and therefore never has a real
          // entrance transition to observe.
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    searchRoute = AppPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => const HomePage.searchFilters(),
                    );
                    Navigator.of(context).push(searchRoute);
                  },
                  child: const Text('Open Search'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Search'));
      // The first pump pushes the route and starts its entrance
      // transition; the second (zero-duration, so it does not itself
      // advance the transition) lets the new route's own localization
      // delegates resolve — the same two-step settle the very first test
      // above needs before it can find any of this page's text.
      await tester.pump();
      await tester.pump();

      final animation = searchRoute.animation!;
      expect(
        animation.status,
        AnimationStatus.forward,
        reason:
            'Sanity check: the transition must genuinely still be running '
            'for the assertions below to prove anything about it.',
      );

      // The shell — everything that does not depend on the filter-section
      // list — must already be on screen immediately, mid-transition.
      expect(find.text('Search Cars'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);

      // The filter-section list itself (make/brand row, price/year/mileage
      // cards, ...) must not be built yet — this is the actual first-open
      // jank this fix removes: it must never compete with the transition
      // itself for frames.
      expect(
        find.text('Year Range'),
        findsNothing,
        reason:
            'The filter-section list must not be built while the route\'s '
            'own push transition is still animating — that upfront build '
            'cost (e.g. brand-logo image decode in the make section) is '
            'exactly what made the first open of this page feel delayed.',
      );

      // Still short of the transition's own (real, not guessed) duration:
      // the section list must remain unbuilt.
      await tester.pump(searchRoute.transitionDuration ~/ 2);
      expect(animation.status, AnimationStatus.forward);
      expect(find.text('Year Range'), findsNothing);

      // Cross the transition's own duration: once the Animation reports
      // `completed`, the section list must build on that same frame —
      // laziness only delays it, it must never lose it.
      await tester.pump(searchRoute.transitionDuration);
      expect(animation.status, AnimationStatus.completed);
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
