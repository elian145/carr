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

  static Future<Directory> _draftDir(String draftId) async {
    final docs = await getApplicationDocumentsDirectory();
    final safeId = draftId.trim().isEmpty
        ? 'default'
        : draftId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final dir = Directory(p.join(docs.path, 'sell_draft_media', safeId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String?> _persistLocalPath(
    String source, {
    required String draftId,
    required String fileName,
  }) async {
    final local = _localPath(source);
    if (local.isEmpty) return null;
    if (_isRemote(local)) return local;

    final src = File(local);
    if (!await src.exists()) return null;

    final dir = await _draftDir(draftId);
    final dest = File(p.join(dir.path, fileName));
    if (await dest.exists()) {
      await dest.delete();
    }
    await src.copy(dest.path);
    return dest.path;
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
}
