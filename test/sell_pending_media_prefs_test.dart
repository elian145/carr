import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:car_listing_app/shared/prefs/sell_pending_media_prefs.dart';

void main() {
  test('jsonSafeMediaList encodes XFiles and maps for pending prefs', () {
    final safe = SellPendingMediaPrefs.jsonSafeMediaList([
      XFile(r'C:\tmp\photo.jpg'),
      {
        'source': r'C:\tmp\other.jpg',
        'focus_y': 0.4,
        'image_width': 1200,
        'image_height': 800,
        'id': 42,
      },
      'uploads/car_photos/a.jpg',
    ]);

    expect(safe, hasLength(3));
    expect(safe[0], r'C:\tmp\photo.jpg');
    expect(safe[1], isA<Map>());
    final map = Map<String, dynamic>.from(safe[1] as Map);
    expect(map['source'], r'C:\tmp\other.jpg');
    expect(map['focus_y'], 0.4);
    expect(map['image_width'], 1200);
    expect(map['id'], 42);
    expect(safe[2], 'uploads/car_photos/a.jpg');

    // Must be JSON-encodable (this is what broke photo upload after create).
    expect(() => SellPendingMediaPrefs.jsonSafeMediaList([XFile('a.mp4')]),
        returnsNormally);
  });
}
