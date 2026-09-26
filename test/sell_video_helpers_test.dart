// Issue-3 regression tests (real-device evidence: `POST
// /api/cars/<id>/videos` -> HTTP 400 for genuinely valid `.mov` files).
//
// `videoUploadDiagnostics()` was extracted from `buildVideoMultipartFile()`
// so the exact filename extension / sniffed MIME type / byte size actually
// SENT for a video upload can be safely logged on failure (see
// `[SELL MEDIA] video upload failed ...` in `sell_listing_media_upload.dart`)
// without re-deriving the sniffing logic a second time. These tests prove
// both functions agree on the same MIME/extension for real `.mov`/`.mp4`
// byte shapes, including the exact durable-storage filename convention
// (`video_XXXXXXXX.mov`) real-device logs showed.
import 'dart:io';

import 'package:car_listing_app/features/sell/sell_video_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

// Real, minimal ISO-BMFF header bytes -- same shapes as the backend
// `kk/security.py::_is_mov`/`_is_mp4` regression tests use.
final _mp4IsomHeader = [
  0x00, 0x00, 0x00, 0x18, // box size
  0x66, 0x74, 0x79, 0x70, // 'ftyp'
  0x69, 0x73, 0x6F, 0x6D, // 'isom' brand
  ...List.filled(16, 0),
];

final _movQtHeader = [
  0x00, 0x00, 0x00, 0x14, // box size
  0x66, 0x74, 0x79, 0x70, // 'ftyp'
  0x71, 0x74, 0x20, 0x20, // 'qt  ' brand
  ...List.filled(16, 0),
];

final _movIsomBrandHeader = [
  0x00, 0x00, 0x00, 0x14, // box size
  0x66, 0x74, 0x79, 0x70, // 'ftyp'
  0x69, 0x73, 0x6F, 0x6D, // 'isom' brand (MP4-family, still a valid .mov)
  ...List.filled(16, 0),
];

// "Classic" pre-ftyp QuickTime movie -- starts directly with a `moov` atom,
// no ftyp box at all.
final _movClassicAtomHeader = [
  0x00, 0x00, 0x00, 0x08, // atom size
  0x6D, 0x6F, 0x6F, 0x76, // 'moov'
  ...List.filled(16, 0),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sell_video_helpers_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('videoUploadDiagnostics()', () {
    test(
      'a real .mp4 (isom brand) file is sniffed as video/mp4 with '
      'extension mp4',
      () async {
        final file = File('${tempDir.path}/clip.mp4')
          ..writeAsBytesSync(_mp4IsomHeader);
        final diag = await videoUploadDiagnostics(XFile(file.path));

        expect(diag.mime, 'video/mp4');
        expect(diag.extension, 'mp4');
        expect(diag.bytes, _mp4IsomHeader.length);
      },
    );

    test(
      'a real .mov file with the canonical QuickTime ftyp brand ("qt  ") '
      'is sniffed as video/quicktime with extension mov',
      () async {
        final file = File('${tempDir.path}/clip.mov')
          ..writeAsBytesSync(_movQtHeader);
        final diag = await videoUploadDiagnostics(XFile(file.path));

        expect(diag.mime, 'video/quicktime');
        expect(diag.extension, 'mov');
      },
    );

    test(
      'a durable-storage-shaped file (video_XXXXXXXX.mov on disk, but an '
      'MP4-family ftyp brand "isom" -- byte-for-byte the same ISO-BMFF '
      'container format as .mp4) is sniffed by its REAL container bytes '
      '(video/mp4), not blindly trusted from the ".mov" filename -- this '
      'is exactly why the file uploads successfully today (the client '
      'already re-labels it as .mp4 before sending) and is also exactly '
      'why the backend fix (Issue 3) is still needed for genuine .mov '
      'containers (the "qt  " and classic-atom cases above) that this '
      'sniffer correctly does NOT reclassify as MP4',
      () async {
        final file = File('${tempDir.path}/video_1a2b3c4d.mov')
          ..writeAsBytesSync(_movIsomBrandHeader);
        final diag = await videoUploadDiagnostics(XFile(file.path));

        expect(diag.mime, 'video/mp4');
        expect(
          diag.extension,
          'mp4',
          reason: 'buildVideoMultipartFile() uploads this content as .mp4 '
              '(matching its real container format), so the backend '
              '_is_mp4() check -- not _is_mov() -- is what validates it, '
              'and it was already accepted before the Issue-3 fix',
        );
      },
    );

    test(
      'byte size reported matches the real file size',
      () async {
        final bytes = [..._mp4IsomHeader, ...List.filled(500, 1)];
        final file = File('${tempDir.path}/sized.mp4')
          ..writeAsBytesSync(bytes);
        final diag = await videoUploadDiagnostics(XFile(file.path));

        expect(diag.bytes, bytes.length);
      },
    );
  });

  group('buildVideoMultipartFile()', () {
    test(
      'a .mov source file (durable draft-media naming convention) is sent '
      'with a .mov filename and a video content-type -- never silently '
      'renamed/re-typed to .mp4',
      () async {
        final file = File('${tempDir.path}/video_deadbeef.mov')
          ..writeAsBytesSync(_movQtHeader);
        final multipart = await buildVideoMultipartFile(XFile(file.path));

        expect(multipart.filename, 'video_deadbeef.mov');
        expect(multipart.contentType.type, 'video');
        expect(
          multipart.field,
          'files',
          reason: 'must match the server\'s request.files.getlist("files") '
              'field name exactly',
        );
      },
    );

    test(
      'a classic pre-ftyp .mov source file still builds a valid multipart '
      'file with a .mov filename',
      () async {
        final file = File('${tempDir.path}/video_classic01.mov')
          ..writeAsBytesSync(_movClassicAtomHeader);
        final multipart = await buildVideoMultipartFile(XFile(file.path));

        expect(multipart.filename, 'video_classic01.mov');
        expect(multipart.contentType.type, 'video');
      },
    );

    test(
      'a .mp4 source file is sent with a .mp4 filename and video/mp4 '
      'content-type',
      () async {
        final file = File('${tempDir.path}/photo_video.mp4')
          ..writeAsBytesSync(_mp4IsomHeader);
        final multipart = await buildVideoMultipartFile(XFile(file.path));

        expect(multipart.filename, 'photo_video.mp4');
        expect(multipart.contentType.mimeType, 'video/mp4');
      },
    );
  });
}
