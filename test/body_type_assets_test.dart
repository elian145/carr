import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/listings/body_type_assets.dart';

void main() {
  test('getBodyTypeAsset uses dynamic map when present', () {
    globalBodyTypeAssetMap = {'Sedan': 'assets/body_types_png/custom.png'};
    expect(getBodyTypeAsset('sedan'), 'assets/body_types_png/custom.png');
  });

  test('getBodyTypeAsset falls back to sedan default', () {
    globalBodyTypeAssetMap = {};
    expect(getBodyTypeAsset('unknown-body'), 'assets/body_types_png/sedan.png');
    expect(getBodyTypeAsset('any'), 'assets/body_types_png/sedan.png');
  });
}
