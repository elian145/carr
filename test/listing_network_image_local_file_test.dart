// Regression coverage for the Sell-media Android bug: a selected photo
// showed as a placeholder/broken-image immediately after picking, and a
// locally-drafted "My Listings" preview kept showing a placeholder too.
// Root cause (see [listingLocalFileImage]'s doc comment in
// listing_network_image.dart): Android `content://` picker/cache paths
// often fail `Image.file` / `File.exists` even though the picker's `XFile`
// can still read them via `XFile.readAsBytes()`. `listingLocalFileImage`
// (backed by the private `_ListingXFileImage` widget) exists specifically
// so Sell-flow rendering falls back to `Image.memory` instead of silently
// showing a broken-image placeholder in that case.
//
// NOTE: this repo's existing Flutter test suite is unit/logic-only (no
// `testWidgets`/widget pumping anywhere in test/) and pumping a real
// Image.file/Image.memory widget in this sandboxed test environment hangs
// indefinitely (reproduced independently of this fix, with a minimal
// Image.file widget test). So these tests stay at the construction/API
// level -- confirming listingLocalFileImage accepts every path shape this
// bug involves without throwing -- rather than pumping a real widget tree.
// The actual fallback *logic* (`File.existsSync` vs `content://`) is
// covered by the equivalent, fully-pumpable checks in
// listing_image_media_test.dart's "regression: Sell media Android
// content:// rendering bug" group, which exercises the same
// existsSync-or-content:// decision this widget's `_fileOnDisk` getter
// makes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:car_listing_app/app/widgets/listing_network_image.dart';

void main() {
  test('listingLocalFileImage constructs for a content:// picker path '
      'without throwing', () {
    expect(
      () => listingLocalFileImage(
        XFile('content://media/external/images/media/12345'),
      ),
      returnsNormally,
    );
  });

  test('listingLocalFileImage constructs for a real absolute file path '
      'without throwing', () {
    expect(
      () => listingLocalFileImage(XFile('/tmp/some/real/photo.jpg')),
      returnsNormally,
    );
  });

  test('listingLocalFileImage constructs for a missing local path without '
      'throwing', () {
    expect(
      () => listingLocalFileImage(
        XFile('/tmp/does/not/exist/photo.jpg'),
      ),
      returnsNormally,
    );
  });

  test('listingLocalFileImage forwards fit/alignment/size/error/placeholder '
      'params without throwing', () {
    expect(
      () => listingLocalFileImage(
        XFile('content://media/external/images/media/1'),
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        width: 100,
        height: 100,
        errorWidget: const Icon(Icons.broken_image_outlined),
        placeholder: const SizedBox.shrink(),
        key: const Key('k'),
      ),
      returnsNormally,
    );
  });

  test('a real on-disk file is detected via File.existsSync (same gate '
      'the widget uses to prefer Image.file over the XFile fallback)', () async {
    final dir = await Directory.systemTemp.createTemp('listing_img_test');
    final file = File('${dir.path}/real.bin');
    await file.writeAsBytes([1, 2, 3]);
    try {
      expect(File(file.path).existsSync(), isTrue);
      expect(file.path.startsWith('content://'), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
