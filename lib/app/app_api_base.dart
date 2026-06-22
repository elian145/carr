import '../services/config.dart';

String getApiBase() {
  // Must match [effectiveApiBase] so listing fetches and [ApiService] hit the same host.
  return effectiveApiBase();
}
