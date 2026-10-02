import 'package:flutter/material.dart';

import 'listing_hero_image.dart';
import 'listing_network_image.dart';

/// Test-only interception point for [_OwnerFallbackHeroImageState]'s
/// remote-loadability probe -- when non-null, a test supplies
/// `Future<bool> Function(String url)` directly (`true` = "treat as
/// successfully decoded", `false` = "treat as failed/still pending") in
/// place of the real `ImageStream`-based probe, so tests can deterministically
/// exercise the local->remote swap (and remote-failure-keeps-local) states
/// without needing genuine network image bytes/a real HTTP round trip.
/// Mirrors this repo's existing `@visibleForTesting` override convention
/// (e.g. `debugLogNonFatalOverride` in `app_log.dart`). Always `null` in
/// production. Tests MUST reset this to `null` in `tearDown`.
@visibleForTesting
Future<bool> Function(String url)? debugOwnerFallbackHeroRemoteProbeOverride;

/// Optimistic-local-media fix: shows a listing owner's own already-durable
/// LOCAL photo immediately, and swaps in-place to the server's REMOTE
/// counterpart only once that remote image has genuinely finished
/// decoding successfully -- never a blank/spinner tile just because a
/// remote URL now exists, and never a permanent stale local image once the
/// remote copy is confirmed good.
///
/// STATE MACHINE (see the task's own A-E contract):
///   - [remoteUrl] null -> always render [localUrl] (STATE A/B: local
///     only / server still processing, no URL yet).
///   - [remoteUrl] non-null, not yet confirmed loadable -> keep rendering
///     [localUrl] (STATE C).
///   - [remoteUrl] confirmed successfully decoded -> render it instead,
///     atomically (STATE D) -- [onRemoteDisplayReady] fires exactly once
///     per distinct [remoteUrl] that reaches this state.
///   - [remoteUrl] fails to decode -> keep rendering [localUrl] (STATE E);
///     [ListingHeroImage] itself already retries a genuine remote decode
///     failure with backoff (see its own `_scheduleRetry`), so this widget
///     does not need a separate retry loop -- it just re-probes whenever
///     [didUpdateWidget] sees [remoteUrl] change, or once per build via
///     its own internal backoff below for a same-URL retry.
///   - [localUrl] empty/missing (STATE per requirement 9: an unexpectedly
///     missing local file after a restart) -> falls back to rendering
///     [remoteUrl] directly via the normal (spinner-while-loading)
///     [ListingHeroImage] path -- there is no local image to protect
///     visually in that case.
class OwnerFallbackHeroImage extends StatefulWidget {
  const OwnerFallbackHeroImage({
    super.key,
    required this.localUrl,
    required this.remoteUrl,
    this.detectionSource,
    this.onRemoteDisplayReady,
  });

  /// Durable local file path/URL, or empty when unavailable.
  final String localUrl;

  /// The server's current best-guess remote counterpart, or `null` while
  /// the server does not yet have one for this slot.
  final String? remoteUrl;
  final dynamic detectionSource;

  /// Fired exactly once per distinct [remoteUrl] the moment it has
  /// genuinely finished decoding and this widget has swapped to it.
  final VoidCallback? onRemoteDisplayReady;

  @override
  State<OwnerFallbackHeroImage> createState() =>
      _OwnerFallbackHeroImageState();
}

class _OwnerFallbackHeroImageState extends State<OwnerFallbackHeroImage> {
  ImageStream? _probeStream;
  ImageStreamListener? _probeListener;
  String? _confirmedRemoteUrl;
  String? _probingUrl;

  bool get _hasLocal => widget.localUrl.trim().isNotEmpty;
  bool get _hasRemote => (widget.remoteUrl ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _maybeStartProbe();
  }

