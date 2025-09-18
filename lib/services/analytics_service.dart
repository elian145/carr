import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class AnalyticsService {
  static String _base() {
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:5000';
    } catch (_) {}
    return 'http://localhost:5000';
  }

  static Future<void> trackEvent(String name, {Map<String, dynamic>? properties}) async {
    try {
      final uri = Uri.parse(_base() + '/api/analytics');
      final body = json.encode({
        'name': name,
        'properties': properties ?? {},
        'ts': DateTime.now().toIso8601String(),
      });
      unawaited(http.post(uri, headers: {'Content-Type': 'application/json'}, body: body));
    } catch (_) {
      // swallow errors
    }
  }
}
