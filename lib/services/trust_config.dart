import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'config.dart';
import '../shared/debug/app_log.dart';

/// Support contact + legal URLs (server env with optional dart-define overrides).
class TrustConfig {
  TrustConfig._();

  static TrustConfigData? _cached;

  @visibleForTesting
  static void resetCacheForTests() {
    _cached = null;
  }

  static Future<TrustConfigData> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) return _cached!;

    TrustConfigData fromApi = const TrustConfigData();
    try {
      final uri = Uri.parse('${effectiveApiBase()}/api/config/trust');
      final res = await ApiService.getHttp(uri);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (decoded is Map) {
          fromApi = TrustConfigData.fromJson(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
        }
      }
    } catch (e, st) { logNonFatal(e, st); }

    _cached = TrustConfigData(
      supportEmail: _pick(kSupportEmail, fromApi.supportEmail),
      supportPhone: _pick(kSupportPhone, fromApi.supportPhone),
      supportWhatsapp: _pick(kSupportWhatsapp, fromApi.supportWhatsapp),
      termsUrl: _pick(kTermsUrl, fromApi.termsUrl),
      privacyUrl: _pick(kPrivacyUrl, fromApi.privacyUrl),
    );
    return _cached!;
  }

  static String _pick(String define, String api, [String fallback = '']) {
    final d = define.trim();
    if (d.isNotEmpty) return d;
    final a = api.trim();
    if (a.isNotEmpty) return a;
    return fallback;
  }
}

class TrustConfigData {
  final String supportEmail;
  final String supportPhone;
  final String supportWhatsapp;
  final String termsUrl;
  final String privacyUrl;

  const TrustConfigData({
    this.supportEmail = '',
    this.supportPhone = '',
    this.supportWhatsapp = '',
    this.termsUrl = '',
    this.privacyUrl = '',
  });

  factory TrustConfigData.fromJson(Map<String, dynamic> json) {
    String s(dynamic k) => (json[k] ?? '').toString().trim();
    return TrustConfigData(
      supportEmail: s('support_email'),
      supportPhone: s('support_phone'),
      supportWhatsapp: s('support_whatsapp'),
      termsUrl: s('terms_url'),
      privacyUrl: s('privacy_url'),
    );
  }
}
