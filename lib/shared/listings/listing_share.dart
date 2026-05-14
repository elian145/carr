import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../media/media_url.dart';

bool _imageEntryIsDamage(dynamic it) {
  if (it is! Map) return false;
  final k = (it['kind'] ?? '').toString().toLowerCase();
  return k == 'damage';
}

/// First non-damage listing photo as an absolute URL (for download + share sheet).
String primaryListingShareImageUrl(Map<String, dynamic> car) {
  final seen = <String>{};

  void addCandidate(String raw) {
    if (raw.trim().isEmpty) return;
    final full = buildMediaUrl(raw);
    if (full.isEmpty || seen.contains(full)) return;
    seen.add(full);
  }

  addCandidate((car['image_url'] ?? '').toString());

  final imgs = car['images'];
  if (imgs is List) {
    for (final it in imgs) {
      if (_imageEntryIsDamage(it)) continue;
      final s = it is Map
          ? (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
                .toString()
          : it.toString();
      addCandidate(s);
    }
  }

  return seen.isEmpty ? '' : seen.first;
}

String _mimeFromResponse(String? contentType, String url) {
  final ct = (contentType ?? '').split(';').first.trim().toLowerCase();
  if (ct.startsWith('image/')) return ct;
  final u = url.toLowerCase();
  if (u.endsWith('.png')) return 'image/png';
  if (u.endsWith('.webp')) return 'image/webp';
  if (u.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

String _extForMime(String mime) {
  if (mime.contains('png')) return 'png';
  if (mime.contains('webp')) return 'webp';
  if (mime.contains('gif')) return 'gif';
  return 'jpg';
}

/// Shares [shareText] together with the listing hero image when possible so the
/// system share sheet shows a photo (like attaching a listing snapshot).
///
/// Rich **link previews** in chat apps (OG image for a URL) still require an
/// HTTPS page with `og:image`; this path shares an actual image file instead.
Future<void> shareListingWithPrimaryImage({
  required String shareText,
  required Map<String, dynamic>? car,
}) async {
  final text = shareText.trim();
  if (text.isEmpty) return;

  final url = (car == null) ? '' : primaryListingShareImageUrl(car);
  const maxBytes = 10 * 1024 * 1024;

  if (!kIsWeb && url.isNotEmpty) {
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        if (bytes.isNotEmpty && bytes.length <= maxBytes) {
          final mime = _mimeFromResponse(resp.headers['content-type'], url);
          final ext = _extForMime(mime);
          final fileName = 'CARZO_listing.$ext';
          final file = XFile.fromData(
            bytes,
            mimeType: mime,
            name: fileName,
          );
          await SharePlus.instance.share(
            ShareParams(
              files: [file],
              text: text,
              fileNameOverrides: [fileName],
              title: 'CARZO',
            ),
          );
          return;
        }
      }
    } catch (_) {
      // Fall back to text-only share below.
    }
  }

  await SharePlus.instance.share(ShareParams(text: text, title: 'CARZO'));
}
