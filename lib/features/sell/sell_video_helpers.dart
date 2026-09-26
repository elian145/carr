import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../shared/debug/app_log.dart';

/// Diagnostics-safe (no auth/token/content) description of what
/// [buildVideoMultipartFile] would send for [video] -- reused by Issue-3
/// (real-device evidence: `POST /api/cars/<id>/videos` -> HTTP 400)
/// failure logging so the exact filename extension / sniffed MIME / byte
/// size that was actually SENT can be reported without re-deriving the
/// sniffing logic a second time.
class VideoUploadDiagnostics {
  const VideoUploadDiagnostics({
    required this.mime,
    required this.extension,
    required this.bytes,
  });

  final String mime;
  final String extension;
  final int bytes;
}

Future<List<int>> _readVideoHeaderBytes(String path) async {
  try {
    final raf = await File(path).open(mode: FileMode.read);
    try {
      return await raf.read(64);
    } finally {
      await raf.close();
    }
  } catch (e, st) {
    logNonFatal(e, st);
    return const [];
  }
}

String? _sniffVideoMimeFromHeader(List<int> headerBytes) {
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

/// Sniffs [video]'s real MIME type / filename extension / byte size using
/// the EXACT same logic [buildVideoMultipartFile] uses to decide what to
/// send -- diagnostic-only (safe to log; no file contents/auth), never
/// used to alter what is actually uploaded.
Future<VideoUploadDiagnostics> videoUploadDiagnostics(XFile video) async {
  final path = video.path.trim();
  final headerBytes = await _readVideoHeaderBytes(path);

  String mime =
      _sniffVideoMimeFromHeader(headerBytes) ??
      lookupMimeType(path, headerBytes: headerBytes) ??
      'video/mp4';
  if (!mime.startsWith('video/')) {
    mime = 'video/mp4';
  }

  final srcName = video.name.trim().isNotEmpty
      ? video.name.trim()
      : p.basename(path);
  String ext = extensionFromMime(mime) ?? '';
  if (mime == 'video/quicktime') ext = 'mov';
  if (mime == 'video/x-matroska') ext = 'mkv';
  if (ext.isEmpty) {
    ext = p.extension(srcName).replaceFirst('.', '');
  }
  final normalizedExt = ext.isNotEmpty ? ext : 'mp4';

  var bytes = 0;
  try {
    bytes = await video.length();
  } catch (e, st) {
    logNonFatal(e, st);
  }

  return VideoUploadDiagnostics(
    mime: mime,
    extension: normalizedExt,
    bytes: bytes,
  );
}

Future<http.MultipartFile> buildVideoMultipartFile(XFile video) async {
  final path = video.path.trim();
  final diagnostics = await videoUploadDiagnostics(video);

  final srcName = video.name.trim().isNotEmpty
      ? video.name.trim()
      : p.basename(path);
  final base = p.basenameWithoutExtension(srcName).trim();
  final fallbackBase = base.isNotEmpty
      ? base
      : 'video_${DateTime.now().millisecondsSinceEpoch}';
  final filename = '$fallbackBase.${diagnostics.extension}';

  MediaType contentType;
  try {
    contentType = MediaType.parse(diagnostics.mime);
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
