import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../shared/listings/listing_image_media.dart';
import 'sell_server_transcode_video.dart';

/// Media-readiness (see `kk/media_readiness.py`): stable per-item ids sent
/// as `expected_media` on `create_car()` and threaded through every Phase-A
/// transfer call (image async-upload / video finalize / normal video
/// upload) so the backend can register one `CarMediaItem` manifest row per
/// declared item at creation time and later match each upload/finalize
/// call back to the row it belongs to.
///
/// These ids are DERIVED, not stored: the same (car-scoped, durable) local
/// source path always produces the same id, so `expected_media` (computed
/// once, right before `create_car`) and the later per-item upload calls
/// (computed again, independently, right before each upload) agree
/// without needing to persist anything new into `carData`/prefs. This
/// only works because `SellDraftMediaPersistence.prepareCarDataForStorage`
/// has already copied every local file into its final durable path BEFORE
/// [PendingSellSubmissionService] ever calls `buildSellCarCreatePayload`
/// (see `_prepareSubmissionRecord`) -- the path is therefore already fixed
/// for the rest of this submission attempt (including any resume).
///
/// Backend contract (`kk/media_readiness.py`'s `_CLIENT_MEDIA_ID_RE`):
/// `^[A-Za-z0-9_-]{1,128}$`.
abstract final class SellMediaIdentity {
  SellMediaIdentity._();

