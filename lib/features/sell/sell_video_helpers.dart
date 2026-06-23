import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../shared/debug/app_log.dart';

Future<http.MultipartFile> buildVideoMultipartFile(XFile video) async {
  final path = video.path.trim();
  final file = File(path);
  List<int> headerBytes = const [];
  try {
    final raf = await file.open(mode: FileMode.read);
    headerBytes = await raf.read(64);
    await raf.close();
  } catch (e, st) {
    logNonFatal(e, st);
  }

  String? sniffFromHeader() {
    if (headerBytes.length >= 12) {
      final box = String.fromCharCodes(headerBytes.sublist(4, 8));
      if (box == 'ftyp') {
        final brand = String.fromCharCodes(
          headerBytes.sublist(8, 12),
        ).toLowerCase();
        if (brand.startsWith('qt')) return 'video/quicktime';
        if (brand.startsWith('3g')) return 'video/3gpp';
        return 'video/mp4';
      }
    }
    if (headerBytes.length >= 4) {
      if (headerBytes[0] == 0x1A &&
          headerBytes[1] == 0x45 &&
          headerBytes[2] == 0xDF &&
          headerBytes[3] == 0xA3) {
        final lower = String.fromCharCodes(headerBytes).toLowerCase();
        if (lower.contains('webm')) return 'video/webm';
        return 'video/x-matroska';
      }
      if (headerBytes.length >= 12 &&
          String.fromCharCodes(headerBytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(headerBytes.sublist(8, 12)) == 'AVI ') {
        return 'video/x-msvideo';
      }
    }
    return null;
  }

  String mime =
      sniffFromHeader() ??
      lookupMimeType(path, headerBytes: headerBytes) ??
      'video/mp4';
  if (!mime.startsWith('video/')) {
    mime = 'video/mp4';
  }

  final srcName = video.name.trim().isNotEmpty
      ? video.name.trim()
      : p.basename(path);
  final base = p.basenameWithoutExtension(srcName).trim();
  final fallbackBase = base.isNotEmpty
      ? base
      : 'video_${DateTime.now().millisecondsSinceEpoch}';
  String ext = extensionFromMime(mime) ?? '';
  if (mime == 'video/quicktime') ext = 'mov';
  if (mime == 'video/x-matroska') ext = 'mkv';
  if (ext.isEmpty) {
    ext = p.extension(srcName).replaceFirst('.', '');
  }
  final normalizedExt = ext.isNotEmpty ? ext : 'mp4';
  final filename = '$fallbackBase.$normalizedExt';

  MediaType contentType;
  try {
    contentType = MediaType.parse(mime);
  } catch (e, st) {
    logNonFatal(e, st);
    contentType = MediaType('video', 'mp4');
  }

  return http.MultipartFile.fromPath(
    'files',
    path,
    filename: filename,
    contentType: contentType,
  );
}

Future<String?> generateVideoThumbnail(String videoPath) async {
  try {
    final thumbnailPath = await VideoThumbnail.thumbnailFile(
      video: videoPath,
      thumbnailPath: (await Directory.systemTemp.createTemp()).path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 200,
      quality: 75,
    );
    return thumbnailPath;
  } catch (e) {
    appLog('Error generating video thumbnail: $e');
    return null;
  }
}
