import 'package:url_launcher/url_launcher.dart';

/// Opens the default browser with a web search for [vin].
Future<bool> openVinSearch(String vin) async {
  final trimmed = vin.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.https('www.google.com', '/search', {'q': trimmed});
  var ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
  return ok;
}
