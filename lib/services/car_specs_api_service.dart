import 'dart:convert';

import 'package:http/http.dart' as http;

/// Year / make / model (+ trim) via [Car API on RapidAPI](https://rapidapi.com/carapi/api/car-api2)
/// or direct [carapi.app](https://carapi.app/).
///
/// **RapidAPI** (`*.rapidapi.com` host): `X-RapidAPI-Key` + `X-RapidAPI-Host` only — the proxy does
/// not expose `/api/auth/login`. `GET /api/trims/v2` and `GET /api/trims/v2/{id}` for search + detail.
///
/// **Direct carapi.app:** `POST /api/auth/login` with `api_token` + `api_secret` → JWT (cached), then
/// the same trim endpoints with `Authorization: Bearer …`.
///
/// When the API returns one or more distinct values for a spec, [OnlineCarSpecs] includes the
/// matching `*Options` list (single-item lists restrict the picker to that value only).
///
/// **dart-define:** `CARAPI_RAPIDAPI_KEY` (required; default host is RapidAPI). For **direct**
/// carapi.app instead: `CARAPI_HOST=https://carapi.app`, `CARAPI_API_TOKEN`, `CARAPI_API_SECRET`
/// (no RapidAPI key needed).
class CarSpecsApiService {
  static const String _defaultHost = 'https://car-api2.p.rapidapi.com';

  static const String _token =
      String.fromEnvironment('CARAPI_API_TOKEN', defaultValue: '');
  static const String _secret =
      String.fromEnvironment('CARAPI_API_SECRET', defaultValue: '');
  static const String _host =
      String.fromEnvironment('CARAPI_HOST', defaultValue: _defaultHost);
  static const String _rapidApiKeyEnv =
      String.fromEnvironment('CARAPI_RAPIDAPI_KEY', defaultValue: '');

  static const Duration _timeout = Duration(seconds: 30);

  static String? _jwt;
  static DateTime? _jwtExpiresAt;

  static String get _apiToken => _token.trim();
  static String get _apiSecret => _secret.trim();
  static String get _rapidApiKey => _rapidApiKeyEnv.trim();

  static Uri get _apiBase {
    final h = _host.trim();
    return Uri.parse(h.isEmpty ? _defaultHost : h);
  }

  static bool get _usesRapidApiProxy =>
      _apiBase.host.toLowerCase().contains('rapidapi.com');

  static String get _baseUrl => _apiBase.toString().replaceAll(RegExp(r'/$'), '');

  static bool get isConfigured {
    if (_usesRapidApiProxy) return _rapidApiKey.isNotEmpty;
    return _apiToken.isNotEmpty && _apiSecret.isNotEmpty;
  }

  /// User-facing hint when [isConfigured] is false (snackbars / dialogs).
  static String get missingConfigurationMessage {
    if (_usesRapidApiProxy) {
      if (_rapidApiKey.isEmpty) {
        return 'Missing CARAPI_RAPIDAPI_KEY (dart-define). '
            'Car API: https://rapidapi.com/carapi/api/car-api2';
      }
      return '';
    }
    if (_apiToken.isEmpty || _apiSecret.isEmpty) {
      return 'Missing CARAPI_API_TOKEN and CARAPI_API_SECRET (dart-define). '
          'Use CARAPI_HOST=https://carapi.app or see https://carapi.app/docs';
    }
    return '';
  }

  static Map<String, String> _withRapidApiHeaders(Map<String, String> headers) {
    if (!_usesRapidApiProxy) return headers;
    return <String, String>{
      ...headers,
      'X-RapidAPI-Key': _rapidApiKey,
      'X-RapidAPI-Host': _apiBase.host,
    };
  }

