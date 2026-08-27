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
  if (isListingImageNotFoundError(error)) return true;
  if (isUnparseableImageUrlError(error)) return true;
  if (isStaleHttpClientError(error)) return true;
  return false;
}

bool _isListingImagePath(String lower) {
  return lower.contains('/static/uploads/') ||
      lower.contains('car_photos') ||
      lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.png') ||
      lower.contains('.webp');
}

/// HTTP 403/410 for listing media — retrying cannot help.
///
/// 404 is [isListingImageNotFoundError]: just-uploaded R2/static files can
/// 404 for a few seconds, so image widgets still retry a bounded number of
/// times.
bool isPermanentHttpImageError(Object error) {
  final lower = error.toString().toLowerCase();
  final isGoneStatus =
      lower.contains('statuscode: 403') ||
      lower.contains('statuscode: 410') ||
      lower.contains('invalid statuscode: 403') ||
      lower.contains('invalid statuscode: 410');
  if (!isGoneStatus) return false;
  return _isListingImagePath(lower);
}

/// HTTP 404 for listing media. Retry briefly (object may not be public yet).
bool isListingImageNotFoundError(Object error) {
  final lower = error.toString().toLowerCase();
  final is404 =
      lower.contains('statuscode: 404') ||
      lower.contains('invalid statuscode: 404');
  if (!is404) return false;
  return _isListingImagePath(lower);
}

/// [Uri.parse] of a local path or `{source: /var/mobile/...}` map leak.
bool isUnparseableImageUrlError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('scheme not starting with alphabetic') ||
      (lower.contains('formatexception') && lower.contains('illegal scheme'));
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

/// Timeouts, DNS, and dropped sockets — worth retrying an upload once or twice.
bool isTransientNetworkError(Object error) {
  if (isStaleHttpClientError(error)) return true;
  final lower = error.toString().toLowerCase();
  return lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('no address associated') ||
      lower.contains('connection abort') ||
      lower.contains('connection reset') ||
      lower.contains('socketexception');
}
