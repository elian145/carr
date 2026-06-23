import '../shared/listings/listing_share_urls.dart';

/// Resolved in-app route for an incoming deep link URI.
class DeepLinkTarget {
  const DeepLinkTarget(this.route, this.arguments);

  final String route;
  final Map<String, dynamic> arguments;
}

/// Returns a navigation target when [uri] is recognized, otherwise null.
DeepLinkTarget? resolveDeepLinkTarget(Uri uri) {
  final path = uri.path;
  final token = uri.queryParameters['token']?.trim();
  if (path.endsWith('reset-password') && token != null && token.isNotEmpty) {
    return DeepLinkTarget(
      '/reset-password',
      <String, String>{'token': token},
    );
  }
  if (path.endsWith('verify-email') && token != null && token.isNotEmpty) {
    return DeepLinkTarget(
      '/verify-email',
      <String, dynamic>{'token': token},
    );
  }
  if (path.endsWith('confirm-signup') && token != null && token.isNotEmpty) {
    return DeepLinkTarget(
      '/verify-email',
      <String, dynamic>{'token': token, 'mode': 'signup'},
    );
  }

  final httpsListingId = listingIdFromSharedHttpsUri(uri);
  if (httpsListingId != null) {
    return DeepLinkTarget(
      '/car_detail',
      <String, dynamic>{'carId': httpsListingId},
    );
  }

  if (uri.scheme == 'carzo' && uri.host == 'listing') {
    final carId = (uri.queryParameters['id'] ??
            uri.queryParameters['carId'] ??
            '')
        .trim();
    if (carId.isEmpty) return null;
    return DeepLinkTarget(
      '/car_detail',
      <String, dynamic>{'carId': carId},
    );
  }

  return null;
}
