part of 'car_details_page.dart';

/// Coarse reason a car-detail load attempt failed to populate `car`, once
/// any legitimate offline-cache fallback has also been ruled out. Drives
/// which failure UI `_CarDetailsPageBuild` renders instead of the generic
/// "Car not found" text for every failure (F-01, root cause of B-02).
enum _CarDetailLoadErrorKind {
  /// Server confirmed the listing does not exist / is not visible (404).
  /// Never falls back to a stale cached listing.
  notFound,

  /// A 401 survived `ApiService.getCarDetail`'s existing refresh-then-retry
  /// attempt. Defense in depth: the current `GET /api/cars/<id>` route does
  /// not normally emit 401 (optional-JWT errors are swallowed server-side),
  /// but this keeps the UI honest if that ever changes.
  authRequired,

  /// Any other non-404/401 `ApiException` — 5xx, 429, or other status.
  server,

  /// Timeout, transport failure (e.g. `SocketException`), or a malformed /
  /// unexpectedly-shaped successful response.
  network,
}

/// Immutable classification produced by [_CarDetailsPageLoad._loadCar].
class _CarDetailLoadError {
  const _CarDetailLoadError(this.kind, {this.statusCode});

  final _CarDetailLoadErrorKind kind;

  /// Only set for [_CarDetailLoadErrorKind.server].
  final int? statusCode;
}

