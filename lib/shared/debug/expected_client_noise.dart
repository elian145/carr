/// Operational failures that already have UI/fallback handling.
///
/// These should not be reported as Sentry errors: missing listing photos,
/// Flutter's removed AssetManifest.json, and iOS sockets reclaimed in
/// the background.
bool isExpectedClientNoise(Object error) {
  final text = error.toString();
  final lower = text.toLowerCase();

  if (lower.contains('unable to load asset') &&
      lower.contains('assetmanifest')) {
    return true;
  }
  if (isPermanentHttpImageError(error)) return true;
  if (isStaleHttpClientError(error)) return true;
  return false;
}

/// HTTP 403/404/410 (and similar) for listing media — retrying cannot help.
bool isPermanentHttpImageError(Object error) {
  final lower = error.toString().toLowerCase();
  final isClientErrorStatus =
      lower.contains('statuscode: 404') ||
      lower.contains('statuscode: 403') ||
      lower.contains('statuscode: 410') ||
      lower.contains('invalid statuscode: 404') ||
      lower.contains('invalid statuscode: 403') ||
      lower.contains('invalid statuscode: 410');
  if (!isClientErrorStatus) return false;
  return lower.contains('/static/uploads/') ||
      lower.contains('car_photos') ||
      lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.png') ||
      lower.contains('.webp');
}

/// Dart/iOS reused a connection the OS already closed (app backgrounded).
bool isStaleHttpClientError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('bad file descriptor') ||
      lower.contains('connection closed') ||
      lower.contains('connection reset by peer') ||
      lower.contains('broken pipe') ||
      lower.contains('software caused connection abort');
}