  @override
  void didUpdateWidget(covariant OwnerFallbackHeroImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteUrl != widget.remoteUrl) {
      // A different (or newly-appeared/disappeared) remote URL to
      // reconcile -- any previous confirmation no longer applies.
      _confirmedRemoteUrl = null;
      _maybeStartProbe();
    }
  }

  void _maybeStartProbe() {
    final url = widget.remoteUrl;
    if (url == null || url.trim().isEmpty) {
      _clearProbe();
      return;
    }
    if (_probingUrl == url || _confirmedRemoteUrl == url) return;
    _clearProbe();
    _probingUrl = url;
    // Local-only Phase-A/no-plate no-op case: if there is no local image
    // at all (STATE per requirement 9), there is nothing to protect --
    // render remote directly via the normal ListingHeroImage path
    // (spinner-while-loading is expected/acceptable there) instead of
    // spending an extra probe resolve.
    if (!_hasLocal) {
      // Plain assignment (no `setState`): this runs synchronously from
      // either `initState` (whose very next step is the FIRST build,
      // which will already see this field) or `didUpdateWidget` (which
      // Flutter calls as part of an update cycle that is already about
      // to call `build` again) -- wrapping in `setState` here would
      // throw ("setState() called before initState() completed") for
      // the `initState` case.
      _confirmedRemoteUrl = url;
      return;
    }

    final override = debugOwnerFallbackHeroRemoteProbeOverride;
    if (override != null) {
      override(url).then((ok) {
        if (!mounted || _probingUrl != url) return;
        if (ok) {
          setState(() => _confirmedRemoteUrl = url);
          widget.onRemoteDisplayReady?.call();
        }
        // else: keep local (STATE E) -- no state change.
      });
      return;
    }

    final provider = listingCachedNetworkImageProvider(url);
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        // Real-device acceptance fix: `ImageStreamListener.onImage` can
        // fire SYNCHRONOUSLY (e.g. the image is already cached) from
        // within `stream.addListener(...)` above, which itself runs from
        // `_maybeStartProbe` -- called from `initState`/`didUpdateWidget`,
        // i.e. DURING this widget's own build pass. Calling `setState()`
        // synchronously in that case throws ("setState() or
        // markNeedsBuild() called during build"), and critically that
        // throw happens BEFORE `widget.onRemoteDisplayReady?.call()`
        // below ever runs -- silently skipping the one call responsible
        // for persisting "this item is remote-display-ready", which is
        // exactly why the "Processing media" badge could get stuck
        // forever even once every item visually looked confirmed.
        // Deferring to the next frame (mirroring the same established
        // pattern in `listing_hero_image.dart`'s own `onImage`/`onError`
        // handlers) makes this always safe, synchronous-cache-hit or not.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_probingUrl != url) return; // superseded by a newer remoteUrl
          setState(() => _confirmedRemoteUrl = url);
          widget.onRemoteDisplayReady?.call();
        });
      },
      onError: (error, stack) {
        // Keep rendering local (STATE E) -- never surface this as a
        // visible error; a later rebuild with a corrected/retried
        // remoteUrl (or this same one, next load) will probe again.
      },
    );
    stream.addListener(listener);
    _probeStream = stream;
    _probeListener = listener;
  }

  void _clearProbe() {
    final stream = _probeStream;
    final listener = _probeListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _probeStream = null;
    _probeListener = null;
    _probingUrl = null;
  }

  @override
  void dispose() {
    _clearProbe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showRemote = _hasRemote && _confirmedRemoteUrl == widget.remoteUrl;
    final effectiveUrl = showRemote ? widget.remoteUrl! : widget.localUrl;
    // Keyed by the URL actually being rendered: once the confirmed remote
    // URL differs from whatever was rendered before, this is a genuinely
    // new source/new key (never the SAME `ListingHeroImage` element
    // silently mutating its `url` under an unrelated key), matching this
    // task's own "new source, new key" contract for the swap.
    return ListingHeroImage(
      key: ValueKey('owner_fallback|$effectiveUrl'),
      url: effectiveUrl,
      detectionSource: widget.detectionSource,
    );
  }
}