  /// Canonical form of a local filesystem path for identity hashing.
  ///
  /// `prepareCarDataForStorage` may return the same durable file with
  /// different separator spellings across passes (first write via
  /// `p.join` vs a later `p.normalize` / iOS-container relocate). Without
  /// this, `create_car`'s `expected_media` and the Phase-A upload's
  /// `client_media_id` can disagree for the exact same file.
  static String identitySourceKey(String source) {
    final s = source.trim();
    if (s.isEmpty || _looksAlreadyRemote(s)) return s;
    if (s.startsWith('content://')) return s;
    return p.normalize(s).replaceAll(r'\', '/');
  }

  /// A short, filesystem/path-independent-looking but fully DETERMINISTIC
  /// FNV-1a-based hex id for [seed] (typically a local file path). Pure
  /// Dart, no dependency on `package:crypto` -- this file is on the hot
  /// "press Submit" path and must never add I/O or a new dependency.
  static String stableIdFromSeed(String seed, {String prefix = 'm'}) {
    const fnvOffsetBasis = 0xcbf29ce484222325;
    const fnvPrime = 0x100000001b3;
    var hash = fnvOffsetBasis;
    for (final byte in seed.codeUnits) {
      hash ^= byte;
      hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
    }
    final hex = hash.toRadixString(16).padLeft(16, '0');
    return '$prefix$hex';
  }

  /// The stable id for one `images`/`damage_images` entry, or `null` when
  /// [item] is already a server-attached image (has a numeric
  /// [ListingImageMedia.id]) -- those are pre-existing edit-mode media,
  /// not part of this submission's Phase A, so they must never appear in
  /// `expected_media`.
  static String? forImageItem(dynamic item, {required String kind}) {
    if (ListingImageMedia.id(item) != null) return null;
    final source = ListingImageMedia.source(item);
    if (source.isEmpty) return null;
    if (_looksAlreadyRemote(source)) return null;
    final bound = _boundIdOf(item);
    if (bound != null) return bound;
    return stableIdFromSeed(
      '$kind:${identitySourceKey(source)}',
      prefix: 'img_',
    );
  }

  /// The stable id for one normal (non-server-transcode) `videos` entry
  /// (an [XFile], path [String], or draft map), or `null` when it's
  /// already a server URL (pre-existing edit-mode video).
  static String? forNormalVideoItem(dynamic item) {
    final String source;
    if (item is XFile) {
      source = item.path.trim();
    } else if (item is Map) {
      source = ListingImageMedia.source(item);
    } else {
      source = (item?.toString() ?? '').trim();
    }
    if (source.isEmpty || _looksAlreadyRemote(source)) return null;
    final bound = _boundIdOf(item);
    if (bound != null) return bound;
    return stableIdFromSeed(
      'video:${identitySourceKey(source)}',
      prefix: 'vid_',
    );
  }

  /// Key under which [rebindToFrozenManifest] pins a frozen manifest id onto
  /// a replacement item. Honored by [forImageItem]/[forNormalVideoItem], so
  /// `expected_media`, every upload and the verification all derive the SAME
  /// id for that item.
  static const String boundIdKey = 'client_media_id';

  static String? _boundIdOf(dynamic item) {
    if (item is! Map) return null;
    final raw = (item[boundIdKey] ?? '').toString().trim();
    return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(raw) ? raw : null;
  }

  /// Retry-after-replacing-photos support.
  ///
  /// Once `create_car` has been attempted, its `expected_media` ids are bound
  /// to the idempotency key: a replay of that key returns the ORIGINAL car,
  /// whose server-side manifest still holds exactly those ids (and the server
  /// has no way to add or rename a manifest row). A replacement photo has a
  /// new path, hence a new path-derived id the server would never accept an
  /// upload for.
  ///
  /// So instead of changing the manifest, every local item whose id is NOT
  /// in [frozen] is bound (in list order, per kind) to a frozen id that no
  /// current item claims -- the replacement simply takes over the slot of
  /// the photo it replaces. Items already matching [frozen] are untouched.
  ///
  /// Never invents or drops a slot: if the selection now holds more or fewer
  /// items of a kind than the frozen manifest, [problem] describes it and the
  /// caller must fail closed (the manifest, like the idempotency key, is not
  /// negotiable).
  static ({Map<String, dynamic> carData, String? problem})
  rebindToFrozenManifest(
    Map<String, dynamic> carData,
    List<Map<String, String>> frozen,
  ) {
    final frozenIds = <String, String>{
      for (final e in frozen)
        if ((e['client_media_id'] ?? '').isNotEmpty)
          e['client_media_id']!: e['kind'] ?? 'image',
    };
    final have = <String>{
      for (final e in buildExpectedMedia(carData)) e['client_media_id']!,
    };
    final free = <String, List<String>>{
      'image': <String>[],
      'video': <String>[],
    };
    for (final entry in frozenIds.entries) {
      if (!have.contains(entry.key)) {
        (free[entry.value] ?? free['image']!).add(entry.key);
      }
    }
    if (free['image']!.isEmpty && free['video']!.isEmpty) {
      var extra = false;
      for (final id in have) {
        if (!frozenIds.containsKey(id)) extra = true;
      }
      return (
        carData: carData,
        problem: extra ? _manifestCountProblem : null,
      );
    }

    final out = Map<String, dynamic>.from(carData);
    var surplus = false;

    List<dynamic> bind(
      List<dynamic> items,
      String kind,
      String? Function(dynamic) idOf,
    ) {
      final next = <dynamic>[];
      for (final item in items) {
        final id = idOf(item);
        if (id == null || frozenIds.containsKey(id)) {
          next.add(item);
          continue;
        }
        final slots = free[kind]!;
        if (slots.isEmpty) {
          surplus = true;
          next.add(item);
          continue;
        }
        final slot = slots.removeAt(0);
        final bound = item is Map
            ? Map<String, dynamic>.from(
                item.map((k, v) => MapEntry(k.toString(), v)),
              )
            : <String, dynamic>{'source': ListingImageMedia.source(item)};
        bound[boundIdKey] = slot;
        next.add(bound);
      }
      return next;
    }

    final listingKey = (carData['original_images'] is List &&
            (carData['original_images'] as List).isNotEmpty)
        ? 'original_images'
        : 'images';
    final damageKey = (carData['original_damage_images'] is List &&
            (carData['original_damage_images'] as List).isNotEmpty)
        ? 'original_damage_images'
        : 'damage_images';
    if (carData[listingKey] is List) {
      out[listingKey] = bind(
        carData[listingKey] as List,
        'image',
        (item) => forImageItem(item, kind: 'listing'),
      );
    }
    if (carData[damageKey] is List) {
      out[damageKey] = bind(
        carData[damageKey] as List,
        'image',
        (item) => forImageItem(item, kind: 'damage'),
      );
    }
    if (carData['videos'] is List) {
      out['videos'] = bind(
        carData['videos'] as List,
        'video',
        forNormalVideoItem,
      );
    }

    final leftover = free['image']!.isNotEmpty || free['video']!.isNotEmpty;
    return (
      carData: out,
      problem: (surplus || leftover) ? _manifestCountProblem : null,
    );
  }

  static const String _manifestCountProblem =
      'This listing was already sent to the server with a fixed set of '
      'photos/videos. You can replace them, but the number of photos/videos '
      'must stay the same as when it was first submitted.';

  static bool _looksAlreadyRemote(String source) =>
      source.startsWith('http://') ||
      source.startsWith('https://') ||
      source.startsWith('uploads/') ||
      source.startsWith('static/') ||
      source.startsWith('/static/');

  /// Architecture fix (real-device evidence: "chose UNBLURRED, final
  /// listing still shows blurred"): the SINGLE authoritative source for
  /// what actually gets uploaded/enqueued/self-attached for a NEW
  /// listing's images, for every one of [buildExpectedMedia],
  /// `SellListingMediaUpload.runPhaseAOnly`, and `.uploadForCar`. ALWAYS
  /// the durable ORIGINAL local source -- never `carData['images']`
  /// (which [applySellPlateBlurChoice] may still point at a
  /// server-generated `blurred_images` PREVIEW url when the user chose
  /// "Blurred": that swap is preview-only from here on, intentionally
  /// decoupled from the final submission source). Falls back to
  /// `images`/`damage_images` only when `original_images`/
  /// `original_damage_images` is absent entirely (e.g. blur choice never
  /// ran for this list -- keeps existing/edit-mode behavior for lists
  /// that never go through the blur-choice split).
  static List<dynamic> finalListingImages(Map<String, dynamic> carData) {
    final originals = carData['original_images'];
    if (originals is List && originals.isNotEmpty) {
      return List<dynamic>.from(originals);
    }
    final images = carData['images'];
    return images is List ? List<dynamic>.from(images) : const <dynamic>[];
  }

  /// Same as [finalListingImages], for damage/disclosure photos.
  static List<dynamic> finalDamageImages(Map<String, dynamic> carData) {
    final originals = carData['original_damage_images'];
    if (originals is List && originals.isNotEmpty) {
      return List<dynamic>.from(originals);
    }
    final damage = carData['damage_images'];
    return damage is List ? List<dynamic>.from(damage) : const <dynamic>[];
  }

  /// The `skip_blur` flag the final Phase-A upload must send for EVERY
  /// expected image, derived from the same `use_blurred_plates` choice
  /// the blur-choice screen wrote -- never from which list
  /// (`original_images` vs `blurred_images`) happened to be picked.
  /// `use_blurred_plates=true` -> upload original bytes, `skip_blur=false`
  /// (let the backend produce + self-attach the blurred output).
  /// `use_blurred_plates=false`/unset -> `skip_blur=true` (publish the
  /// original bytes exactly as uploaded).
  static bool skipBlurForFinalSubmission(Map<String, dynamic> carData) =>
      carData['use_blurred_plates'] != true;

  /// Grid index of the seller's starred cover photo in a list of [length]
  /// listing images (`carData['primary_image_index']`, written by the star
  /// button). Anything missing/garbled/out of range is the first photo --
  /// the same fallback the Sell UI and preview use.
  static int coverImageIndex(Map<String, dynamic> carData, {required int length}) {
    if (length <= 0) return -1;
    final raw = carData['primary_image_index'];
    final parsed = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
    return (parsed < 0 || parsed >= length) ? 0 : parsed;
  }

  /// Position of grid item [index] once the cover ([coverIndex]) is moved to
  /// the front and everyone else keeps their relative grid order.
  static int coverFirstPosition(int index, {required int coverIndex}) {
    if (coverIndex < 0) return index;
    if (index == coverIndex) return 0;
    return index < coverIndex ? index + 1 : index;
  }

  /// The wire form of a (possibly frozen) manifest: the client persists every
  /// value as a string, the backend wants `is_cover` as a bool and
  /// `sort_order` as an int. Entries without those keys are sent unchanged
  /// (legacy frozen manifests).
  static List<Map<String, dynamic>> expectedMediaWirePayload(
    List<Map<String, String>> manifest,
  ) {
    return [
      for (final e in manifest)
        <String, dynamic>{
          'client_media_id': e['client_media_id'],
          'kind': e['kind'],
          if (e['is_cover'] == 'true') 'is_cover': true,
          if (int.tryParse(e['sort_order'] ?? '') != null)
            'sort_order': int.parse(e['sort_order']!),
        },
    ];
  }

  /// Builds the `expected_media` array for `POST /api/cars` from the SAME
  /// [finalListingImages]/[finalDamageImages]/`videos`/
  /// `server_transcode_videos` lists [buildSellCarCreatePayload]/
  /// `uploadForCar` now read for the actual transfer -- so a
  /// `client_media_id` here always agrees with the id the real upload
  /// call derives for the exact same item (never computed from a
  /// temporary `blurred_images` preview path). Empty/absent lists are
  /// simply skipped -- an all-empty result means "no expected media"
  /// (unchanged, `media_status=ready` behavior), matching every existing
  /// listing with no async media.
  static List<Map<String, String>> buildExpectedMedia(
    Map<String, dynamic> carData,
  ) {
    final out = <Map<String, String>>[];
    void addAll(
      dynamic rawList,
      String kind,
      String? Function(dynamic) idOf, {
      // Display position for item `i` (grid index -> position). Null = the
      // list carries no order information (videos).
      int Function(int index)? sortOrderOf,
      // Grid index of the seller's cover, or -1.
      int coverIndex = -1,
    }) {
      if (rawList is! List) return;
      for (var i = 0; i < rawList.length; i++) {
        final id = idOf(rawList[i]);
        if (id == null) continue;
        final entry = <String, String>{'client_media_id': id, 'kind': kind};
        if (sortOrderOf != null) {
          entry['sort_order'] = sortOrderOf(i).toString();
        }
        if (i == coverIndex) entry['is_cover'] = 'true';
        out.add(entry);
      }
    }

    // The seller's starred cover is declared HERE, together with the manifest,
    // so the server owns it from the moment the listing exists. The backend's
    // self-attach used to make the cover whichever photo finished processing
    // first, because nothing told it which photo the seller chose.
    // `sort_order` is the position in the cover-first display order; the array
    // itself stays in grid order (identity/rebind logic depends on that).
    final listingImages = finalListingImages(carData);
    final coverIndex = coverImageIndex(carData, length: listingImages.length);
    addAll(
      listingImages,
      'image',
      (item) => forImageItem(item, kind: 'listing'),
      sortOrderOf: (i) => coverFirstPosition(i, coverIndex: coverIndex),
      coverIndex: coverIndex,
    );
    addAll(
      finalDamageImages(carData),
      'image',
      (item) => forImageItem(item, kind: 'damage'),
      sortOrderOf: (i) => i,
    );
    addAll(carData['videos'], 'video', forNormalVideoItem);

    final serverTranscode = carData['server_transcode_videos'];
    if (serverTranscode is List) {
      for (final item in serverTranscode) {
        final spec = item is ServerTranscodeVideoSpec
            ? item
            : ServerTranscodeVideoSpec.fromJson(item);
        final draftMediaId = spec?.draftMediaId.trim();
        if (draftMediaId == null || draftMediaId.isEmpty) continue;
        out.add({'client_media_id': draftMediaId, 'kind': 'video'});
      }
    }

    // Defensive de-dup (mirrors the backend's own rejection of duplicate
    // `client_media_id`s) -- guards against two items that somehow
    // resolve to the same source path (e.g. a genuine duplicate pick)
    // ever producing an invalid, request-rejecting payload.
    final seen = <String>{};
    final deduped = <Map<String, String>>[];
    for (final entry in out) {
      if (seen.add(entry['client_media_id']!)) deduped.add(entry);
    }
    return deduped;
  }
}
