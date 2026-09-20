// Item 9 (CarNet V1 batch): push notification taps must open the specific
// chat conversation / listing the payload points at (reusing the existing
// `/chat/conversation` and `/car_detail` named routes), fall back gracefully
// for legacy/unknown payloads, and never throw on missing/invalid ids.
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/push_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('chat_message notifications', () {
    test('routes to the specific conversation when car_id + sender_id are present', () {
      final dest = PushNotificationService.debugResolveNotificationDestination({
        'type': 'chat_message',
        'car_id': 'car-123',
        'sender_id': 'user-456',
      });
      expect(dest, isNotNull);
      expect(dest!.route, '/chat/conversation');
      expect(dest.arguments, {'carId': 'car-123', 'receiverId': 'user-456'});
    });

    test('omits receiverId when sender_id is missing', () {
      final dest = PushNotificationService.debugResolveNotificationDestination({
        'type': 'chat_message',
        'car_id': 'car-123',
      });
      expect(dest!.route, '/chat/conversation');
      expect(dest.arguments, {'carId': 'car-123'});
    });

    test('falls back to the generic chat list when car_id is missing', () {
      final dest = PushNotificationService.debugResolveNotificationDestination({
        'type': 'chat_message',
        'sender_id': 'user-456',
      });
      expect(dest!.route, '/chat');
      expect(dest.arguments, isNull);
    });

    test('an untyped payload with only sender_id is still treated as chat', () {
      final dest = PushNotificationService.debugResolveNotificationDestination({
        'sender_id': 'user-456',
        'car_id': 'car-789',
      });
      expect(dest!.route, '/chat/conversation');
      expect(dest.arguments, {'carId': 'car-789', 'receiverId': 'user-456'});
    });
  });

  group('listing-specific notifications (saved search / price drop)', () {
    test('opens the specific listing via car_detail when only car_id is present', () {
      final dest = PushNotificationService.debugResolveNotificationDestination({
        'car_id': 'car-999',
        'saved_search_id': 'search-1',
      });
      expect(dest!.route, '/car_detail');
      expect(dest.arguments, {'carId': 'car-999'});
    });

    test('price_drop payload (car_id + prices, no type) opens the listing', () {
      final dest = PushNotificationService.debugResolveNotificationDestination({
        'car_id': 'car-321',
        'old_price': '20000',
        'new_price': '18000',
      });
      expect(dest!.route, '/car_detail');
      expect(dest.arguments, {'carId': 'car-321'});
    });
  });

  group('dealer_application notifications', () {
    test('routes to /profile regardless of other fields', () {
      final dest = PushNotificationService.debugResolveNotificationDestination({
        'type': 'dealer_application',
        'car_id': 'ignored',
      });
      expect(dest!.route, '/profile');
      expect(dest.arguments, isNull);
    });
  });

  group('legacy / unknown payloads', () {
    test('a completely empty payload falls back to the generic chat list', () {
      final dest = PushNotificationService.debugResolveNotificationDestination(
        const {},
      );
      expect(dest!.route, '/chat');
      expect(dest.arguments, isNull);
    });

    test('an unrecognized type with no usable id is a safe no-op', () {
      final dest = PushNotificationService.debugResolveNotificationDestination({
        'type': 'some_future_notification_type',
      });
      expect(dest, isNull);
    });

    test('non-string / malformed id values never throw and are treated as missing', () {
      expect(
        () => PushNotificationService.debugResolveNotificationDestination({
          'type': 'chat_message',
          'car_id': '',
          'sender_id': '   ',
        }),
        returnsNormally,
      );
      final dest = PushNotificationService.debugResolveNotificationDestination({
        'type': 'chat_message',
        'car_id': '',
        'sender_id': '   ',
      });
      expect(dest!.route, '/chat');
    });
  });
}
