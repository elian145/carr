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

mixin _CarDetailsPageLoad on _CarDetailsPageLifecycle, WidgetsBindingObserver {
  /// Auto-reconciliation fix: pauses the owner-media poll timer while
  /// backgrounded (no point burning battery/data reconciling a screen
  /// nobody can see) and resumes it -- with an immediate tick rather than
  /// waiting a full interval -- on return to the foreground, if there is
  /// still anything left to reconcile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_showProcessingMedia) {
          unawaited(_pollOwnerMediaOnce());
          _maybeScheduleOwnerMediaPoll();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _cancelOwnerMediaPoll();
    }
  }

  /// Optimistic-submission fix (task item #14): merges this device's own
  /// still-in-flight local Sell-submission media into a freshly-loaded
  /// listing map, for the OWNER only -- see
  /// `owner_pending_media_merge.dart` for the full contract/safety
  /// guarantees. A no-op (returns [loaded] unchanged) for every other
  /// viewer, and for the owner too once the background media pipeline has
  /// actually finished (the durable record it reads is removed then).
  ///
  /// Real-device acceptance fix ("video stuck in 'Processing media'
  /// forever even once attached"): [rawCarForOverlay], when provided, is
  /// the TRUE pre-[_normalizeCarDetailMap] server response -- every call
  /// site used to pass the already-normalized [loaded] for BOTH the
  /// merge/owner-check below AND the overlay build, but
  /// `_normalizeVideoPaths` (which [_normalizeCarDetailMap] applies)
  /// collapses each `videos[]` entry down to a bare url string,
  /// discarding its `client_media_id` field entirely. Images have no
  /// equivalent normalization step, so this silently affected ONLY
  /// videos: `OwnerMediaOverlay.build`'s exact-id matching always saw an
  /// empty `client_media_id` pool for videos, forcing every video onto
  /// the (correctly) more conservative legacy-positional-fallback path --
  /// confirmed stuck at `matched_by_id=false` on a real device despite
  /// the server genuinely returning a matching `client_media_id`. Falls
  /// back to [loaded] itself when omitted (the offline-cache-reload call
  /// sites below never persisted the raw shape to begin with, so there is
  /// nothing better to pass there; the legacy-positional fallback those
  /// already relied on previously is unaffected by this fix).
  Future<Map<String, dynamic>> _mergeOwnerPendingMedia(
    Map<String, dynamic> loaded, {
    Map<String, dynamic>? rawCarForOverlay,
  }) async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final owner = isListingOwner(loaded, auth.userId);
      final merged = await OwnerPendingMediaMerge.mergeIfOwner(
        loaded,
        isOwner: owner,
      );
      // Optimistic-local-media fix: build the per-item local<->remote
      // overlay from the RAW server response -- deliberately NOT
      // [merged]: `OwnerPendingMediaMerge._merge` has already appended
      // this device's own local fallback items into
      // `merged['images']`/`merged['videos']` (as plain local-path
      // strings/maps), and this overlay's own positional-pairing logic
      // needs to count ONLY genuine server-side remote items to know how
      // many local slots the server has actually caught up to -- feeding
      // it the already-merged list would double-count each local
      // fallback as if it were its own remote counterpart. The whole-
      // listing legacy signal is used when the overlay itself is empty
      // (non-owner / edit-mode / no active record) -- see
      // `_showProcessingMedia`'s doc comment in `car_details_page_media
      // .dart`. Plain field assignment here is intentional: every call
      // site wraps this method's result in its own `setState` right
      // after, which is what actually triggers the rebuild that picks
      // these up.
      _ownerMediaOverlay = await OwnerMediaOverlay.build(
        car: rawCarForOverlay ?? loaded,
        isOwner: owner,
      );
      // A freshly-built overlay has a brand-new `serverStillProcessing`
      // snapshot -- see `_ownerMediaRecordConfirmedGone`'s own doc
      // comment (car_details_page_fields.dart) for why this must be
      // trusted again from scratch rather than keeping any earlier
      // confirmation around.
      _ownerMediaRecordConfirmedGone = false;
      // Optimistic-local-media fix (Critical Issue 1 -- restart safety):
      // "if remote_display_ready was true previously and the remote URL
      // is unchanged, it is okay to restore that state on restart" (user's
      // explicit instruction). `_remoteDisplayReady` only ever lives in
      // THIS widget's memory otherwise, so without this it would forget
      // every already-confirmed item on every fresh page open/app
      // restart -- which would needlessly re-show the local fallback (and
      // briefly re-show "Processing media") for items already known-good.
      // Merge (never overwrite an in-session-confirmed `true` back to
      // unset) rather than replace, since a slot can already have been
      // confirmed earlier in THIS same session (e.g. a resumed load).
      if (owner && (_ownerMediaOverlay?.isEmpty ?? true) == false) {
        final carId = listingPrimaryId(loaded);
        if (carId.isNotEmpty) {
          final persistedReady =
              await OwnerOptimisticMediaCleanup.loadRemoteDisplayReadyMap(
            carId,
          );
          for (final entry in persistedReady.entries) {
            _remoteDisplayReady[entry.key] = true;
          }
        }
      }
      _legacyMediaProcessing = owner &&
          await OwnerPendingMediaMerge.isMediaProcessing(widget.carId);
      return merged;
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
        final merged = await _mergeOwnerPendingMedia(
          normalized,
          rawCarForOverlay: loaded,
        );
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
        _maybeScheduleOwnerMediaPoll();
        // Badge-stuck-until-swiped fix: probe every pending slot's
        // remote readiness in the background right away too, not only
        // on the NEXT poll tick -- covers the case where the server is
        // already fully done by the time this first load completes (see
        // `_backgroundProbeAllPendingSlots`'s own doc comment).
        _backgroundProbeAllPendingSlots();
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

  /// Auto-reconciliation fix: how often to re-fetch this listing while
  /// [_showProcessingMedia] is true. Deliberately NOT aggressive (every
  /// 2s, not sub-second) -- this is a background reconciliation of a
  /// normal `GET /api/cars/<id>` request, not a dedicated lightweight
  /// readiness-check endpoint.
  static const Duration _ownerMediaPollInterval = Duration(seconds: 2);

  /// Starts the periodic re-fetch timer described on
  /// [_ownerMediaPollTimer]'s own doc comment -- a no-op if one is
  /// already scheduled (no duplicate timers) or if there is nothing left
  /// to reconcile. Safe to call after every successful load/poll tick;
  /// it only ever creates a timer when [_showProcessingMedia] is
  /// genuinely still true.
  void _maybeScheduleOwnerMediaPoll() {
    if (!mounted || !_showProcessingMedia) {
      _cancelOwnerMediaPoll();
      return;
    }
    if (_ownerMediaPollTimer != null) return;
    _ownerMediaPollTimer = Timer.periodic(_ownerMediaPollInterval, (_) {
      unawaited(_pollOwnerMediaOnce());
    });
  }

  /// Stops and clears [_ownerMediaPollTimer] -- called once reconciliation
  /// is genuinely done ([_showProcessingMedia] false), on `dispose()`, and
  /// while the app is backgrounded (see
  /// `_CarDetailsPageLifecycle.didChangeAppLifecycleState`).
  void _cancelOwnerMediaPoll() {
    _ownerMediaPollTimer?.cancel();
    _ownerMediaPollTimer = null;
  }

  /// One lightweight reconciliation tick: re-fetches this listing and
  /// re-merges/re-tags it EXACTLY like [_loadCar]'s main success path,
  /// but skips [_loadCar]'s one-time-per-visit side effects (offline
  /// cache write, image precache, favorite status, similar listings,
  /// view tracking) -- those must never repeat every 2 seconds. Silently
  /// skips a tick on any error (network hiccup, cancellation) and simply
  /// retries on the next one; never surfaces a poll failure to the owner.
  Future<void> _pollOwnerMediaOnce() async {
    // No overlapping requests: a slow response still in flight when the
    // next tick fires is skipped rather than stacked.
    if (_ownerMediaPollInFlight) return;
    if (!mounted || !_showProcessingMedia) {
      _cancelOwnerMediaPoll();
      return;
    }
    _ownerMediaPollInFlight = true;
    try {
      final loaded = await ApiService.getCarDetail(widget.carId);
      if (!mounted) return;
      final normalized = _normalizeCarDetailMap(loaded);
      final merged = await _mergeOwnerPendingMedia(
        normalized,
        rawCarForOverlay: loaded,
      );
      if (!mounted) return;
      setState(() => car = merged);
      _clampHeroMediaIndex();
      // Badge-stuck-until-swiped fix: see
      // `_backgroundProbeAllPendingSlots`'s own doc comment -- this is
      // what lets the badge clear itself purely from polling, without
      // requiring the owner to ever swipe to an off-screen slide.
      _backgroundProbeAllPendingSlots();
    } catch (e, st) {
      logNonFatal(e, st, 'CarDetailsPage._pollOwnerMediaOnce');
    } finally {
      _ownerMediaPollInFlight = false;
      // Stop as soon as reconciliation is genuinely done, instead of
      // waiting for one more wasted tick to notice.
      if (mounted && !_showProcessingMedia) _cancelOwnerMediaPoll();
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
