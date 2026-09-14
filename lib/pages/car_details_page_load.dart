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
  Future<void> _loadCar() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cacheKey = 'cache_car_${widget.carId}';

      // Prefer network first so new uploads (images/videos) are not hidden behind stale cache.
      Map<String, dynamic>? loaded;
      _CarDetailLoadError? failure;
      try {
        loaded = await ApiService.getCarDetail(widget.carId);
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
        setState(() {
          car = _normalizeCarDetailMap(loaded!);
          loading = false;
          loadError = null;
        });
        _clampHeroMediaIndex();
        _precacheListingImages();
        unawaited(_loadFavoriteStatus());
        _loadSimilar();
        unawaited(sp.setString(cacheKey, json.encode(car)));
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
              if (mounted) {
                setState(() {
                  car = _normalizeCarDetailMap(Map<String, dynamic>.from(data));
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
              if (mounted) {
                setState(() {
                  car = _normalizeCarDetailMap(
                    Map<String, dynamic>.from(data.first),
                  );
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
