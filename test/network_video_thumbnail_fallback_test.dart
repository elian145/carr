import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/media/remote_video_thumbnail.dart';
import 'package:car_listing_app/widgets/network_video_thumbnail.dart';

/// 1x1 PNG (any decodable image works as the "thumbnail").
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  const url = 'https://cdn.example.com/v/hero.mp4';

  tearDown(RemoteVideoThumbnail.debugReset);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
  }

  testWidgets(
    'hero preview shows an actual thumbnail when 800 ms fails and 0 ms works',
    (tester) async {
      final calls = <int>[];
      RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
        calls.add(t);
        if (t == 800) throw MissingPluginException('data');
        return _tinyPng;
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 200,
            height: 300,
            child: NetworkVideoThumbnailPreview(
              videoUrl: url,
              fillParent: true,
            ),
          ),
        ),
      );
      await settle(tester);

      expect(calls, [800, 0]);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsNothing);
    },
  );

  testWidgets(
    'hero preview keeps the placeholder when no frame can be produced, and '
    'a rebuild inside the backoff window does not call the plugin again',
    (tester) async {
      var calls = 0;
      RemoteVideoThumbnail.debugFetcherOverride = (v, h, t, w) async {
        calls++;
        throw MissingPluginException('data');
      };
      Widget host(Key k) => MaterialApp(
            home: SizedBox(
              width: 200,
              height: 300,
              child: NetworkVideoThumbnailPreview(
                key: k,
                videoUrl: url,
                fillParent: true,
              ),
            ),
          );

      await tester.pumpWidget(host(const ValueKey('a')));
      await settle(tester);
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(calls, 2);

      await tester.pumpWidget(host(const ValueKey('b'))); // fresh state
      await settle(tester);
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(calls, 2, reason: 'throttled: no new native calls');
    },
  );
}
