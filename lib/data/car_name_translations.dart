import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Arabic and Kurdish names for car brands, models, and trims.
///
/// Large maps live in [assets/i18n/car_names_*.json] and are loaded on demand
/// for the active locale only (not both), to avoid ~350KB of const maps in the
/// Dart isolate from app start.
class CarNameTranslations {
  CarNameTranslations._();

  static final Map<String, _CarNameLocalePack> _packs =
      <String, _CarNameLocalePack>{};
  static final Map<String, Future<_CarNameLocalePack?>> _loading =
      <String, Future<_CarNameLocalePack?>>{};

  static const Map<String, String> _latinToAr = {
    'a': 'ا', 'b': 'ب', 'c': 'ك', 'd': 'د', 'e': 'ي', 'f': 'ف', 'g': 'ج', 'h': 'ه',
    'i': 'ي', 'j': 'ج', 'k': 'ك', 'l': 'ل', 'm': 'م', 'n': 'ن', 'o': 'و', 'p': 'ب',
    'q': 'ك', 'r': 'ر', 's': 'س', 't': 'ت', 'u': 'و', 'v': 'ف', 'w': 'و', 'x': 'كس',
    'y': 'ي', 'z': 'ز',
  };
  static const Map<String, String> _latinToKu = {
    'a': 'ا', 'b': 'ب', 'c': 'ک', 'd': 'د', 'e': 'ێ', 'f': 'ف', 'g': 'گ', 'h': 'ه',
    'i': 'ی', 'j': 'ژ', 'k': 'ک', 'l': 'ڵ', 'm': 'م', 'n': 'ن', 'o': 'ۆ', 'p': 'پ',
    'q': 'ک', 'r': 'ڕ', 's': 'س', 't': 'ت', 'u': 'و', 'v': 'ڤ', 'w': 'و', 'x': 'کس',
    'y': 'ی', 'z': 'ز',
  };

  static String _key(String? s) => (s ?? '').trim().toLowerCase();

  /// Lookup forms for catalog keys: raw, hyphen↔space (Land-Rover ↔ land rover).
  static Iterable<String> _keyVariants(String? s) sync* {
    final base = _key(s);
    if (base.isEmpty) return;
    yield base;
    final spaced = base
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (spaced.isNotEmpty && spaced != base) yield spaced;
    final hyphenated = spaced.replaceAll(' ', '-');
    if (hyphenated.isNotEmpty &&
        hyphenated != base &&
        hyphenated != spaced) {
      yield hyphenated;
    }
  }

