// Widget tests for `OwnerFallbackHeroImage` (see
// `lib/app/widgets/owner_fallback_hero_image.dart`) -- the optimistic-
// local-media fix's local<->remote swap widget. Uses
// `debugOwnerFallbackHeroRemoteProbeOverride` (a `@visibleForTesting`
// seam, same convention as `debugLogNonFatalOverride` in `app_log.dart`)
// to deterministically control "did the remote decode succeed" without
// needing real network image bytes -- mirrors this repo's own testing
// philosophy of asserting on which URL/widget is mounted rather than
// chasing genuine pixel decodes (see `sell_blur_preview_progressive_
// lifecycle_test.dart`'s own doc comment on the same point).
import 'dart:async';

import 'package:car_listing_app/app/widgets/listing_hero_image.dart';
import 'package:car_listing_app/app/widgets/owner_fallback_hero_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    debugOwnerFallbackHeroRemoteProbeOverride = null;
  });

  Future<void> pump(
    WidgetTester tester, {
    required String localUrl,
    String? remoteUrl,
    VoidCallback? onRemoteDisplayReady,
    Key? key,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: OwnerFallbackHeroImage(
          key: key,
          localUrl: localUrl,
          remoteUrl: remoteUrl,
          onRemoteDisplayReady: onRemoteDisplayReady,
        ),
      ),
    );
  }

  testWidgets(
    'State A/B: no remoteUrl yet -- renders the local url, no probe',
    (tester) async {
      debugOwnerFallbackHeroRemoteProbeOverride = (url) async {
        fail('must not probe when remoteUrl is null');
      };
      await pump(tester, localUrl: '/tmp/local.jpg', remoteUrl: null);
      await tester.pump();

      final hero = tester.widget<ListingHeroImage>(
        find.byType(ListingHeroImage),
      );
      expect(hero.url, '/tmp/local.jpg');
    },
  );

  testWidgets(
    'State C: remoteUrl exists but not yet confirmed loadable -- keeps '
    'rendering local (never blanks the tile while the probe is pending)',
    (tester) async {
      final completer = Completer<bool>();
      debugOwnerFallbackHeroRemoteProbeOverride = (url) => completer.future;

      await pump(
        tester,
        localUrl: '/tmp/local.jpg',
        remoteUrl: 'https://cdn.example.com/remote.jpg',
      );
      await tester.pump();

      final hero = tester.widget<ListingHeroImage>(
        find.byType(ListingHeroImage),
      );
      expect(
        hero.url,
        '/tmp/local.jpg',
        reason: 'still local while the remote probe is unresolved',
      );
    },
  );

  testWidgets(
    'State D: remote confirmed loadable -- atomically swaps to the '
    'remote url and fires onRemoteDisplayReady exactly once',
    (tester) async {
      final completer = Completer<bool>();
      debugOwnerFallbackHeroRemoteProbeOverride = (url) => completer.future;
      var readyCount = 0;

      await pump(
        tester,
        localUrl: '/tmp/local.jpg',
        remoteUrl: 'https://cdn.example.com/remote.jpg',
        onRemoteDisplayReady: () => readyCount++,
      );
      await tester.pump();

      completer.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final hero = tester.widget<ListingHeroImage>(
        find.byType(ListingHeroImage),
      );
      expect(hero.url, 'https://cdn.example.com/remote.jpg');
      expect(readyCount, 1);
    },
  );

  testWidgets(
    'State E: remote probe fails -- keeps rendering local, never calls '
    'onRemoteDisplayReady',
    (tester) async {
      debugOwnerFallbackHeroRemoteProbeOverride = (url) async => false;
      var readyCount = 0;

      await pump(
        tester,
        localUrl: '/tmp/local.jpg',
        remoteUrl: 'https://cdn.example.com/remote.jpg',
        onRemoteDisplayReady: () => readyCount++,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final hero = tester.widget<ListingHeroImage>(
        find.byType(ListingHeroImage),
      );
      expect(hero.url, '/tmp/local.jpg');
      expect(readyCount, 0);
    },
  );

  testWidgets(
    'never shows a blank/spinner-only tile: exactly one ListingHeroImage '
    'is mounted at every stage (before, during, and after the remote '
    'swap)',
    (tester) async {
      final completer = Completer<bool>();
      debugOwnerFallbackHeroRemoteProbeOverride = (url) => completer.future;

      await pump(
        tester,
        localUrl: '/tmp/local.jpg',
        remoteUrl: 'https://cdn.example.com/remote.jpg',
      );
      await tester.pump();
      expect(find.byType(ListingHeroImage), findsOneWidget);

      completer.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(ListingHeroImage), findsOneWidget);
    },
  );

  testWidgets(
    'requirement 9 fallback: local file unexpectedly missing (empty '
    'localUrl) -- renders remote directly via the normal path instead of '
    'crashing',
    (tester) async {
      debugOwnerFallbackHeroRemoteProbeOverride = (url) async {
        fail('must not probe when there is no local file to protect');
      };

      await pump(
        tester,
        localUrl: '',
        remoteUrl: 'https://cdn.example.com/remote.jpg',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final hero = tester.widget<ListingHeroImage>(
        find.byType(ListingHeroImage),
      );
      expect(hero.url, 'https://cdn.example.com/remote.jpg');
    },
  );

  testWidgets(
    'a superseded remoteUrl (widget rebuilds with a NEW remoteUrl before '
    'the old probe resolved) never lets the stale probe result apply',
    (tester) async {
      final firstCompleter = Completer<bool>();
      final secondCompleter = Completer<bool>();
      var callCount = 0;
      debugOwnerFallbackHeroRemoteProbeOverride = (url) {
        callCount++;
        return callCount == 1 ? firstCompleter.future : secondCompleter.future;
      };

      await pump(
        tester,
        localUrl: '/tmp/local.jpg',
        remoteUrl: 'https://cdn.example.com/remote_v1.jpg',
      );
      await tester.pump();

      // A fresh remoteUrl arrives before the first probe ever resolves.
      await pump(
        tester,
        localUrl: '/tmp/local.jpg',
        remoteUrl: 'https://cdn.example.com/remote_v2.jpg',
      );
      await tester.pump();

      // The stale v1 probe finally resolves -- must be ignored.
      firstCompleter.complete(true);
      await tester.pump();

      final heroAfterStaleResolve = tester.widget<ListingHeroImage>(
        find.byType(ListingHeroImage),
      );
      expect(
        heroAfterStaleResolve.url,
        '/tmp/local.jpg',
        reason: 'the stale v1 probe result must not swap to v1 once v2 is '
            'the current remoteUrl',
      );

      secondCompleter.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final heroAfterRealResolve = tester.widget<ListingHeroImage>(
        find.byType(ListingHeroImage),
      );
      expect(
        heroAfterRealResolve.url,
        'https://cdn.example.com/remote_v2.jpg',
      );
    },
  );
}
