part of 'car_details_page.dart';

mixin _CarDetailsPageLoad on _CarDetailsPageLifecycle {
  Future<void> _loadCar() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cacheKey = 'cache_car_${widget.carId}';

      // Prefer network first so new uploads (images/videos) are not hidden behind stale cache.
      bool appliedFromNetwork = false;
      try {
        final loaded = await ApiService.getCarDetail(widget.carId);
        if (loaded != null && mounted) {
          setState(() {
            car = _normalizeCarDetailMap(loaded);
            loading = false;
          });
          _clampHeroMediaIndex();
          appliedFromNetwork = true;
        }
      } catch (e, st) {
        logNonFatal(e, st);
      }

      if (appliedFromNetwork && car != null) {
        _precacheListingImages();
        unawaited(_loadFavoriteStatus());
        _loadSimilarAndRelated();
        unawaited(sp.setString(cacheKey, json.encode(car)));
        _trackView();
        return;
      }

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
              });
              _clampHeroMediaIndex();
            }
            _precacheListingImages();
            unawaited(_loadFavoriteStatus());
            unawaited(_trackView());
          } else if (data is List && data.isNotEmpty) {
            if (mounted) {
              setState(() {
                car = _normalizeCarDetailMap(
                  Map<String, dynamic>.from(data.first),
                );
                loading = false;
              });
              _clampHeroMediaIndex();
            }
            _precacheListingImages();
            unawaited(_loadFavoriteStatus());
            unawaited(_trackView());
          }
        } catch (e, st) { logNonFatal(e, st); }
      }

      if (!mounted) return;
      setState(() {
        loading = false;
      });
    } catch (e, st) { logNonFatal(e, st); 
      if (mounted) {
        setState(() {
          loading = false;
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


  Future<void> _loadSimilarAndRelated() async {
    if (car == null) return;
    final String brand = (car!['brand'] ?? '').toString().trim();
    if (brand.isEmpty) return;
    if (!mounted) return;
    setState(() {
      loadingSimilar = true;
      loadingRelated = true;
    });
    try {
      final result = await loadCarDetailsRecommendations(
        car: car!,
        cacheCarId: widget.carId,
      );
      if (mounted) {
        setState(() {
          similarCars = result.similar;
          relatedCars = result.related;
        });
      }
    } catch (e) {
      appLog('Failed to load similar/related: $e');
    } finally {
      if (mounted) {
        setState(() {
          loadingSimilar = false;
          loadingRelated = false;
        });
      }
    }
  }
}
