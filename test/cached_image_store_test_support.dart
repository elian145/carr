import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';

/// Pre-creates `CachedNetworkImage`'s process-wide `DefaultCacheManager`
/// OUTSIDE any test body, so its disk-store bootstrap can never be charged to
/// whichever widget test happens to mount the first `CachedNetworkImage`.
///
/// Why this exists (Codemagic macOS-only failures):
/// `flutter_cache_manager` picks its on-disk info store per OS. On Android,
/// iOS **and macOS** it uses a sqflite database; on Windows/Linux it uses a
/// JSON file. `flutter test` has no sqflite platform plugin, so on macOS the
/// store's `open()` future fails with a `MissingPluginException` -- while on a
/// Windows/Linux dev box the very same code path works, which is why the
/// failure never reproduced locally.
///
/// `DefaultCacheManager` is a lazy singleton: it is constructed (and
/// `repo.open()` kicked off) the first time any `CachedNetworkImage` loads.
/// That `open()` future has no listener yet, so its failure surfaces as an
/// UNCAUGHT async error in the zone of the first test that built an image --
/// failing that test ("The following MissingPluginException was thrown
/// running a test") even though every assertion in it is about widget
/// configuration, not about disk caching. It is a race against the test's
/// remaining runtime, hence "flaky" for short tests and deterministic for
/// long ones.
///
/// Constructing the singleton here, inside [runZonedGuarded], routes that
/// environment-only error to a no-op handler instead of the test zone. Later
/// image loads still observe the (platform-dependent) store state through the
/// normal image error path, exactly as before; nothing is mocked or weakened.
///
/// Call this from `setUpAll` AFTER the path_provider mock is installed.
void primeCachedImageStoreForTests() {
  runZonedGuarded<void>(
    () {
      // Same getter CachedNetworkImage uses; first access builds the singleton.
      CachedNetworkImageProvider.defaultCacheManager;
    },
    (Object error, StackTrace stack) {
      // Intentionally ignored: the store cannot open under `flutter test`
      // on platforms whose cache info repo needs a native plugin (macOS).
    },
  );
}