  static String? _packLookup(Map<String, String> map, String? raw) {
    for (final k in _keyVariants(raw)) {
      final v = map[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static String? _packModelLookup(
    Map<String, String> models,
    String? brand,
    String? model,
  ) {
    for (final bk in _keyVariants(brand)) {
      for (final mk in _keyVariants(model)) {
        final v = models['$bk|$mk'];
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  /// True if token is a short alphanumeric code to keep in English: has a digit (X7, M5, X80, 4Runner)
  /// or is very short letters only (iX, RX, M). Words like Land, Santa, Bestune are false.
  static bool _isCodeLike(String token) {
    final t = token.trim();
    if (t.isEmpty) return true;
    if (!RegExp(r'^[a-zA-Z0-9\-\.]+$').hasMatch(t)) return false;
    if (RegExp(r'\d').hasMatch(t) && t.length <= 8) return true;
    if (t.length <= 2 && RegExp(r'^[A-Za-z]+$').hasMatch(t)) return true;
    return false;
  }

  static String _transliterateToken(String token, bool isAr) {
    final map = isAr ? _latinToAr : _latinToKu;
    final out = StringBuffer();
    for (var i = 0; i < token.length; i++) {
      final ch = token[i];
      final c = ch.toLowerCase();
      if (map.containsKey(c)) {
        out.write(map[c]);
      } else if (RegExp(r'[0-9\-.]').hasMatch(ch)) {
        out.write(ch);
      } else {
        out.write(ch);
      }
    }
    return out.toString();
  }

  static bool _isTranslatedLocale(String? code) =>
      code == 'ar' || code == 'ku';

  /// Load JSON pack for [languageCode] (`ar` / `ku`). No-op for other locales.
  /// Drops the other translated locale from memory after a successful load.
  static Future<void> ensureLoadedForLocale(String? languageCode) async {
    final code = languageCode?.trim().toLowerCase();
    if (!_isTranslatedLocale(code)) {
      _packs.remove('ar');
      _packs.remove('ku');
      return;
    }
    await _packFor(code!);
    // Keep only the active translated locale in memory.
    for (final other in const ['ar', 'ku']) {
      if (other != code) _packs.remove(other);
    }
  }

  static Future<_CarNameLocalePack?> _packFor(String code) {
    final cached = _packs[code];
    if (cached != null) return Future<_CarNameLocalePack?>.value(cached);
    return _loading.putIfAbsent(code, () async {
      try {
        final raw =
            await rootBundle.loadString('assets/i18n/car_names_$code.json');
        final decoded = json.decode(raw);
        if (decoded is! Map) return null;
        final pack = _CarNameLocalePack.fromJson(decoded);
        _packs[code] = pack;
        return pack;
      } catch (e, st) {
        // Avoid Sentry during asset miss in tests; still log in debug.
        if (kDebugMode) {
          debugPrint('CarNameTranslations.load.$code failed: $e');
          debugPrint('$st');
        }
        return null;
      } finally {
        _loading.remove(code);
      }
    });
  }

  static _CarNameLocalePack? _cachedPack(String locale) => _packs[locale];

  static String getLocalizedBrand(BuildContext context, String? brand) {
    return getLocalizedBrandForLocale(
      Localizations.localeOf(context).languageCode,
      brand,
    );
  }

  /// Locale-code variant (useful for tests and non-widget callers).
  static String getLocalizedBrandForLocale(String languageCode, String? brand) {
    if (brand == null || brand.isEmpty) return '';
    final pack = _cachedPack(languageCode);
    if (pack == null) return brand;
    return _packLookup(pack.brands, brand) ?? brand;
  }

  static String getLocalizedModel(
    BuildContext context,
    String? brand,
    String? model,
  ) {
    return getLocalizedModelForLocale(
      Localizations.localeOf(context).languageCode,
      brand,
      model,
    );
  }

  static String getLocalizedModelForLocale(
    String languageCode,
    String? brand,
    String? model,
  ) {
    if (model == null || model.isEmpty) return '';
    if (!_isTranslatedLocale(languageCode)) return model;

    final tokens = model.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return model;
    if (tokens.every(_isCodeLike)) return model;

    final pack = _cachedPack(languageCode);
    if (pack == null) return model;

    final isAr = languageCode == 'ar';
    final existing = _packModelLookup(pack.models, brand, model);
    if (existing != null) return existing;

    final parts = <String>[];
    for (final token in tokens) {
      if (_isCodeLike(token)) {
        parts.add(token);
      } else {
        final singleTr = _packModelLookup(pack.models, brand, token);
        parts.add(singleTr ?? _transliterateToken(token, isAr));
      }
    }
    final joined = parts.join(' ').trim();
    return joined.isEmpty ? model : joined;
  }

  /// Returns localized trim name for current locale, or original if not found.
  static String getLocalizedTrim(BuildContext context, String? trim) {
    return getLocalizedTrimForLocale(
      Localizations.localeOf(context).languageCode,
      trim,
    );
  }

  static String getLocalizedTrimForLocale(String languageCode, String? trim) {
    if (trim == null || trim.isEmpty) return '';
    final pack = _cachedPack(languageCode);
    if (pack == null) return trim;
    return _packLookup(pack.trims, trim) ?? trim;
  }

  /// Returns localized "Brand Model" or "Brand Model Trim" for display.
  static String getLocalizedCarTitle(
    BuildContext context,
    Map<String, dynamic>? car,
  ) {
    if (car == null) return '';
    final brand = car['brand']?.toString().trim() ?? '';
    final model = car['model']?.toString().trim() ?? '';
    final trim = car['trim']?.toString().trim();
    final year = car['year']?.toString().trim();

    final locBrand = getLocalizedBrand(context, brand.isEmpty ? null : brand);
    final locModel = getLocalizedModel(
      context,
      brand.isEmpty ? null : brand,
      model.isEmpty ? null : model,
    );
    final parts = <String>[locBrand, locModel];
    if (trim != null && trim.isNotEmpty) {
      parts.add(trim);
    }
    var title = parts.join(' ').trim();
    if (year != null && year.isNotEmpty) {
      title = '$title $year'.trim();
    }
    return title.isEmpty ? (car['title']?.toString() ?? '') : title;
  }

  /// Brand + model only (no trim, no year). Caller can append translated trim.
  static String getLocalizedCarTitleNoYear(
    BuildContext context,
    Map<String, dynamic>? car,
  ) {
    if (car == null) return '';
    final brand = car['brand']?.toString().trim() ?? '';
    final model = car['model']?.toString().trim() ?? '';

    final locBrand = getLocalizedBrand(context, brand.isEmpty ? null : brand);
    final locModel = getLocalizedModel(
      context,
      brand.isEmpty ? null : brand,
      model.isEmpty ? null : model,
    );
    final title = [locBrand, locModel].join(' ').trim();
    return title.isEmpty ? (car['title']?.toString() ?? '') : title;
  }

  @visibleForTesting
  static void debugResetForTest() {
    _packs.clear();
    _loading.clear();
  }

  @visibleForTesting
  static bool debugHasPack(String languageCode) =>
      _packs.containsKey(languageCode);

  @visibleForTesting
  static void debugInstallPack(
    String languageCode, {
    required Map<String, String> brands,
    Map<String, String> models = const <String, String>{},
    Map<String, String> trims = const <String, String>{},
  }) {
    _packs[languageCode] = _CarNameLocalePack(
      brands: brands,
      models: models,
      trims: trims,
    );
  }
}

class _CarNameLocalePack {
  const _CarNameLocalePack({
    required this.brands,
    required this.models,
    required this.trims,
  });

  final Map<String, String> brands;
  final Map<String, String> models;
  final Map<String, String> trims;

  factory _CarNameLocalePack.fromJson(Map<dynamic, dynamic> json) {
    Map<String, String> asStringMap(Object? raw) {
      if (raw is! Map) return const <String, String>{};
      return {
        for (final e in raw.entries)
          e.key.toString(): e.value?.toString() ?? '',
      };
    }

    return _CarNameLocalePack(
      brands: asStringMap(json['brands']),
      models: asStringMap(json['models']),
      trims: asStringMap(json['trims']),
    );
  }
}
