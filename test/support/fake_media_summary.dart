import 'package:car_listing_app/features/sell/sell_media_identity.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';

/// Faithful fake of `GET /api/cars/<id>/media-summary` for tests.
///
/// The real server registers one `CarMediaItem` manifest row per
/// `expected_media` entry atomically with `create_car` (`awaiting_upload`,
/// Phase A NOT complete), and an item only becomes accepted
/// (`phase_a_complete`) once its bytes were actually transferred.
/// `media_summary()` returns the rows as
/// `{client_media_id, kind, status, phase_a_complete}`.
///
/// Older fake servers in this suite returned `items: []`, which is only
/// truthful for a listing created WITHOUT media -- and which the client now
/// (correctly) refuses to treat as "all media confirmed".
///
/// Model: an item is accepted once the fake server has observed an upload
/// of its kind for that car ([noteUpload], called from the fake image
/// enqueue/attach and video upload handlers), or when [acceptAll] is set
/// (for tests that do not exercise media transfer at all).
class FakeMediaManifest {
  FakeMediaManifest();

  /// Treat every declared item as already accepted (no upload needed).
  bool acceptAll = false;

  /// Pin the legacy client-driven attach flow for ALL cars (an enqueued
  /// image is not reported accepted until the client's own
  /// `POST /images/attach` lands), for tests whose assertions describe that
  /// flow (per-confirmed-item persisted progress).
  bool legacyClientAttachFlow = false;

  /// Lookup of the fake server's own car state (`images` / `videos` rows).
  Map<String, dynamic>? Function(String carId)? carLookup;

  final Map<String, List<Map<String, String>>> _declared =
      <String, List<Map<String, String>>>{};
  final Set<String> _uploaded = <String>{};
  final Map<String, String> _statusOverride = <String, String>{};
  final Map<String, bool> _phaseAOverride = <String, bool>{};

  /// Call from the fake `POST /api/cars` handler with the decoded body.
  void registerCreate(String carId, Map<String, dynamic> body) {
    final raw = body['expected_media'];
    _declared[carId] = <Map<String, String>>[
      if (raw is List)
        for (final e in raw)
          if (e is Map)
            <String, String>{
              'client_media_id': (e['client_media_id'] ?? '').toString(),
              'kind': (e['kind'] ?? 'image').toString(),
            },
    ];
  }

  /// Record that the server accepted an upload of [kind] (`image`/`video`)
  /// for [carId]. [viaClientAttach] marks the legacy client-driven
  /// `POST /images/attach` path.
  ///
  /// For a car this fake never saw created (a test that pre-seeds server
  /// state + a durable record with an existing `carId`), an enqueued image
  /// is NOT reported accepted until the client-driven attach lands: those
  /// tests pin the legacy client-attach flow (exactly one attach call with
  /// the remaining paths) that the previous `items: []` fake implied.
  void noteUpload(
    String carId,
    String kind, {
    bool viaClientAttach = false,
  }) {
    final seeded = !_declared.containsKey(carId);
    if ((seeded || legacyClientAttachFlow) &&
        kind == 'image' &&
        !viaClientAttach) {
      return;
    }
    _uploaded.add('$carId|$kind');
  }

  /// Force one item's server status (e.g. `failed`).
  void setItemStatus(String clientMediaId, String status) =>
      _statusOverride[clientMediaId] = status;

  /// Force one item's Phase-A acceptance.
  void setPhaseAComplete(String clientMediaId, bool value) =>
      _phaseAOverride[clientMediaId] = value;

  /// Drop the declared manifest of [carId] (server lost / replay of a car
  /// created without media).
  void clear(String carId) => _declared[carId] = <Map<String, String>>[];

  /// The manifest the server holds for [carId]. When this fake never saw the
  /// create call (a test that seeds a record with an existing `carId`), the
  /// durable client record is used: that listing was, by construction,
  /// created from that record's own carData.
  Future<List<Map<String, String>>> manifestFor(String carId) async {
    final known = _declared[carId];
    if (known != null) return known;
    for (final r in await SellSubmissionStatePrefs.loadAll()) {
      if (r.carId == carId) {
        return r.expectedMedia ??
            SellMediaIdentity.buildExpectedMedia(r.carData);
      }
    }
    return const <Map<String, String>>[];
  }

  Future<Map<String, dynamic>> summary(
    String carId, {
    String mediaStatus = 'ready',
  }) async {
    final items = <Map<String, dynamic>>[];
    final manifest = await manifestFor(carId);
    // Seeded car (never created through this fake): media rows the test put
    // on the fake server BEFORE the run are, by construction, media that
    // already landed -- their manifest rows are accepted. Compared by count
    // per kind, like the coarse server-count reconciliation those tests pin.
    final car = carLookup?.call(carId);
    // Items the record's carData ALREADY carries with a server id are not in
    // the manifest (server-owned), so they must not count as landed
    // manifest media.
    final records = await SellSubmissionStatePrefs.loadAll();
    Map<String, dynamic>? seededCarData;
    for (final r in records) {
      if (r.carId == carId) seededCarData = r.carData;
    }
    int serverOwnedCount(List<String> keys) {
      var n = 0;
      for (final k in keys) {
        final v = seededCarData?[k];
        if (v is List) {
          n += v.where((e) => e is Map && e['id'] != null).length;
        }
      }
      return n;
    }

    bool serverAlreadyHolds(String kind) {
      if (car == null || _declared.containsKey(carId)) return false;
      final need = manifest.where((m) => (m['kind'] ?? 'image') == kind).length;
      final rows = car[kind == 'video' ? 'videos' : 'images'];
      if (need == 0 || rows is! List) return false;
      final owned = kind == 'video'
          ? serverOwnedCount(const ['videos'])
          : serverOwnedCount(const ['images', 'damage_images']);
      return rows.length - owned >= need;
    }

    for (final e in manifest) {
      final id = e['client_media_id']!;
      final kind = e['kind'] ?? 'image';
      final accepted = _phaseAOverride[id] ??
          (acceptAll ||
              _uploaded.contains('$carId|$kind') ||
              serverAlreadyHolds(kind));
      items.add(<String, dynamic>{
        'client_media_id': id,
        'kind': kind,
        'status': _statusOverride[id] ?? (accepted ? 'processing' : 'awaiting_upload'),
        'phase_a_complete': accepted,
      });
    }
    return <String, dynamic>{
      'media_status': mediaStatus,
      'items': items,
      'phase_a_complete': items.every((i) => i['phase_a_complete'] == true),
    };
  }
}
