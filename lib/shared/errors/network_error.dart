/// Detects transport-level failures without exposing raw exception text to users.
bool isNetworkTransportError(Object error) {
  final raw = error.toString().toLowerCase();
  return raw.contains('socketexception') ||
      raw.contains('handshakeexception') ||
      raw.contains('connection refused') ||
      raw.contains('connection reset') ||
      raw.contains('network is unreachable');
}
