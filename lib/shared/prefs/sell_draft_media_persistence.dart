import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies picked listing media into app documents so sell drafts survive restarts.
class SellDraftMediaPersistence {
  static bool _isRemote(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  static String _localPath(String raw) =>
      raw.trim().replaceFirst(RegExp(r'^file://'), '');

  /// Normalized local filesystem path (strips `file://`).
  static String localMediaPath(String raw) => _localPath(raw);

  /// True when [raw] is a device path, not a server uploads/static URL.
  static bool isLocalMediaPath(String raw) {
    final local = _localPath(raw);
    if (local.isEmpty) return false;
    if (_isRemote(local)) return false;
    final norm = local.replaceAll(r'\', '/');
    if (norm.startsWith('uploads/') ||
        norm.startsWith('static/') ||
        norm.startsWith('car_photos/')) {
      return false;
    }
    if (norm.contains('sell_draft_media')) return true;
    return p.isAbsolute(norm);
  }

  static String _safeDraftId(String draftId) {
    final trimmed = draftId.trim();
    if (trimmed.isEmpty) return 'default';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  static Future<Directory> _draftDir(String draftId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(docs.path, 'sell_draft_media', _safeDraftId(draftId)),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> _writeBytesToFile(File dest, List<int> bytes) async {
    await dest.writeAsBytes(bytes, flush: true);
  }

  static Future<bool> _copyOrReadInto(File dest, String local) async {
    final src = File(local);
    if (await src.exists()) {
      try {
        await src.copy(dest.path);
        return await dest.exists();
      } catch (_) {}
    }
    try {
      final bytes = await XFile(local).readAsBytes();
      if (bytes.isEmpty) return false;
      await _writeBytesToFile(dest, bytes);
      return await dest.exists();
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _persistLocalPath(
    String source, {
    required String draftId,
    required String fileName,
  }) async {
    final local = _localPath(source);
    if (local.isEmpty) return null;
    if (_isRemote(local)) return local;

    final dir = await _draftDir(draftId);
    final dest = File(p.join(dir.path, fileName));
    final normSrc = p.normalize(local);
    final normDest = p.normalize(dest.path);

    // Re-persisting an item already stored at the target path must not delete it.
    if (normSrc == normDest) {
      if (await dest.exists()) return dest.path;
      return null;
    }

    if (await dest.exists()) {
      await dest.delete();
    }

    final ok = await _copyOrReadInto(dest, local);
    return ok ? dest.path : null;
  }

  static Future<List<dynamic>> persistDynamicMediaList(
    List<dynamic> items, {
    required String draftId,
    required String namePrefix,
  }) async {
    final out = <dynamic>[];
    for (var i = 0; i < items.length; i++) {
      final raw = items[i] is XFile
          ? (items[i] as XFile).path
          : items[i]?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      if (_isRemote(raw)) {
        out.add(raw);
        continue;
      }
      final ext = p.extension(_localPath(raw));
      final safeExt = ext.isEmpty ? '.jpg' : ext;
      final stored = await _persistLocalPath(
        raw,
        draftId: draftId,
        fileName: '${namePrefix}_$i$safeExt',
      );
      if (stored == null || stored.isEmpty) continue;
      out.add(XFile(stored));
    }
    return out;
  }

  static Future<List<String>> persistPathList(
    List<dynamic> items, {
    required String draftId,
    required String namePrefix,
  }) async {
    final persisted = await persistDynamicMediaList(
      items,
      draftId: draftId,
      namePrefix: namePrefix,
    );
    return persisted
        .map((e) => e is XFile ? e.path : e.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  static Future<Map<String, dynamic>> prepareCarDataForStorage(
    Map<String, dynamic> carData, {
    required String draftId,
  }) async {
    final copy = Map<String, dynamic>.from(carData);
    if (copy['images'] is List) {
      copy['images'] = await persistDynamicMediaList(
        List<dynamic>.from(copy['images'] as List),
        draftId: draftId,
        namePrefix: 'listing',
      );
    }
    if (copy['damage_images'] is List) {
      copy['damage_images'] = await persistDynamicMediaList(
        List<dynamic>.from(copy['damage_images'] as List),
        draftId: draftId,
        namePrefix: 'damage',
      );
    }
    if (copy['videos'] is List) {
      copy['videos'] = await persistDynamicMediaList(
        List<dynamic>.from(copy['videos'] as List),
        draftId: draftId,
        namePrefix: 'video',
      );
    }
    if (copy['processed_image_paths'] is List) {
      copy['processed_image_paths'] = await persistPathList(
        List<dynamic>.from(copy['processed_image_paths'] as List),
        draftId: draftId,
        namePrefix: 'processed',
      );
    }
    return copy;
  }

  static Future<Map<String, dynamic>> augmentDraftMap(
    Map<String, dynamic> draft, {
    required String draftId,
  }) async {
    final copy = Map<String, dynamic>.from(draft);
    for (final entry in <MapEntry<String, String>>[
      MapEntry('image_paths', 'listing'),
      MapEntry('damage_image_paths', 'damage'),
      MapEntry('video_paths', 'video'),
    ]) {
      final raw = copy[entry.key];
      if (raw is! List) continue;
      copy[entry.key] = await persistPathList(
        raw,
        draftId: draftId,
        namePrefix: entry.value,
      );
    }
    return copy;
  }

  static List<dynamic> resolveDynamicMediaList(List<dynamic>? items) {
    if (items == null) return [];
    final out = <dynamic>[];
    for (final item in items) {
      final raw = item is XFile ? item.path : item?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      if (_isRemote(raw)) {
        out.add(raw);
        continue;
      }
      final local = _localPath(raw);
      if (File(local).existsSync()) {
        out.add(XFile(local));
      }
    }
    return out;
  }

  static List<String> resolvePathList(List<dynamic>? items) {
    return resolveDynamicMediaList(items)
        .map((e) => e is XFile ? e.path : e.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  static List<XFile> xFilesForUpload(List<dynamic>? items) {
    return resolveDynamicMediaList(items).whereType<XFile>().toList();
  }
}