mixin _CarDetailsPageLoad on _CarDetailsPageLifecycle {
  /// Optimistic-submission fix (task item #14): merges this device's own
  /// still-in-flight local Sell-submission media into a freshly-loaded
  /// listing map, for the OWNER only -- see
  /// `owner_pending_media_merge.dart` for the full contract/safety
  /// guarantees. A no-op (returns [loaded] unchanged) for every other
  /// viewer, and for the owner too once the background media pipeline has
  /// actually finished (the durable record it reads is removed then).
  Future<Map<String, dynamic>> _mergeOwnerPendingMedia(
    Map<String, dynamic> loaded,
  ) async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final owner = isListingOwner(loaded, auth.userId);
      return await OwnerPendingMediaMerge.mergeIfOwner(
        loaded,
        isOwner: owner,
      );
    } catch (e, st) {
      logNonFatal(e, st, 'CarDetailsPage._mergeOwnerPendingMedia');
      return loaded;
    }
  }

  Future<void> _loadCar() async {
    // F-06: abort any still-in-flight load from a previous call (e.g. an
    // earlier retry) before starting a new one, and genuinely cancel this
    // one on `dispose()`.
    _loadCarCancelToken?.cancel();
    final cancelToken = ApiCancelToken();
    _loadCarCancelToken = cancelToken;
    try {
      final sp = await SharedPreferences.getInstance();
      final cacheKey = 'cache_car_${widget.carId}';

      // Prefer network first so new uploads (images/videos) are not hidden behind stale cache.
      Map<String, dynamic>? loaded;
      _CarDetailLoadError? failure;
      try {
        loaded = await ApiService.getCarDetail(
          widget.carId,
          cancelToken: cancelToken,
        );
      } on ApiCancelledException {
        // Intentional cancellation (e.g. the user navigated away before
        // this load finished) — not a network/server failure. Silently
        // stop: no setState, no loadError, no non-fatal log, no cache
        // write, and no retry. Distinguishable from every real failure by
        // exception type (see ApiCancelledException's own doc comment).
        return;
      } on ApiException catch (e, st) {
        if (e.statusCode == 404) {
          // Definitive "not found" — expected/benign (deleted or never
          // existed), not worth non-fatal logging.
          failure = const _CarDetailLoadError(_CarDetailLoadErrorKind.notFound);
        } else if (e.statusCode == 401) {
          failure = const _CarDetailLoadError(
            _CarDetailLoadErrorKind.authRequired,
          );
          logNonFatal(e, st, 'CarDetailsPage._loadCar');
        } else {
          failure = _CarDetailLoadError(
            _CarDetailLoadErrorKind.server,
            statusCode: e.statusCode,
          );
          logNonFatal(e, st, 'CarDetailsPage._loadCar');
        }
      } catch (e, st) {
        // TimeoutException, transport failures (e.g. SocketException), and
        // malformed/unexpectedly-shaped 200 bodies all land here — never
        // treated as "not found" (F-01).
        failure = const _CarDetailLoadError(_CarDetailLoadErrorKind.network);
        logNonFatal(e, st, 'CarDetailsPage._loadCar');
      }

      if (loaded != null && mounted) {
        final normalized = _normalizeCarDetailMap(loaded);
        // Cache the SERVER truth (never the owner-pending-media-merged
        // version below) -- a locally-merged local file path would be
        // meaningless (and could point at a file that no longer exists)
        // if this cache is later read back as an offline fallback.
        unawaited(sp.setString(cacheKey, json.encode(normalized)));
        final merged = await _mergeOwnerPendingMedia(normalized);
        if (!mounted) return;
        setState(() {
          car = merged;
          loading = false;
          loadError = null;
        });
        _clampHeroMediaIndex();
        _precacheListingImages();
        unawaited(_loadFavoriteStatus());
        _loadSimilar();
        _trackView();
        return;
      }

      // Confirmed absence: never fall back to a stale cached listing.
      if (failure?.kind == _CarDetailLoadErrorKind.notFound) {
        if (!mounted) return;
        setState(() {
          car = null;
          loading = false;
          loadError = failure;
        });
        return;
      }

      // Transient/server/network failures preserve the existing offline
      // cache fallback exactly as before. An unresolved auth failure does
      // not use it — there is nothing sensible to show behind a login wall.
      if (failure?.kind != _CarDetailLoadErrorKind.authRequired) {
        // Offline / error: fall back to cached listing
        final cached = sp.getString(cacheKey);
        if (cached != null && cached.isNotEmpty) {
          try {
            final data = json.decode(cached);
            if (data is Map) {
              final normalized = _normalizeCarDetailMap(
                Map<String, dynamic>.from(data),
              );
              final merged = await _mergeOwnerPendingMedia(normalized);
              if (mounted) {
                setState(() {
                  car = merged;
                  loading = false;
                  loadError = null;
                });
                _clampHeroMediaIndex();
              }
              _precacheListingImages();
              unawaited(_loadFavoriteStatus());
              unawaited(_trackView());
              return;
            } else if (data is List && data.isNotEmpty) {
              final normalized = _normalizeCarDetailMap(
                Map<String, dynamic>.from(data.first),
              );
              final merged = await _mergeOwnerPendingMedia(normalized);
              if (mounted) {
                setState(() {
                  car = merged;
                  loading = false;
                  loadError = null;
                });
                _clampHeroMediaIndex();
              }
              _precacheListingImages();
              unawaited(_loadFavoriteStatus());
              unawaited(_trackView());
              return;
            }
          } catch (e, st) { logNonFatal(e, st); }
        }
      }

      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = failure ??
            const _CarDetailLoadError(_CarDetailLoadErrorKind.network);
      });
    } catch (e, st) {
      logNonFatal(e, st, 'CarDetailsPage._loadCar');
      if (mounted) {
        setState(() {
          loading = false;
          loadError ??= const _CarDetailLoadError(_CarDetailLoadErrorKind.network);
        });
      }
    }
  }

  Future<void> _trackView() async {
    try {
      final id = (car != null && listingPrimaryId(car!).isNotEmpty)
          ? listingPrimaryId(car!)
          : widget.carId.toString();
      final snap = car != null
          ? Map<String, dynamic>.from(car!)
          : null;
      await AnalyticsService.trackView(id, listingSnapshot: snap);
    } catch (e) {
      appLog('Failed to track view: $e');
    }
  }


  Future<void> _loadSimilar() async {
    if (car == null) return;
    final String brand = (car!['brand'] ?? '').toString().trim();
    if (brand.isEmpty) return;
    if (!mounted) return;
    setState(() {
      loadingSimilar = true;
    });
    try {
      final result = await loadCarDetailsRecommendations(
        car: car!,
        cacheCarId: widget.carId,
      );
      if (mounted) {
        setState(() {
          similarCars = result.similar;
        });
      }
    } catch (e) {
      appLog('Failed to load similar: $e');
    } finally {
      if (mounted) {
        setState(() {
          loadingSimilar = false;
        });
      }
    }
  }
}