  static Future<OnlineCarSpecs> lookupByYmm({
    required int year,
    required String brand,
    required String model,
    required String trim,
  }) async {
    if (!isConfigured) {
      throw StateError(missingConfigurationMessage.isEmpty
          ? 'Car API is not configured.'
          : missingConfigurationMessage);
    }
    if (year <= 0) {
      throw ArgumentError('Invalid year');
    }
    final make = brand.trim();
    final modelName = model.trim();
    final trimName = trim.trim();
    if (make.isEmpty || modelName.isEmpty || trimName.isEmpty) {
      throw ArgumentError('Brand, model, and trim are required');
    }

    if (!_usesRapidApiProxy) {
      await _ensureJwt();
    }

    var summaries = await _gatherTrimSummaries('api/trims/v2', year, make, modelName, trimName);
    if (summaries.isEmpty) {
      summaries = await _gatherTrimSummaries('api/trims', year, make, modelName, trimName);
    }
    if (summaries.isEmpty) {
      summaries = await _jsonModelLooseSearch('api/trims/v2', year, make, modelName);
    }
    if (summaries.isEmpty) {
      summaries = await _jsonModelLooseSearch('api/trims', year, make, modelName);
    }
    if (summaries.isEmpty) {
      throw StateError(
        'No Car API trims for $make $modelName ($trimName, $year). '
        'Try another trim spelling or check your plan/year coverage.'
        '${_planYearCoverageHint(year)}',
      );
    }

    final scored = _scoreTrimSummaries(summaries, year, trimName);
    final ids = <int>[];
    for (final e in scored) {
      final id = _toInt(e.value['id']);
      if (id != null && !ids.contains(id)) ids.add(id);
    }

    final details = <Map<String, dynamic>>[];
    for (final id in ids.take(12)) {
      final d = await _getTrimDetail(id);
      if (d != null) details.add(d);
    }
    if (details.isEmpty) {
      throw StateError(
        'Car API returned trim matches but no vehicle details for $make $modelName ($trimName).',
      );
    }

    final primary = _pickBestPrimaryDetail(details, trimName, year);
    final primaryEx = _extractCarApiDetail(primary);
    final agg = _aggregateCarApiDetails(details);
    final specVariants = _dedupedSpecVariants(details);

    final raw = <String, dynamic>{
      'source': _usesRapidApiProxy ? 'carapi_rapidapi' : 'carapi',
      'trim_ids': ids.take(12).toList(),
      'primary_id': primary['id'],
    };

    return OnlineCarSpecs(
      engineSizeLiters: primaryEx.engineLiters,
      cylinderCount: primaryEx.cylinders,
      seating: primaryEx.seating,
      fuelEconomy: primaryEx.mpgLabel,
      transmission: primaryEx.transmission,
      drivetrain: primaryEx.drivetrain,
      bodyType: primaryEx.bodyType,
      engineType: primaryEx.engineType,
      fuelType: primaryEx.fuelType,
      engineSizeLiterOptions: _optionList2(agg.engineLiters),
      cylinderOptions: _optionList2(agg.cylinders),
      seatingOptions: _optionList2(agg.seatings),
      fuelEconomyOptions: _optionStringList2(agg.mpgLabels),
      transmissionOptions: _optionStringList2(agg.transmissions),
      drivetrainOptions: _optionStringList2(agg.drivetrains),
      bodyTypeOptions: _optionStringList2(agg.bodyTypes),
      engineTypeOptions: _optionStringList2(agg.engineTypes),
      fuelTypeOptions: _optionStringList2(agg.fuelTypes),
      specVariants: specVariants,
      rawAttributes: raw,
    );
  }

  static List<OnlineSpecVariant> _dedupedSpecVariants(
    List<Map<String, dynamic>> details,
  ) {
    final seen = <String>{};
    final out = <OnlineSpecVariant>[];
    for (final d in details) {
      final ex = _extractCarApiDetail(d);
      final key = _variantDedupeKey(ex);
      if (!seen.add(key)) continue;
      out.add(OnlineSpecVariant(
        engineSizeLiters: ex.engineLiters,
        cylinderCount: ex.cylinders,
        seating: ex.seating,
        fuelEconomy: ex.mpgLabel,
        transmission: ex.transmission,
        drivetrain: ex.drivetrain,
        bodyType: ex.bodyType,
        engineType: ex.engineType,
        fuelType: ex.fuelType,
      ));
    }
    return out;
  }

  static String _variantDedupeKey(_Extract ex) {
    final e = ex.engineLiters != null ? _roundEngine(ex.engineLiters!) : -1.0;
    final parts = <String>[
      e.toStringAsFixed(1),
      '${ex.cylinders ?? -1}',
      ex.transmission ?? '',
      ex.drivetrain ?? '',
      ex.bodyType ?? '',
      ex.engineType ?? '',
      ex.fuelType ?? '',
      ex.mpgLabel ?? '',
      '${ex.seating ?? -1}',
    ];
    return parts.join('|');
  }

  static List<T>? _optionList2<T extends num>(List<T> sorted) {
    if (sorted.isEmpty) return null;
    return List<T>.from(sorted);
  }

  static List<String>? _optionStringList2(List<String> sorted) {
    if (sorted.isEmpty) return null;
    return List<String>.from(sorted);
  }

  static Future<void> _ensureJwt() async {
    final now = DateTime.now();
    if (_jwt != null &&
        _jwtExpiresAt != null &&
        now.isBefore(_jwtExpiresAt!.subtract(const Duration(seconds: 90)))) {
      return;
    }

    final uri = Uri.parse('$_baseUrl/api/auth/login');
    final res = await http
        .post(
          uri,
          headers: _withRapidApiHeaders(const {
            'Content-Type': 'application/json',
            'accept': 'text/plain',
          }),
          body: json.encode({
            'api_token': _apiToken,
            'api_secret': _apiSecret,
          }),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw StateError(
        'Car API login failed (HTTP ${res.statusCode}): ${res.body}',
      );
    }

    final jwt = res.body.trim();
    if (jwt.split('.').length != 3) {
      throw StateError('Car API login returned an invalid token.');
    }
    _jwt = jwt;
    _jwtExpiresAt = _decodeJwtExp(jwt);
  }

