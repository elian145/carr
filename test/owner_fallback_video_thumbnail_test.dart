// Widget tests for `OwnerFallbackVideoThumbnail` (see
// `lib/app/widgets/owner_fallback_video_thumbnail.dart`) -- video
// counterpart of `owner_fallback_hero_image_test.dart`. Uses
// `debugOwnerFallbackVideoRemoteProbeOverride` to control "did the
// remote thumbnail probe succeed" deterministically, without a real
// video file/network round trip.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:car_listing_app/app/widgets/owner_fallback_video_thumbnail.dart';
import 'package:car_listing_app/widgets/network_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A genuinely decodable 1x1 transparent PNG -- `Image.memory` needs real
/// image bytes (unlike this repo's `ListingHeroImage`/`CachedNetworkImage`
/// tests, which only ever inspect widget props before a real decode --
/// see `owner_fallback_hero_image_test.dart`'s own doc comment -- this
/// widget's confirmed-remote branch renders `Image.memory` directly, so a
/// fake, non-decodable byte array would surface as an uncaught image
/// decode exception).
Uint8List _fakeJpegBytes() => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

void main() {
  tearDown(() {
    debugOwnerFallbackVideoRemoteProbeOverride = null;
  });

  Future<void> pump(
    WidgetTester tester, {
    required String localUrl,
    String? remoteUrl,
    VoidCallback? onRemoteDisplayReady,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: OwnerFallbackVideoThumbnail(
          localUrl: localUrl,
          remoteUrl: remoteUrl,
          onRemoteDisplayReady: onRemoteDisplayReady,
        ),
      ),
    );
  }

  testWidgets(
    'State A/B: no remoteUrl yet -- renders the local video url via the '
    'normal preview widget, no probe',
    (tester) async {
      debugOwnerFallbackVideoRemoteProbeOverride = (url) async {
        fail('must not probe when remoteUrl is null');
      };
      await pump(tester, localUrl: '/tmp/local.mp4', remoteUrl: null);
      await tester.pump();

      final thumb = tester.widget<NetworkVideoThumbnailPreview>(
        find.byType(NetworkVideoThumbnailPreview),
      );
      expect(thumb.videoUrl, '/tmp/local.mp4');
    },
  );

  testWidgets(
    'State C: remoteUrl exists but probe not yet resolved -- keeps '
    'rendering the local video preview',
    (tester) async {
      final completer = Completer<Uint8List?>();
      debugOwnerFallbackVideoRemoteProbeOverride = (url) => completer.future;

      await pump(
        tester,
        localUrl: '/tmp/local.mp4',
        remoteUrl: 'https://cdn.example.com/remote.mp4',
      );
      await tester.pump();

      final thumb = tester.widget<NetworkVideoThumbnailPreview>(
        find.byType(NetworkVideoThumbnailPreview),
      );
      expect(thumb.videoUrl, '/tmp/local.mp4');
    },
  );

  testWidgets(
    'State D: remote thumbnail confirmed -- swaps to rendering the '
    'fetched remote bytes directly (no second fetch through the normal '
    'preview widget) and fires onRemoteDisplayReady exactly once',
    (tester) async {
      final completer = Completer<Uint8List?>();
      debugOwnerFallbackVideoRemoteProbeOverride = (url) => completer.future;
      var readyCount = 0;

      await pump(
        tester,
        localUrl: '/tmp/local.mp4',
        remoteUrl: 'https://cdn.example.com/remote.mp4',
        onRemoteDisplayReady: () => readyCount++,
      );
      await tester.pump();

      completer.complete(_fakeJpegBytes());
      await tester.pump();

      expect(
        find.byType(NetworkVideoThumbnailPreview),
        findsNothing,
        reason: 'once confirmed, renders the already-fetched bytes '
            'directly via Image.memory instead of re-triggering the '
            'preview widget\'s own fetch',
      );
      expect(find.byType(Image), findsOneWidget);
      expect(readyCount, 1);
    },
  );

  testWidgets(
    'State E: remote probe fails (null bytes) -- keeps rendering local, '
    'never calls onRemoteDisplayReady',
    (tester) async {
      debugOwnerFallbackVideoRemoteProbeOverride = (url) async => null;
      var readyCount = 0;

      await pump(
        tester,
        localUrl: '/tmp/local.mp4',
        remoteUrl: 'https://cdn.example.com/remote.mp4',
        onRemoteDisplayReady: () => readyCount++,
      );
      await tester.pump();
      await tester.pump();

      final thumb = tester.widget<NetworkVideoThumbnailPreview>(
        find.byType(NetworkVideoThumbnailPreview),
      );
      expect(thumb.videoUrl, '/tmp/local.mp4');
      expect(readyCount, 0);
    },
  );

  testWidgets(
    'requirement 9 fallback: local file unexpectedly missing (empty '
    'localUrl) -- renders remote directly via the normal path',
    (tester) async {
      debugOwnerFallbackVideoRemoteProbeOverride = (url) async {
        fail('must not probe when there is no local file to protect');
      };

      await pump(
        tester,
        localUrl: '',
        remoteUrl: 'https://cdn.example.com/remote.mp4',
      );
      await tester.pump();

      final thumb = tester.widget<NetworkVideoThumbnailPreview>(
        find.byType(NetworkVideoThumbnailPreview),
      );
      expect(thumb.videoUrl, 'https://cdn.example.com/remote.mp4');
    },
  );
}
