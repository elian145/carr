import 'package:http/http.dart' as http;

import '../device_id_service.dart';

/// F-12: the ONE place that adds `X-Device-Id` to outgoing API requests.
///
/// `ApiService` hands every request helper (JSON GET/POST/PUT/PATCH/DELETE,
/// multipart uploads, token refresh, login / phone start / phone verify /
/// send-verification / forgot- and reset-password, ...) one shared client via
/// `ApiService._httpClient`; wrapping that client covers all of them, so no
/// individual call site can forget the header.
///
/// Rules:
///  * only requests to the first-party API host get the header ([isFirstParty]);
///    third-party URLs (CDNs, storage, analytics) never learn the id;
///  * an explicit `X-Device-Id` already on the request is left untouched;
///  * the id is optional for the server: when it is unavailable nothing is
///    added and the request is sent unchanged (never blocked, never failed);
///  * the value is client-asserted and only used by the backend as an extra
///    rate-limit key, never as authentication (see [DeviceIdService]).
class DeviceIdHttpClient extends http.BaseClient {
  DeviceIdHttpClient(
    this._inner, {
    required this.service,
    required this.isFirstParty,
  });

  static const String headerName = 'X-Device-Id';

  final http.Client _inner;
  final DeviceIdService service;
  final bool Function(Uri url) isFirstParty;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (isFirstParty(request.url) && !_hasDeviceHeader(request)) {
      String? id;
      try {
        id = service.cachedId ?? await service.getDeviceId();
      } catch (_) {
        id = null; // never fail a request because of the device id
      }
      if (id != null && id.isNotEmpty) {
        request.headers[headerName] = id;
      }
    }
    return _inner.send(request);
  }

  static bool _hasDeviceHeader(http.BaseRequest request) {
    for (final name in request.headers.keys) {
      if (name.toLowerCase() == 'x-device-id') return true;
    }
    return false;
  }

  /// The wrapped client is owned (and recycled/closed) by `ApiService`.
  @override
  void close() {}
}
