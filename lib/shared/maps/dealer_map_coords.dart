/// Parses latitude/longitude from JSON (num, String, or null).
double? parseDealerCoord(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final t = value.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
  return null;
}

bool isValidDealerLatLng(double lat, double lng) {
  return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}