  static DateTime? _decodeJwtExp(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      final mod = payload.length % 4;
      if (mod == 2) {
        payload += '==';
      } else if (mod == 3) {
        payload += '=';
      } else if (mod == 1) {
        return null;
      }
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      final bytes = base64.decode(payload);
      final map = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp is int) {
        return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      }
    } catch (_) {}
    return null;
  }

  static Uri _trimListUri(String endpoint, Map<String, String> queryParameters) {
    final ep = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    return Uri.parse('$_baseUrl/$ep').replace(queryParameters: queryParameters);
  }

  /// Car API documents a limited year range on free access; paid plans cover more years.
  static String _planYearCoverageHint(int year) {
    if (year > 2020 || year < 2015) {
      return ' If you are on a free or basic plan, try a year between 2015–2020 to confirm the '
          'integration works, or upgrade your Car API subscription on RapidAPI for newer years.';
    }
    return '';
  }

  /// JSON filter: model LIKE `%3%Series%` style when the catalog uses spaces the DB encodes differently.
  static Future<List<Map<String, dynamic>>> _jsonModelLooseSearch(
    String endpoint,
    int year,
    String make,
    String model,
  ) async {
    final tokens = model.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (tokens.isEmpty) return [];
    final likeVal = '%${tokens.join('%')}%';
    final filter = json.encode([
      {'field': 'year', 'op': '=', 'val': year},
      {'field': 'make', 'op': '=', 'val': make},
      {'field': 'model', 'op': 'like', 'val': likeVal},
    ]);
    return _getTrimsList(_trimListUri(endpoint, {
      'json': filter,
      'limit': '100',
    }));
  }

  /// Tries several query strategies against one list endpoint (`api/trims/v2` or legacy `api/trims`).
  static Future<List<Map<String, dynamic>>> _gatherTrimSummaries(
    String endpoint,
    int year,
    String make,
    String model,
    String trim,
  ) async {
    var s = await _getTrimsList(_trimListUri(endpoint, {
      'year': '$year',
      'make': make,
      'model': model,
      'trim': trim,
      'limit': '50',
    }));
    if (s.isEmpty) {
      final filter = json.encode([
        {'field': 'year', 'op': '=', 'val': year},
        {'field': 'make', 'op': '=', 'val': make},
        {'field': 'model', 'op': '=', 'val': model},
        {'field': 'trim', 'op': 'like', 'val': '%$trim%'},
      ]);
      s = await _getTrimsList(_trimListUri(endpoint, {
        'json': filter,
        'limit': '50',
      }));
    }
    if (s.isEmpty && trim.isNotEmpty) {
      s = await _getTrimsList(_trimListUri(endpoint, {
        'year': '$year',
        'make': make,
        'model': model,
        'description': '%$trim%',
        'limit': '80',
      }));
    }
    if (s.isEmpty) {
      s = await _getTrimsList(_trimListUri(endpoint, {
        'year': '$year',
        'make': make,
        'model': model,
        'limit': '100',
      }));
    }
    if (s.isEmpty) {
      final filter = json.encode([
        {'field': 'year', 'op': '=', 'val': year},
        {'field': 'make', 'op': '=', 'val': make},
        {'field': 'model', 'op': '=', 'val': model},
      ]);
      s = await _getTrimsList(_trimListUri(endpoint, {
        'json': filter,
        'limit': '100',
      }));
    }
    if (s.isEmpty && model.contains(' ')) {
      final hyphenated = model.replaceAll(' ', '-');
      if (hyphenated != model) {
        s = await _getTrimsList(_trimListUri(endpoint, {
          'year': '$year',
          'make': make,
          'model': hyphenated,
          'limit': '100',
        }));
      }
    }
    return s;
  }

  static Future<List<Map<String, dynamic>>> _getTrimsList(Uri uri) async {
    final res = await http
        .get(
          uri,
          headers: _authHeaders(),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw StateError(
        'Car API trim search failed (HTTP ${res.statusCode}): ${res.body}',
      );
    }
    final decoded = json.decode(res.body);
    List<dynamic>? rows;
    if (decoded is List) {
      rows = decoded;
    } else if (decoded is Map) {
      final m = Map<String, dynamic>.from(decoded);
      final data = m['data'];
      if (data is List) {
        rows = data;
      } else {
        for (final k in const ['results', 'items', 'trims']) {
          final v = m[k];
          if (v is List) {
            rows = v;
            break;
          }
        }
      }
    }
    if (rows == null) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in rows) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(item as Map));
      }
    }
    return out;
  }

  static Map<String, dynamic>? _unwrapEntityMap(dynamic decoded) {
    if (decoded is! Map) return null;
    var m = Map<String, dynamic>.from(decoded);
    final nested = m['data'];
    if (nested is Map) {
      m = Map<String, dynamic>.from(nested);
    }
    return m;
  }

  static Future<Map<String, dynamic>?> _getTrimDetail(int id) async {
    for (final path in const ['api/trims/v2', 'api/trims']) {
      final uri = Uri.parse('$_baseUrl/$path/$id');
      final res = await http
          .get(
            uri,
            headers: _authHeaders(),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) continue;
      final m = _unwrapEntityMap(json.decode(res.body));
      if (m != null) return m;
    }
    return null;
  }

  static Map<String, String> _authHeaders() {
    if (_usesRapidApiProxy) {
      return _withRapidApiHeaders(const {'accept': 'application/json'});
    }
    return _withRapidApiHeaders(<String, String>{
      'accept': 'application/json',
      if (_jwt != null) 'Authorization': 'Bearer $_jwt',
    });
  }

  /// Best string match for user trim across API fields (330i often appears in [description] only).
  static int _trimRowMatchScore(String trimQuery, Map<String, dynamic> m) {
    final parts = <String>[
      '${m['trim'] ?? ''}',
      '${m['submodel'] ?? ''}',
      '${m['description'] ?? ''}',
      '${m['series'] ?? ''}',
    ];
    var best = 0;
    for (final p in parts) {
      final s = _trimScoreStrings(trimQuery, p);
      final a = _trimCodeAnchorScore(trimQuery, p);
      if (s + a > best) best = s + a;
    }
    return best;
  }

  static List<MapEntry<int, Map<String, dynamic>>> _scoreTrimSummaries(
    List<Map<String, dynamic>> rows,
    int year,
    String trimQuery,
  ) {
    final scored = <MapEntry<int, Map<String, dynamic>>>[];
    for (final m in rows) {
      var s = _trimRowMatchScore(trimQuery, m);
      final y = _toInt(m['year']);
      if (y == year) s += 55;
      scored.add(MapEntry(s, m));
    }
    scored.sort((a, b) => b.key.compareTo(a.key));
    return scored;
  }

  static Map<String, dynamic> _pickBestPrimaryDetail(
    List<Map<String, dynamic>> details,
    String trimQuery,
    int year,
  ) {
    var best = details.first;
    var bestC = -1;
    var bestTrimSc = -1;
    for (final d in details) {
      var trimSc = _trimRowMatchScore(trimQuery, d);
      final y = _toInt(d['year']);
      if (y == year) trimSc += 55;
      final c = _rowCompleteness(d);
      if (c > bestC || (c == bestC && trimSc > bestTrimSc)) {
        bestC = c;
        bestTrimSc = trimSc;
        best = d;
      }
    }
    return best;
  }

  static int _rowCompleteness(Map<String, dynamic> detail) {
    final ex = _extractCarApiDetail(detail);
    var n = 0;
    if (ex.transmission != null) n += 4;
    if (ex.bodyType != null) n += 4;
    if (ex.drivetrain != null) n += 2;
    if (ex.engineLiters != null) n += 3;
    if (ex.cylinders != null) n += 3;
    if (ex.seating != null) n += 3;
    if (ex.mpgLabel != null) n += 1;
    if (ex.fuelType != null) n += 1;
    return n;
  }

  static _Aggregate _aggregateCarApiDetails(List<Map<String, dynamic>> details) {
    final engineLiters = <double>{};
    final cylinders = <int>{};
    final seatings = <int>{};
    final mpgLabels = <String>{};
    final transmissions = <String>{};
    final drivetrains = <String>{};
    final bodyTypes = <String>{};
    final engineTypes = <String>{};
    final fuelTypes = <String>{};

    for (final d in details) {
      final ex = _extractCarApiDetail(d);
      if (ex.engineLiters != null) engineLiters.add(_roundEngine(ex.engineLiters!));
      if (ex.cylinders != null) cylinders.add(ex.cylinders!);
      if (ex.seating != null) seatings.add(ex.seating!);
      if (ex.mpgLabel != null) mpgLabels.add(ex.mpgLabel!);
      if (ex.transmission != null) transmissions.add(ex.transmission!);
      if (ex.drivetrain != null) drivetrains.add(ex.drivetrain!);
      if (ex.bodyType != null) bodyTypes.add(ex.bodyType!);
      if (ex.engineType != null) engineTypes.add(ex.engineType!);
      if (ex.fuelType != null) fuelTypes.add(ex.fuelType!);
    }

    return _Aggregate(
      engineLiters: _sortedNums(engineLiters),
      cylinders: _sortedInts(cylinders),
      seatings: _sortedInts(seatings),
      mpgLabels: _sortedStrings(mpgLabels),
      transmissions: _sortedStrings(transmissions),
      drivetrains: _sortedStrings(drivetrains),
      bodyTypes: _sortedStrings(bodyTypes),
      engineTypes: _sortedStrings(engineTypes),
      fuelTypes: _sortedStrings(fuelTypes),
    );
  }

  static _Extract _extractCarApiDetail(Map<String, dynamic> d) {
    final body = _trimEmbedding(d, 'bodies', 'make_model_trim_body');
    final eng = _trimEmbedding(d, 'engines', 'make_model_trim_engine');
    final mileage =
        _trimEmbedding(d, 'mileages', 'make_model_trim_mileage');

    final transmission = _mapTransmission(eng?['transmission']?.toString());
    final drivetrain = _mapDrivetrain(eng?['drive_type']?.toString());
    final bodyType = _mapBodyType(body?['type']?.toString());
    final fuelType = _mapFuelType(eng?['fuel_type']?.toString());
    final engineType = _mapEngineType(eng?['engine_type']?.toString(), fuelType);

    final engineLiters = _toDouble(eng?['size']);
    final cylinders = _parseCylinderField(eng?['cylinders']);
    final seating = _parseSeating(body?['seats']);

    final city = _toNum(mileage?['epa_city_mpg']);
    final hwy = _toNum(mileage?['epa_highway_mpg']);
    final comb = _toNum(mileage?['combined_mpg']);
    String? mpgLabel;
    if (city != null && hwy != null) {
      mpgLabel = '$city/$hwy MPG (city/hwy)';
    } else if (comb != null) {
      mpgLabel = '$comb MPG (combined)';
    }

    final structured = _Extract(
      engineLiters: engineLiters,
      cylinders: cylinders,
      seating: seating,
      mpgLabel: mpgLabel,
      transmission: transmission,
      drivetrain: drivetrain,
      bodyType: bodyType,
      engineType: engineType ?? fuelType,
      fuelType: fuelType ?? engineType,
    );

    final desc = d['description']?.toString();
    return _mergeExtractPreferBase(structured, _extractFromDescriptionText(desc));
  }

  static Map<String, dynamic>? _firstMapInList(dynamic list) {
    if (list is! List || list.isEmpty) return null;
    final first = list.first;
    if (first is! Map) return null;
    return Map<String, dynamic>.from(first as Map);
  }

  /// v2 uses [bodies]/[engines]/[mileages] lists; v1 detail uses singular [make_model_trim_*] objects.
  static Map<String, dynamic>? _trimEmbedding(
    Map<String, dynamic> d,
    String listKey,
    String v1ObjectKey,
  ) {
    final listOrObj = d[listKey];
    if (listOrObj is Map) {
      return Map<String, dynamic>.from(listOrObj);
    }
    final fromList = _firstMapInList(listOrObj);
    if (fromList != null) return fromList;
    final v1 = d[v1ObjectKey];
    if (v1 is Map) return Map<String, dynamic>.from(v1);
    return null;
  }

  static _Extract _mergeExtractPreferBase(_Extract base, _Extract fallback) {
    return _Extract(
      engineLiters: base.engineLiters ?? fallback.engineLiters,
      cylinders: base.cylinders ?? fallback.cylinders,
      seating: base.seating ?? fallback.seating,
      mpgLabel: base.mpgLabel ?? fallback.mpgLabel,
      transmission: base.transmission ?? fallback.transmission,
      drivetrain: base.drivetrain ?? fallback.drivetrain,
      bodyType: base.bodyType ?? fallback.bodyType,
      engineType: base.engineType ?? fallback.engineType,
      fuelType: base.fuelType ?? fallback.fuelType,
    );
  }

  /// When structured body/engine rows are missing (common on trimmed responses), parse [description].
  static _Extract _extractFromDescriptionText(String? description) {
    if (description == null || description.trim().isEmpty) {
      return _Extract();
    }
    final s = description;

    double? liters;
    final mLit = RegExp(r'(\d+\.\d+)\s*[lL]\b').firstMatch(s);
    if (mLit != null) {
      liters = double.tryParse(mLit.group(1)!);
    } else {
      final mLit2 = RegExp(r'\b(\d+)\s*[lL]\s*(?:I4|V6|V8|6cyl|4cyl)').firstMatch(s);
      if (mLit2 != null) liters = double.tryParse(mLit2.group(1)!);
    }

    int? cyl;
    final mCyl = RegExp(r'(\d+)\s*[cC]yl').firstMatch(s);
    if (mCyl != null) cyl = int.tryParse(mCyl.group(1)!);
    int? seats;
    final mDr = RegExp(r'(\d+)\s*[dD]r').firstMatch(s);
    if (mDr != null) {
      final doors = int.tryParse(mDr.group(1)!);
      if (doors != null && doors >= 4) seats = 5;
    }

    final low = s.toLowerCase();
    final bodyType = _mapBodyType(s);
    final transmission = _mapTransmission(s) ??
        (RegExp(r'\d+\s*[sS]peed|\b[mcC][vV][tT]|Turbo\s+\d+[aA]\b').hasMatch(s)
            ? 'automatic'
            : null);

    String? drivetrain;
    if (low.contains('xdrive') ||
        low.contains('x-drive') ||
        low.contains(' awd') ||
        low.contains('all-wheel')) {
      drivetrain = 'awd';
    } else if (low.contains(' rwd') || low.contains('rear-wheel')) {
      drivetrain = 'rwd';
    } else if (low.contains(' fwd') || low.contains('front-wheel')) {
      drivetrain = 'fwd';
    }

    String? fuelType;
    String? engineType;
    if (low.contains('diesel')) {
      fuelType = 'diesel';
      engineType = 'diesel';
    } else if (low.contains('electric') || low.contains(' kwh')) {
      fuelType = 'electric';
      engineType = 'electric';
    } else if (low.contains('hybrid') || low.contains('phev')) {
      fuelType = 'hybrid';
      engineType = 'hybrid';
    } else if (low.contains('gas') ||
        low.contains('turbo') ||
        low.contains('unleaded') ||
        cyl != null) {
      fuelType = 'gasoline';
      engineType = 'gasoline';
    }

    return _Extract(
      engineLiters: liters,
      cylinders: cyl,
      seating: seats,
      transmission: transmission,
      drivetrain: drivetrain,
      bodyType: bodyType,
      engineType: engineType,
      fuelType: fuelType,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static int? _parseCylinderField(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().toLowerCase();
    final m = RegExp(r'(\d+)').firstMatch(s);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  static double _roundEngine(double x) => double.parse(x.toStringAsFixed(1));

  static List<double> _sortedNums(Set<double> s) {
    final l = s.toList()..sort();
    return l;
  }

  static List<int> _sortedInts(Set<int> s) {
    final l = s.toList()..sort();
    return l;
  }

  static List<String> _sortedStrings(Set<String> s) {
    final l = s.toList()..sort();
    return l;
  }

  static int _trimScoreStrings(String query, String candidate) {
    final q = _norm(query);
    final c = _norm(candidate);
    if (q.isEmpty) return c.isEmpty ? 0 : 5;
    if (c.isEmpty) return 0;
    if (q == c) return 200;
    if (c.contains(q) || q.contains(c)) return 150;
    final qWords = q.split(' ').where((w) => w.isNotEmpty).toSet();
    final cWords = c.split(' ').where((w) => w.isNotEmpty).toSet();
    return qWords.intersection(cWords).length * 22;
  }

  static int _trimCodeAnchorScore(String userTrim, String apiTrim) {
    final u = userTrim.toLowerCase();
    final a = apiTrim.toLowerCase();
    final m3 = RegExp(r'\d{3}i?').firstMatch(u)?.group(0);
    if (m3 == null || m3.length < 3) return 0;
    final code = m3.length > 3 ? m3.substring(0, 3) : m3;
    if (a.contains(m3) || a.contains(code)) return 45;
    final api3 = RegExp(r'\d{3}').firstMatch(a)?.group(0);
    if (api3 != null && api3 != code) return -35;
    return 0;
  }

  static String _norm(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static int? _parseSeating(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return _firstInt(v.toString());
  }

  static int? _firstInt(String s) {
    final m = RegExp(r'(\d+)').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString().trim());
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static String? _mapTransmission(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.toLowerCase().trim();
    if (s.length <= 6) {
      switch (s) {
        case 'm':
        case 'mt':
          return 'manual';
        case 'a':
        case 'at':
        case 'c':
        case 'cvt':
        case 'd':
        case 'dct':
        case 's':
          return 'automatic';
        default:
          break;
      }
    }
    if (s.contains('manual')) return 'manual';
    if (s.contains('auto') ||
        s.contains('cvt') ||
        s.contains('variable') ||
        s.contains('direct drive') ||
        RegExp(r'\d+\s*-?\s*speed').hasMatch(s)) {
      return 'automatic';
    }
    return null;
  }

  static String? _mapDrivetrain(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.toLowerCase();
    if (s.contains('awd') || s.contains('all wheel')) return 'awd';
    if (s.contains('4wd') || s.contains('4x4') || s.contains('four wheel')) {
      return '4wd';
    }
    if (s.contains('rwd') || s.contains('rear wheel')) return 'rwd';
    if (s.contains('fwd') || s.contains('front wheel')) return 'fwd';
    return null;
  }

  static String? _mapBodyType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.toLowerCase();
    if (s.contains('suv') ||
        s.contains('sport utility') ||
        s.contains('crossover') ||
        s.contains('cuv')) {
      return 'suv';
    }
    if (s.contains('sedan')) return 'sedan';
    if (s.contains('hatch')) return 'hatchback';
    if (s.contains('gran coupe') || s.contains('gran-coupe')) return 'coupe';
    if (s.contains('coupe')) return 'coupe';
    if (s.contains('convertible') || s.contains('cabrio')) return 'convertible';
    if (s.contains('wagon') || s.contains('touring') || s.contains('avant')) {
      return 'wagon';
    }
    if (s.contains('van') || s.contains('minivan')) return 'van';
    if (s.contains('pickup') || s.contains('truck')) return 'pickup';
    if (RegExp(r'\b(car|sedan)\b').hasMatch(s) &&
        !s.contains('suv') &&
        !s.contains('truck')) {
      return 'sedan';
    }
    return null;
  }

  static String? _mapEngineType(String? raw, String? fuelFallback) {
    if (raw != null && raw.isNotEmpty) {
      final s = raw.toLowerCase();
      if (s.contains('electric') || s.contains('bev')) return 'electric';
      if (s.contains('hybrid') || s.contains('phev') || s.contains('plug')) {
        return 'hybrid';
      }
      if (s.contains('diesel')) return 'diesel';
      if (s.contains('gas') || s.contains('ice') || s.contains('flex')) {
        return 'gasoline';
      }
    }
    return fuelFallback;
  }

  static String? _mapFuelType(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final s = raw.toLowerCase();
    if (s.contains('electric')) return 'electric';
    if (s.contains('diesel')) return 'diesel';
    if (s.contains('hybrid') || s.contains('phev')) return 'hybrid';
    if (s.contains('gas') ||
        s.contains('unleaded') ||
        s.contains('premium') ||
        s.contains('flex') ||
        s.contains('e85')) {
      return 'gasoline';
    }
    return null;
  }
}

class _Extract {
  _Extract({
    this.engineLiters,
    this.cylinders,
    this.seating,
    this.mpgLabel,
    this.transmission,
    this.drivetrain,
    this.bodyType,
    this.engineType,
    this.fuelType,
  });

  final double? engineLiters;
  final int? cylinders;
  final int? seating;
  final String? mpgLabel;
  final String? transmission;
  final String? drivetrain;
  final String? bodyType;
  final String? engineType;
  final String? fuelType;
}

class _Aggregate {
  _Aggregate({
    required this.engineLiters,
    required this.cylinders,
    required this.seatings,
    required this.mpgLabels,
    required this.transmissions,
    required this.drivetrains,
    required this.bodyTypes,
    required this.engineTypes,
    required this.fuelTypes,
  });

  final List<double> engineLiters;
  final List<int> cylinders;
  final List<int> seatings;
  final List<String> mpgLabels;
  final List<String> transmissions;
  final List<String> drivetrains;
  final List<String> bodyTypes;
  final List<String> engineTypes;
  final List<String> fuelTypes;
}

/// One coherent equipment set from a Car API trim detail (engine size ↔ cylinders, etc.).
class OnlineSpecVariant {
  const OnlineSpecVariant({
    this.engineSizeLiters,
    this.cylinderCount,
    this.seating,
    this.fuelEconomy,
    this.transmission,
    this.drivetrain,
    this.bodyType,
    this.engineType,
    this.fuelType,
  });

  final double? engineSizeLiters;
  final int? cylinderCount;
  final int? seating;
  final String? fuelEconomy;
  final String? transmission;
  final String? drivetrain;
  final String? bodyType;
  final String? engineType;
  final String? fuelType;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'engine_l': engineSizeLiters,
        'cyl': cylinderCount,
        'seat': seating,
        'mpg': fuelEconomy,
        'tr': transmission,
        'drv': drivetrain,
        'body': bodyType,
        'engt': engineType,
        'fuel': fuelType,
      };

  factory OnlineSpecVariant.fromJson(Map<String, dynamic> m) {
    return OnlineSpecVariant(
      engineSizeLiters: (m['engine_l'] as num?)?.toDouble(),
      cylinderCount: (m['cyl'] as num?)?.toInt(),
      seating: (m['seat'] as num?)?.toInt(),
      fuelEconomy: m['mpg']?.toString(),
      transmission: m['tr']?.toString(),
      drivetrain: m['drv']?.toString(),
      bodyType: m['body']?.toString(),
      engineType: m['engt']?.toString(),
      fuelType: m['fuel']?.toString(),
    );
  }

  /// [anchors] names which fields the user just changed (only those filter variants).
  /// Keys: `e` engine L, `c` cylinders, `tr` transmission, `drv` drivetrain, `body`, `engt`,
  /// `fuel`, `mpg`, `seat`.
  static OnlineSpecVariant? matchBestAnchored(
    List<OnlineSpecVariant> variants,
    Set<String> anchors, {
    double? engineLiters,
    int? cylinders,
    String? transmission,
    String? drivetrain,
    String? bodyType,
    String? engineType,
    String? fuelType,
    String? fuelEconomy,
    int? seating,
    String? currentTransmission,
    String? currentDrivetrain,
    int? currentSeating,
  }) {
    bool anchoredOk(OnlineSpecVariant v) {
      if (anchors.contains('e') &&
          engineLiters != null &&
          v.engineSizeLiters != null) {
        if ((v.engineSizeLiters! - engineLiters).abs() > 0.06) return false;
      }
      if (anchors.contains('c') && cylinders != null && v.cylinderCount != null) {
        if (v.cylinderCount != cylinders) return false;
      }
      if (anchors.contains('tr') &&
          transmission != null &&
          v.transmission != null &&
          v.transmission != transmission) {
        return false;
      }
      if (anchors.contains('drv') &&
          drivetrain != null &&
          v.drivetrain != null &&
          v.drivetrain != drivetrain) {
        return false;
      }
      if (anchors.contains('body') &&
          bodyType != null &&
          v.bodyType != null &&
          v.bodyType != bodyType) {
        return false;
      }
      if (anchors.contains('engt') &&
          engineType != null &&
          v.engineType != null &&
          v.engineType != engineType) {
        return false;
      }
      if (anchors.contains('fuel') &&
          fuelType != null &&
          v.fuelType != null &&
          v.fuelType != fuelType) {
        return false;
      }
      if (anchors.contains('mpg') &&
          fuelEconomy != null &&
          v.fuelEconomy != null &&
          v.fuelEconomy != fuelEconomy) {
        return false;
      }
      if (anchors.contains('seat') && seating != null && v.seating != null) {
        if (v.seating != seating) return false;
      }
      return true;
    }

    var cands = variants.where(anchoredOk).toList();
    if (cands.isEmpty) return null;
    if (cands.length == 1) return cands.first;

    OnlineSpecVariant? prefer(
      List<OnlineSpecVariant> list,
      bool Function(OnlineSpecVariant) p,
    ) {
      final x = list.where(p).toList();
      return x.length == 1 ? x.first : null;
    }

    if (!anchors.contains('tr') && currentTransmission != null) {
      final p = prefer(cands, (v) => v.transmission == currentTransmission);
      if (p != null) return p;
    }
    if (!anchors.contains('drv') && currentDrivetrain != null) {
      final p = prefer(cands, (v) => v.drivetrain == currentDrivetrain);
      if (p != null) return p;
    }
    if (!anchors.contains('seat') && currentSeating != null) {
      final p = prefer(cands, (v) => v.seating == currentSeating);
      if (p != null) return p;
    }
    return cands.first;
  }
}

class OnlineCarSpecs {
  const OnlineCarSpecs({
    this.engineSizeLiters,
    this.cylinderCount,
    this.seating,
    this.fuelEconomy,
    this.transmission,
    this.drivetrain,
    this.bodyType,
    this.engineType,
    this.fuelType,
    required this.rawAttributes,
    this.engineSizeLiterOptions,
    this.cylinderOptions,
    this.seatingOptions,
    this.fuelEconomyOptions,
    this.transmissionOptions,
    this.drivetrainOptions,
    this.bodyTypeOptions,
    this.engineTypeOptions,
    this.fuelTypeOptions,
    this.specVariants = const [],
  });

  final double? engineSizeLiters;
  final int? cylinderCount;
  final int? seating;
  final String? fuelEconomy;
  final String? transmission;
  final String? drivetrain;
  final String? bodyType;
  final String? engineType;
  final String? fuelType;
  final Map<String, dynamic> rawAttributes;

  final List<double>? engineSizeLiterOptions;
  final List<int>? cylinderOptions;
  final List<int>? seatingOptions;
  final List<String>? fuelEconomyOptions;
  final List<String>? transmissionOptions;
  final List<String>? drivetrainOptions;
  final List<String>? bodyTypeOptions;
  final List<String>? engineTypeOptions;
  final List<String>? fuelTypeOptions;

  /// Distinct equipment rows from matched trims; used to keep specs consistent when user changes one field.
  final List<OnlineSpecVariant> specVariants;
}
