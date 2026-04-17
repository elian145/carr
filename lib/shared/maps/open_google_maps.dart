import 'package:url_launcher/url_launcher.dart';

/// Opens the native Google Maps app or browser at [latitude], [longitude].
Future<bool> openGoogleMapsAt(double latitude, double longitude, {String? label}) async {
  final labelTrim = label?.trim() ?? '';
  final query = labelTrim.isNotEmpty ? labelTrim : '$latitude,$longitude';
  final uri = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
  var ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
  return ok;
}
