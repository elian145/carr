import 'dart:async';
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

  /// Server URL or relative upload path stored in drafts (not a device file).
  static bool isRetainedMediaReference(String raw) {
    final norm = _localPath(raw).replaceAll(r'\', '/');
    if (norm.isEmpty) return false;
    if (_isRemote(norm)) return true;
    return norm.startsWith('uploads/') ||
        norm.startsWith('static/') ||
        norm.startsWith('car_photos/');
  }

  /// True when [raw] is a device path, not a server uploads/static URL.
  static bool isLocalMediaPath(String raw) {
    final local = _localPath(raw);
    if (local.isEmpty) return false;
    if (isRetainedMediaReference(local)) return false;
    final norm = local.replaceAll(r'\', '/');
    if (norm.contains('sell_draft_media')) return true;
    return p.isAbsolute(norm) || norm.startsWith('content://');
  }

  static String _safeDraftId(String draftId) {
    final trimmed = draftId.trim();
    if (trimmed.isEmpty) return 'default';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  static Future<Directory> draftDirectory(String draftId) =>
      _draftDir(draftId);

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

  static bool _isInDraftDir(String local, String draftId) {
    final norm = p.normalize(_localPath(local));
    return norm.contains(
      p.normalize(p.join('sell_draft_media', _safeDraftId(draftId))),
    );
  }

  static final Map<String, Future<void>> _persistChains = {};

  static Future<T> _serializedForDraft<T>(
    String draftId,
    Future<T> Function() action,
  ) async {
    final key = _safeDraftId(draftId);
    final previous = _persistChains[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _persistChains[key] = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_persistChains[key], completer.future)) {
        _persistChains.remove(key);
      }
    }
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

  static Future<String> _contentKeyForLocalFile(String local) async {
    try {
      final bytes = await XFile(local).readAsBytes();
      if (bytes.isEmpty) return Object.hashAll([local]).abs().toString();
      final sampleLen = bytes.length < 16384 ? bytes.length : 16384;
      return Object.hash(
        bytes.length,
        Object.hashAll(bytes.sublist(0, sampleLen)),
      ).abs().toString();
    } catch (_) {
      return Object.hashAll([local]).abs().toString();
    }
  }

  static Future<String?> _persistLocalPath(
    String source, {
    required String draftId,
    required String namePrefix,
  }) async {
    final local = _localPath(source);
    if (local.isEmpty) return null;
    if (isRetainedMediaReference(local)) return local;

    if (_isInDraftDir(local, draftId)) {
      if (await File(local).exists()) return local;
      try {
        await XFile(local).length();
        return local;
      } catch (_) {
        return null;
      }
    }

    final dir = await _draftDir(draftId);
    final ext = p.extension(local);
    final safeExt = ext.isEmpty ? '.jpg' : ext;
    final contentKey = await _contentKeyForLocalFile(local);
    final dest = File(p.join(dir.path, '${namePrefix}_$contentKey$safeExt'));
    final normSrc = p.normalize(local);
    final normDest = p.normalize(dest.path);

    if (normSrc == normDest) {
      if (await dest.exists()) return dest.path;
      return null;
    }

    if (await dest.exists()) {
      return dest.path;
    }

    final ok = await _copyOrReadInto(dest, local);
    return ok ? dest.path : null;
  }

  static Future<List<dynamic>> _persistDynamicMediaListImpl(
    List<dynamic> items, {
    required String draftId,
    required String namePrefix,
  }) async {
    final out = <dynamic>[];
    for (final item in items) {
      final raw = item is XFile
          ? item.path
          : item?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      if (isRetainedMediaReference(raw)) {
        out.add(raw);
        continue;
      }
      final stored = await _persistLocalPath(
        raw,
        draftId: draftId,
        namePrefix: namePrefix,
      );
      if (stored == null || stored.isEmpty) continue;
      out.add(XFile(stored));
    }
    return out;
  }

  static Future<List<dynamic>> persistDynamicMediaList(
    List<dynamic> items, {
    required String draftId,
    required String namePrefix,
  }) {
    return _serializedForDraft(
      draftId,
      () => _persistDynamicMediaListImpl(
        items,
        draftId: draftId,
        namePrefix: namePrefix,
      ),
    );
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
  }) {
    return _serializedForDraft(draftId, () async {
      final copy = Map<String, dynamic>.from(carData);
      if (copy['images'] is List) {
        copy['images'] = await _persistDynamicMediaListImpl(
          List<dynamic>.from(copy['images'] as List),
          draftId: draftId,
          namePrefix: 'listing',
        );
      }
      if (copy['damage_images'] is List) {
        copy['damage_images'] = await _persistDynamicMediaListImpl(
          List<dynamic>.from(copy['damage_images'] as List),
          draftId: draftId,
          namePrefix: 'damage',
        );
      }
      if (copy['videos'] is List) {
        copy['videos'] = await _persistDynamicMediaListImpl(
          List<dynamic>.from(copy['videos'] as List),
          draftId: draftId,
          namePrefix: 'video',
        );
      }
      if (copy['processed_image_paths'] is List) {
        copy['processed_image_paths'] = (await _persistDynamicMediaListImpl(
          List<dynamic>.from(copy['processed_image_paths'] as List),
          draftId: draftId,
          namePrefix: 'processed',
        ))
            .map((e) => e is XFile ? e.path : e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
      return copy;
    });
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

  static String _mediaIdentity(dynamic item) {
    if (item is XFile) return item.path.trim();
    return item?.toString().trim() ?? '';
  }

  /// Union of media lists, preserving first-seen order.
  static List<dynamic> mergeRawMediaLists(List<List<dynamic>> sources) {
    final seen = <String>{};
    final merged = <dynamic>[];
    for (final source in sources) {
      for (final item in source) {
        final id = _mediaIdentity(item);
        if (id.isEmpty || !seen.add(id)) continue;
        merged.add(item is XFile ? item : id);
      }
    }
    return resolveDynamicMediaList(merged, includeMissingLocalPaths: true);
  }

  static bool _isUnderSellDraftMedia(String local) {
    return p.normalize(_localPath(local)).contains(
      p.normalize('sell_draft_media'),
    );
  }

  static List<dynamic> resolveDynamicMediaList(
    List<dynamic>? items, {
    bool includeMissingLocalPaths = false,
  }) {
    if (items == null) return [];
    final out = <dynamic>[];
    for (final item in items) {
      final raw = item is XFile ? item.path : item?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      if (isRetainedMediaReference(raw)) {
        out.add(raw);
        continue;
      }
      final local = _localPath(raw);
      if (File(local).existsSync()) {
        out.add(XFile(local));
        continue;
      }
      if (includeMissingLocalPaths && _isUnderSellDraftMedia(local)) {
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

  /// Writes bytes into the draft folder so temp previews survive app restarts.
  static Future<String?> persistBytesToDraft(
    List<int> bytes, {
    required String draftId,
    required String namePrefix,
    String extension = '.jpg',
  }) {
    if (bytes.isEmpty) return Future.value(null);
    return _serializedForDraft(draftId, () async {
      final dir = await _draftDir(draftId);
      final key = Object.hashAll(bytes).abs().toString();
      final dest = File(p.join(dir.path, '${namePrefix}_$key$extension'));
      if (await dest.exists()) return dest.path;
      await _writeBytesToFile(dest, bytes);
      return (await dest.exists()) ? dest.path : null;
    });
  }
}
