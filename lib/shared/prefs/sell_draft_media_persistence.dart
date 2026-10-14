import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../shared/debug/app_log.dart';
import '../listings/listing_image_media.dart';

/// Copies picked listing media into app documents so sell drafts survive restarts.
class SellDraftMediaPersistence {
  /// Test-only interception point: when set, awaited at the very start of
  /// [_copyOrReadInto] for every file, keyed by its ORIGINAL (pre-copy)
  /// local path. Lets tests simulate a durable copy that is still
  /// pending, completes after an arbitrary delay, completes out of
  /// order, or fails for one specific file -- without depending on real
  /// file-system timing. Always `null` in production; mirrors this
  /// repo's existing `@visibleForTesting` override convention (e.g.
  /// `AuthService.debugProfileRetryDelaysOverride`,
  /// `debugLogNonFatalOverride`).
  @visibleForTesting
  static Future<void> Function(String localPath)? debugBeforeCopyOverride;
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

  static Future<Directory> draftDirectory(String draftId) => _draftDir(draftId);

  /// Last known application Documents path. Used to rewrite stale iOS
  /// container UUIDs in saved draft media without an extra await on every
  /// sync resolve. Populated by [_draftDir] / [ensureDocumentsPathCached].
  static String? _cachedDocsPath;

  static Future<Directory> _draftDir(String draftId) async {
    final docs = await getApplicationDocumentsDirectory();
    _cachedDocsPath = docs.path;
    final dir = Directory(
      p.join(docs.path, 'sell_draft_media', _safeDraftId(draftId)),
    );
    // Never recreate a folder that was intentionally tombstoned — stale
    // persist/blur must not reopen deleted draft media.
    if (_folderTombstoned.contains(_safeDraftId(draftId))) {
      return dir;
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Warms [_cachedDocsPath] so [resolveDynamicMediaList] can remap stale
  /// iOS sandbox paths synchronously when an old draft is reopened.
  static Future<void> ensureDocumentsPathCached() async {
    if (_cachedDocsPath != null && _cachedDocsPath!.trim().isNotEmpty) {
      return;
    }
    final docs = await getApplicationDocumentsDirectory();
    _cachedDocsPath = docs.path;
  }

  /// Relative `sell_draft_media/<draftId>/<file>` suffix, or null.
  static String? sellDraftMediaRelativeSuffix(String raw) {
    final norm = p.normalize(_localPath(raw)).replaceAll(r'\', '/');
    final marker = 'sell_draft_media/';
    final idx = norm.toLowerCase().indexOf(marker);
    if (idx < 0) return null;
    final suffix = norm.substring(idx);
    if (suffix.contains('..')) return null;
    return suffix;
  }

  /// If [raw] is a stale absolute path (old iOS container UUID) but the
  /// same file still exists under the current Documents directory, return
  /// the current path. Otherwise null.
  static String? relocateStaleDraftMediaPath(String raw) {
    final suffix = sellDraftMediaRelativeSuffix(raw);
    if (suffix == null) return null;
    final docs = _cachedDocsPath;
    if (docs == null || docs.trim().isEmpty) return null;
    final candidate = p.normalize(p.join(docs, suffix));
    final current = p.normalize(_localPath(raw));
    if (p.equals(current, candidate)) {
      return File(candidate).existsSync() ? candidate : null;
    }
    if (File(candidate).existsSync()) return candidate;
    return null;
  }

  static bool _isIosContainerPath(String local) {
    final n = local.replaceAll(r'\', '/');
    return n.contains('/Containers/Data/Application/');
  }

  /// True when [raw] is a durable draft / iOS-container file that is gone
  /// even after remapping onto the current Documents directory.
  static bool isConfirmedMissingDurableLocal(String raw) {
    final local = _localPath(raw);
    if (local.isEmpty || local.startsWith('content://')) return false;
    if (!_isUnderSellDraftMedia(local) && !_isIosContainerPath(local)) {
      return false;
    }
    final relocated = relocateStaleDraftMediaPath(local);
    if (relocated != null && File(relocated).existsSync()) return false;
    return !File(local).existsSync();
  }

  /// Deletes only this draft's local `sell_draft_media/<draftId>/` folder.
  /// Never touches remote/upload paths or other drafts' folders.
  ///
  /// Returns immediately after marking the folder for deletion. Physical
  /// removal waits (event-driven) until every [withLocalMediaLeases] reader
  /// for this draft has released — never force-deletes on a timer, so a
  /// slow blur/prestage upload cannot lose source files mid-stream.
  ///
  /// Empty-draft discard calls this on the UI path; the await here must
  /// not block the wizard. Callers that need the folder gone (tests)
  /// should await [debugAwaitPendingFolderDeletes].
  ///
  /// If the process dies while a delete is deferred behind an active
  /// lease, the folder may remain on disk after prefs are cleared (orphan
  /// media). That is intentional: surviving files are safer than deleting
  /// mid-upload. A later empty-draft / optimistic-media cleanup can remove
  /// leftovers; pending-submission paths never call this while a durable
  /// submission record still exists.
  ///
  /// Tombstones the draft id immediately so stale blur/persist/multipart
  /// work cannot acquire a NEW lease (or re-probe deleted `listing_orig_*`
  /// paths) after intentional cleanup — the prior lease gate alone only
  /// covered readers that already held a lease before delete.
  static Future<void> deleteLocalDraftFolder(String draftId) async {
    final id = draftId.trim();
    if (id.isEmpty) return;
    final key = _safeDraftId(id);
    _folderDeleteRequested.add(key);
    _folderTombstoned.add(key);
    if (_pendingFolderDeletes.containsKey(key)) return;
    late final Future<void> future;
    future = _deleteLocalDraftFolderBody(id).whenComplete(() {
      if (identical(_pendingFolderDeletes[key], future)) {
        _pendingFolderDeletes.remove(key);
      }
    });
    _pendingFolderDeletes[key] = future;
    // Surface unexpected async failures (should already be caught inside
    // the body) without creating an unhandled Future error.
    unawaited(future.catchError((Object e, StackTrace st) {
      logNonFatal(e, st, 'SellDraftMediaPersistence.deleteLocalDraftFolder');
    }));
  }

  static final Map<String, Future<void>> _pendingFolderDeletes = {};
  static final Set<String> _folderDeleteRequested = {};
  /// Armed synchronously after leases are confirmed idle, before any
  /// `await` in the physical delete path. Blocks new lease acquires for
  /// this draft so a reader cannot sneak in during `getApplicationDocuments`
  /// / `Directory.delete` awaits.
  static final Set<String> _folderDeleteArmed = {};
  /// Sticky after [deleteLocalDraftFolder]: draft media is intentionally
  /// gone. Survives physical delete so a late `MultipartFile.fromPath` /
  /// `_persistLocalPath` cannot treat obsolete paths as live sources.
  static final Set<String> _folderTombstoned = {};

  static Future<void> _deleteLocalDraftFolderBody(String id) async {
    final key = _safeDraftId(id);
    try {
      while (_folderDeleteRequested.contains(key)) {
        // Wait outside the persist serialize chain so a long upload does
        // not block unrelated persist work for this draft id.
        await _awaitLeasesIdle(key);

        var deleted = false;
        await _serializedForDraft(id, () async {
          if (!_folderDeleteRequested.contains(key)) return;
          if ((_readLeases[key] ?? 0) > 0) return;

          // Arm before any await — see [_folderDeleteArmed].
          _folderDeleteArmed.add(key);
          try {
            if ((_readLeases[key] ?? 0) > 0) return;
            final docs = await getApplicationDocumentsDirectory();
            if ((_readLeases[key] ?? 0) > 0) return;
            final dir = Directory(
              p.join(docs.path, 'sell_draft_media', key),
            );
            if (await dir.exists()) {
              await dir.delete(recursive: true);
            }
            // Keep [_folderTombstoned] — stale async work may still hold
            // obsolete listing_orig paths after the folder is gone.
            _folderDeleteRequested.remove(key);
            deleted = true;
          } finally {
            _folderDeleteArmed.remove(key);
          }
        });

        if (deleted || !_folderDeleteRequested.contains(key)) break;
        // A new lease appeared between idle wake and the serialized
        // re-check — loop and wait for the next idle signal.
      }
    } catch (e, st) {
      logNonFatal(e, st, 'SellDraftMediaPersistence._deleteLocalDraftFolderBody');
    }
  }

  /// True when [deleteLocalDraftFolder] has marked this draft's local media
  /// for intentional removal (including after physical delete completed).
  static bool isDraftMediaTombstoned(String draftId) {
    final id = draftId.trim();
    if (id.isEmpty) return false;
    return _folderTombstoned.contains(_safeDraftId(id));
  }

  /// Awaits in-flight [deleteLocalDraftFolder] jobs (test helper).
  ///
  /// When [draftId] is set, waits only for that draft (avoids blocking on
  /// unrelated deletes still waiting on a media lease from another test).
  /// When omitted, waits until every pending delete has finished.
  @visibleForTesting
  static Future<void> debugAwaitPendingFolderDeletes([String? draftId]) async {
    if (draftId != null) {
      final pending = _pendingFolderDeletes[_safeDraftId(draftId.trim())];
      if (pending != null) await pending;
      return;
    }
    while (_pendingFolderDeletes.isNotEmpty) {
      await Future.wait(
        List<Future<void>>.from(_pendingFolderDeletes.values),
      );
    }
  }

  @visibleForTesting
  static bool debugFolderDeleteRequested(String draftId) =>
      _folderDeleteRequested.contains(_safeDraftId(draftId));

  /// Clears in-memory delete/lease bookkeeping between tests.
  @visibleForTesting
  static void debugResetMediaLifecycleForTest() {
    _folderDeleteRequested.clear();
    _folderDeleteArmed.clear();
    _folderTombstoned.clear();
    _readLeases.clear();
    _leaseIdle.clear();
    _pendingFolderDeletes.clear();
    _persistChains.clear();
    _cachedDocsPath = null;
  }

  static bool _isInDraftDir(String local, String draftId) {
    final norm = p.normalize(_localPath(local));
    return norm.contains(
      p.normalize(p.join('sell_draft_media', _safeDraftId(draftId))),
    );
  }

  static final Map<String, Future<void>> _persistChains = {};

  /// In-flight readers of durable draft files (e.g. multipart blur/prestage
  /// uploads). [deleteLocalDraftFolder] waits for these so empty-draft
  /// cleanup cannot truncate a live `MultipartFile.fromPath` stream —
  /// production symptom: `Content size below specified contentLength`.
  static final Map<String, int> _readLeases = {};
  static final Map<String, Completer<void>> _leaseIdle = {};

  /// Test-only stand-in for the old "90s" wall clock. Used by tests to
  /// assert the folder still exists after this duration while a lease is
  /// held. Production deletion does **not** force-delete when this elapses
  /// — cleanup stays deferred until the last lease is released.
  @visibleForTesting
  static Duration deleteLeaseWaitTimeout = const Duration(seconds: 90);

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

  /// Draft id embedded in a durable local path under `sell_draft_media/`, or
  /// null when [raw] is remote / picker-cache / unrelated.
  static String? draftIdFromMediaPath(String raw) {
    final local = _localPath(raw);
    if (local.isEmpty) return null;
    final parts = p.split(p.normalize(local));
    for (var i = 0; i < parts.length - 1; i++) {
      if (parts[i] == 'sell_draft_media') {
        final id = parts[i + 1].trim();
        if (id.isNotEmpty && id != '.' && id != '..') return id;
      }
    }
    return null;
  }

  /// Holds a read lease for every distinct draft id in [localPaths] for the
  /// duration of [action]. No-op when no path is under `sell_draft_media/`.
  ///
  /// Refuses new leases when folder deletion was requested, is armed, or
  /// the draft is tombstoned (delete already completed) so a late blur /
  /// multipart reader cannot `fromPath` intentionally deleted files.
  static Future<T> withLocalMediaLeases<T>(
    Iterable<String> localPaths,
    Future<T> Function() action,
  ) async {
    final ids = <String>{};
    for (final path in localPaths) {
      final id = draftIdFromMediaPath(path);
      if (id != null) ids.add(_safeDraftId(id));
    }
    if (ids.isEmpty) return action();
    for (final id in ids) {
      if (_folderTombstoned.contains(id) ||
          _folderDeleteRequested.contains(id) ||
          _folderDeleteArmed.contains(id)) {
        throw StateError(
          'SellDraftMediaPersistence: refusing media lease for $id '
          'while folder delete is in progress',
        );
      }
      _readLeases[id] = (_readLeases[id] ?? 0) + 1;
    }
    try {
      return await action();
    } finally {
      for (final id in ids) {
        final next = (_readLeases[id] ?? 1) - 1;
        if (next <= 0) {
          _readLeases.remove(id);
          final idle = _leaseIdle.remove(id);
          if (idle != null && !idle.isCompleted) idle.complete();
        } else {
          _readLeases[id] = next;
        }
      }
    }
  }

  @visibleForTesting
  static int debugReadLeaseCount(String draftId) =>
      _readLeases[_safeDraftId(draftId)] ?? 0;

  /// Event-driven wait until this draft has zero read leases.
  /// Never force-returns while leases remain (no timeout bypass).
  static Future<void> _awaitLeasesIdle(String key) async {
    while ((_readLeases[key] ?? 0) > 0) {
      final idle = _leaseIdle[key] ??= Completer<void>();
      await idle.future;
    }
  }

  static Future<void> _writeBytesToFile(File dest, List<int> bytes) async {
    await dest.writeAsBytes(bytes, flush: true);
  }

  static Future<bool> _copyOrReadInto(File dest, String local) async {
    final hook = debugBeforeCopyOverride;
    if (hook != null) await hook(local);
    final src = File(local);
    if (await src.exists()) {
      try {
        await src.copy(dest.path);
        return await dest.exists();
      } catch (e, st) {
        logNonFatal(e, st);
      }
    }
    try {
      final sink = dest.openWrite();
      try {
        await for (final chunk in XFile(local).openRead()) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return await dest.exists() && await dest.length() > 0;
    } catch (e, st) {
      logNonFatal(e, st);
      try {
        if (await dest.exists()) await dest.delete();
      } catch (_) {}
      return false;
    }
  }

  static Future<String> _contentKeyForLocalFile(String local) async {
    try {
      int length = 0;
      List<int> sample = const [];
      final file = File(local);
      if (await file.exists()) {
        length = await file.length();
        final raf = await file.open();
        try {
          sample = await raf.read(16384);
        } finally {
          await raf.close();
        }
      } else {
        final xf = XFile(local);
        length = await xf.length();
        await for (final chunk in xf.openRead(0, 16384)) {
          sample = [...sample, ...chunk];
          if (sample.length >= 16384) {
            sample = sample.sublist(0, 16384);
            break;
          }
        }
      }
      if (length <= 0) return Object.hashAll([local]).abs().toString();
      return Object.hash(length, Object.hashAll(sample)).abs().toString();
    } catch (e, st) {
      logNonFatal(e, st);
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

    final safeId = _safeDraftId(draftId);
    // Intentional empty-draft / discard cleanup: do not recreate the folder
    // or probe deleted listing_orig paths (PathNotFound → Sentry spam).
    if (_folderTombstoned.contains(safeId) ||
        _folderDeleteRequested.contains(safeId)) {
      return null;
    }

    await ensureDocumentsPathCached();
    final relocated = relocateStaleDraftMediaPath(local);
    final effective =
        (relocated != null && relocated.isNotEmpty) ? relocated : local;

    if (_isInDraftDir(effective, draftId) || _isInDraftDir(local, draftId)) {
      if (await File(effective).exists()) return effective;
      // Genuinely missing durable draft file (corrupt/old draft, or a
      // sibling deleted this path). Drop quietly — callers already skip
      // null; re-probing via XFile.length only produces Sentry noise.
      return null;
    }

    final dir = await _draftDir(draftId);
    final ext = p.extension(local);
    final safeExt = ext.isEmpty
        ? (namePrefix.startsWith('video') ? '.mp4' : '.jpg')
        : ext;
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
    final seen = <String>{};
    for (final item in items) {
      final raw = ListingImageMedia.source(item);
      if (raw.isEmpty) continue;
      if (ListingImageMedia.isLocalMissing(item)) {
        final id = canonicalMediaIdentity(item);
        if (id.isNotEmpty && seen.add(id)) {
          out.add(ListingImageMedia.map(item, source: raw, localMissing: true));
        }
        continue;
      }
      if (isRetainedMediaReference(raw)) {
        final id = canonicalMediaIdentity(raw);
        if (seen.add(id)) {
          out.add(item is Map ? ListingImageMedia.map(item, source: raw) : raw);
        }
        continue;
      }
      final stored = await _persistLocalPath(
        raw,
        draftId: draftId,
        namePrefix: namePrefix,
      );
      if (stored == null || stored.isEmpty) continue;
      final id = canonicalMediaIdentity(stored);
      if (!seen.add(id)) continue;
      // Always persist as a metadata map so pending-prefs / drafts stay
      // JSON-serializable (never leave live XFile instances in carData).
      out.add(ListingImageMedia.map(item, source: stored));
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
        .map(ListingImageMedia.source)
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
      if (copy['original_images'] is List) {
        copy['original_images'] = await _persistDynamicMediaListImpl(
          List<dynamic>.from(copy['original_images'] as List),
          draftId: draftId,
          namePrefix: 'listing_orig',
        );
      }
      if (copy['blurred_images'] is List) {
        copy['blurred_images'] = await _persistDynamicMediaListImpl(
          List<dynamic>.from(copy['blurred_images'] as List),
          draftId: draftId,
          namePrefix: 'listing_blur',
        );
      }
      if (copy['damage_images'] is List) {
        copy['damage_images'] = await _persistDynamicMediaListImpl(
          List<dynamic>.from(copy['damage_images'] as List),
          draftId: draftId,
          namePrefix: 'damage',
        );
      }
      if (copy['original_damage_images'] is List) {
        copy['original_damage_images'] = await _persistDynamicMediaListImpl(
          List<dynamic>.from(copy['original_damage_images'] as List),
          draftId: draftId,
          namePrefix: 'damage_orig',
        );
      }
      if (copy['blurred_damage_images'] is List) {
        copy['blurred_damage_images'] = await _persistDynamicMediaListImpl(
          List<dynamic>.from(copy['blurred_damage_images'] as List),
          draftId: draftId,
          namePrefix: 'damage_blur',
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
        copy['processed_image_paths'] =
            (await _persistDynamicMediaListImpl(
                  List<dynamic>.from(copy['processed_image_paths'] as List),
                  draftId: draftId,
                  namePrefix: 'processed',
                ))
                .map(ListingImageMedia.source)
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
    return ListingImageMedia.source(item);
  }

  /// Stable dedupe key: draft files by basename, everything else by normalized path.
  static String canonicalMediaIdentity(dynamic item) {
    final raw = _mediaIdentity(item);
    if (raw.isEmpty) return raw;
    if (isRetainedMediaReference(raw)) {
      return _localPath(raw).replaceAll(r'\', '/').toLowerCase();
    }
    var local = p.normalize(_localPath(raw)).replaceAll(r'\', '/');
    if (Platform.isWindows) {
      local = local.toLowerCase();
    }
    if (local.contains('sell_draft_media/')) {
      return p.basename(local);
    }
    return local;
  }

  /// Prefer [primary] when it has media; otherwise use [secondary].
  static List<dynamic> coalesceMediaLists({
    List<dynamic>? primary,
    List<dynamic>? secondary,
  }) {
    final primaryResolved = resolveDynamicMediaList(
      primary is List ? List<dynamic>.from(primary) : null,
      includeMissingLocalPaths: true,
    );
    if (primaryResolved.isNotEmpty) return primaryResolved;
    return resolveDynamicMediaList(
      secondary is List ? List<dynamic>.from(secondary) : null,
      includeMissingLocalPaths: true,
    );
  }

  /// Union of media lists with canonical dedupe (same draft file, different path spellings).
  static List<dynamic> mergeRawMediaLists(List<List<dynamic>> sources) {
    final seen = <String>{};
    final merged = <dynamic>[];
    for (final source in sources) {
      for (final item in source) {
        final id = canonicalMediaIdentity(item);
        if (id.isEmpty || !seen.add(id)) continue;
        merged.add(item is XFile ? item : _mediaIdentity(item));
      }
    }
    return resolveDynamicMediaList(merged, includeMissingLocalPaths: true);
  }

  static bool _isUnderSellDraftMedia(String local) {
    return p
        .normalize(_localPath(local))
        .contains(p.normalize('sell_draft_media'));
  }

  static List<dynamic> resolveDynamicMediaList(
    List<dynamic>? items, {
    bool includeMissingLocalPaths = false,
  }) {
    if (items == null) return [];
    final out = <dynamic>[];
    final seen = <String>{};
    for (final item in items) {
      final raw = ListingImageMedia.source(item);
      if (raw.isEmpty) continue;
      dynamic resolved;
      if (isRetainedMediaReference(raw)) {
        resolved = item is Map ? ListingImageMedia.map(item, source: raw) : raw;
      } else if (ListingImageMedia.isLocalMissing(item)) {
        resolved = ListingImageMedia.map(item, source: raw, localMissing: true);
      } else {
        final local = _localPath(raw);
        final relocated = relocateStaleDraftMediaPath(local);
        final candidate =
            (relocated != null && relocated.isNotEmpty) ? relocated : local;
        if (File(candidate).existsSync()) {
          resolved = item is Map
              ? ListingImageMedia.map(
                  item,
                  source: candidate,
                  localMissing: false,
                )
              : XFile(candidate);
        } else if (local.startsWith('content://')) {
          // Android picker/cache URIs often fail File.existsSync even when
          // XFile can still read them. Keep them so review/upload can proceed.
          resolved = item is Map
              ? ListingImageMedia.map(item, source: local)
              : (item is XFile ? item : XFile(local));
        } else if (_isUnderSellDraftMedia(local) || _isIosContainerPath(local)) {
          // Stale iOS sandbox / missing durable draft file — keep a
          // replace-photo slot, never hand the dead path to blur/upload.
          resolved = ListingImageMedia.map(
            item,
            source: local,
            localMissing: true,
          );
        } else if (includeMissingLocalPaths || p.isAbsolute(local)) {
          resolved = item is Map
              ? ListingImageMedia.map(item, source: local)
              : (item is XFile ? item : XFile(local));
        } else {
          continue;
        }
      }
      final id = canonicalMediaIdentity(resolved);
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(resolved);
    }
    return out;
  }

  static List<String> resolvePathList(List<dynamic>? items) {
    return resolveDynamicMediaList(
      items,
    ).map(ListingImageMedia.source).where((s) => s.trim().isNotEmpty).toList();
  }

  static List<XFile> xFilesForUpload(List<dynamic>? items) {
    return resolveDynamicMediaList(
      items,
    ).map(ListingImageMedia.localFile).whereType<XFile>().toList();
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
