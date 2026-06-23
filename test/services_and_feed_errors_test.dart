import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_feed_errors.dart';
import 'package:car_listing_app/shared/errors/network_error.dart';
import 'package:car_listing_app/services/deep_link_navigation.dart';
import 'package:car_listing_app/services/websocket_service.dart';

void main() {
  group('HomeFeedErrors', () {
    test('network and server keys are stable', () {
      expect(HomeFeedErrors.network, 'feed:network');
      expect(HomeFeedErrors.server(503), 'feed:server:503');
    });
  });

  group('isNetworkTransportError', () {
    test('detects socket and handshake failures', () {
      expect(
        isNetworkTransportError(Exception('SocketException: failed')),
        isTrue,
      );
      expect(
        isNetworkTransportError(Exception('HandshakeException: cert')),
        isTrue,
      );
      expect(isNetworkTransportError(Exception('404 Not Found')), isFalse);
    });
  });

  group('resolveDeepLinkTarget', () {
    test('carzo listing scheme', () {
      final target = resolveDeepLinkTarget(
        Uri.parse('carzo://listing?id=abc123'),
      );
      expect(target?.route, '/car_detail');
      expect(target?.arguments['carId'], 'abc123');
    });

    test('reset password with token', () {
      final target = resolveDeepLinkTarget(
        Uri.parse('carzo://auth/reset-password?token=secret'),
      );
      expect(target?.route, '/reset-password');
      expect(target?.arguments['token'], 'secret');
    });

    test('unknown URI returns null', () {
      expect(
        resolveDeepLinkTarget(Uri.parse('https://example.com/unknown')),
        isNull,
      );
    });
  });

  group('parseApiDateTime', () {
    test('parses UTC naive timestamps as local', () {
      final dt = parseApiDateTime('2024-06-01T12:00:00');
      expect(dt.year, 2024);
      expect(dt.month, 6);
      expect(dt.day, 1);
    });

    test('empty input falls back to now', () {
      final before = DateTime.now();
      final dt = parseApiDateTime('');
      final after = DateTime.now();
      expect(
        dt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        dt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });
}
