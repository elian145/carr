part of 'home_flow.dart';

mixin _HomePageFetch on _HomePageFields {
  void _persistCurrentHomeOffsetNow() {
    try {
      if (_homeScrollController.hasClients) {
        final pos = _homeScrollController.position;
        final y = pos.pixels.clamp(pos.minScrollExtent, pos.maxScrollExtent);
        _lastHomeScrollPixels = y;
        _pendingHomeScrollRestore = y;
        _HomeFeedScrollPersistence.savePixels(y);
        return;
      }
    } catch (e, st) { logNonFatal(e, st); }
    _pendingHomeScrollRestore = _lastHomeScrollPixels;
    _HomeFeedScrollPersistence.savePixels(_lastHomeScrollPixels);
  }

  void _primePendingHomeScrollRestoreFromPersistence() {
    final y = _HomeFeedScrollPersistence.initialOffset;
    if (y > 0) _pendingHomeScrollRestore = y;
  }

  Future<void> _nextLayoutFrame() async {
    final c = Completer<void>();
    // Force a frame so awaiting this helper never depends on user input.
    SchedulerBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  void _scheduleHomeScrollRestoreAfterListReady() {
    final target = _pendingHomeScrollRestore;
    if (target == null || target <= 0) return;

    final gen = ++_homeScrollRestoreScheduleGen;
    // Ensure a frame is produced even when nothing else is animating.
    SchedulerBinding.instance.scheduleFrame();
    unawaited(_restoreHomeScrollWork(gen, target));
  }

  /// Loads extra pages without waiting on scroll physics, then jumps once — faster than
  /// nudging scroll each frame to trigger [_loadMore].
  Future<void> _restoreHomeScrollWork(int gen, double target) async {
    const slack = 12.0;
    const maxPrefetchPages = 40;

    for (var i = 0; i < 240 && mounted; i++) {
        if (gen != _homeScrollRestoreScheduleGen) return;
        await _nextLayoutFrame();
        if (!isLoading &&
            _homeScrollController.hasClients &&
            _homeScrollController.position.hasContentDimensions) {
          break;
        }
      }
      if (!mounted || gen != _homeScrollRestoreScheduleGen) return;

      for (var p = 0; p < maxPrefetchPages && mounted; p++) {
        if (gen != _homeScrollRestoreScheduleGen) return;
        if (!_homeScrollController.hasClients) return;
        final pos = _homeScrollController.position;
        if (!pos.hasContentDimensions) {
          await _nextLayoutFrame();
          continue;
        }
        if (pos.maxScrollExtent >= target - slack) break;
        if (!_hasNext) break;
        await _loadMore();
        await _nextLayoutFrame();
      }

      if (!mounted || gen != _homeScrollRestoreScheduleGen) return;
      await _nextLayoutFrame();
      if (!mounted || gen != _homeScrollRestoreScheduleGen) return;
      if (!_homeScrollController.hasClients) {
        SchedulerBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || gen != _homeScrollRestoreScheduleGen) return;
          _scheduleHomeScrollRestoreAfterListReady();
        });
        return;
      }
      final pos = _homeScrollController.position;
      if (!pos.hasContentDimensions) {
        SchedulerBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || gen != _homeScrollRestoreScheduleGen) return;
          _scheduleHomeScrollRestoreAfterListReady();
        });
        return;
      }
      final desired = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((pos.pixels - desired).abs() > 0.5) {
        _homeScrollController.jumpTo(desired);
      }
      // Do not clear pending target until we actually reach it (or data loading
      // has fully settled and no further growth is possible).
      final reachedTarget = (desired - target).abs() <= slack;
      final settling =
          isLoading || _isLoadingMore || (_hasNext && pos.maxScrollExtent < target - slack);
      if (!reachedTarget && settling) {
        SchedulerBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || gen != _homeScrollRestoreScheduleGen) return;
          _scheduleHomeScrollRestoreAfterListReady();
        });
        return;
      }
      _pendingHomeScrollRestore = null;
  }

  Future<void> _loadBodyTypesFromAssets() async {
    try {
      final String manifestJson = await services.rootBundle.loadString(
        'AssetManifest.json',
      );
      final Map<String, dynamic> manifestMap = json.decode(manifestJson);
      final Iterable<String> allAssets = manifestMap.keys.cast<String>();

      // Accept both SVG (clean) and PNG variants from both folders
      final List<String> btAssets = allAssets
          .where(
            (p) =>
                (p.startsWith('assets/body_types_clean/') &&
                    (p.endsWith('.svg') || p.endsWith('.png'))) ||
                (p.startsWith('assets/body_types_png/') && p.endsWith('.png')),
          )
          .toList();

      // Build normalized label -> canonical svg path map
      final Map<String, String> labelToSvg = {};
      for (final String path in btAssets) {
        // Extract base filename without extension
        final String fileName = path.split('/').last; // e.g., sedan.svg
        final String base = fileName
            .replaceAll('.svg', '')
            .replaceAll('.png', '');
        if (base.toLowerCase() == 'default') {
          continue; // skip default placeholder
        }

        // Build a user-friendly label (title case, even if file uses underscores)
        final String label = base
            .replaceAll('_', ' ')
            .split(' ')
            .map(
              (w) => w.isEmpty
                  ? w
                  : (w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '')),
            )
            .join(' ');

        // Prefer clean SVG if available for same label, otherwise use PNG
        if (!labelToSvg.containsKey(label)) {
          labelToSvg[label] = path;
        } else {
          final String existing = labelToSvg[label]!;
          final bool existingIsSvg = existing.toLowerCase().endsWith('.svg');
          final bool incomingIsSvg = path.toLowerCase().endsWith('.svg');
          if (!existingIsSvg && incomingIsSvg) {
            labelToSvg[label] = path;
          }
        }
      }

      if (mounted) {
        setState(() {
          final List<String> labels = labelToSvg.keys.toList()..sort();
          globalBodyTypes = ['Any', ...labels];
          // Keep bodyTypes as sell-page list so More Filters options stay aligned
          globalBodyTypeAssetMap = labelToSvg;
        });
      }
    } catch (e, st) { logNonFatal(e, st); 
      // If anything fails, keep the existing static fallback already present in code
    }
  }
  Future<void> fetchCars({
    bool bypassCache = false,
    bool isRetry = false,
  }) async {
    _debugLog(
      '[home-feed] fetchCars called with bypassCache: $bypassCache, isRetry: $isRetry',
    );
    // Analytics tracking for search fetch
    // Only show full-screen loading when there is no feed yet. If we already have
    // listings (e.g. memory rehydrate after tab switch), isLoading would replace the
    // grid with SliverFillRemaining, collapse scroll extent, and the scroll listener
    // would persist a tiny clamped offset — wiping the user's deep scroll position.
    if (mounted) {
      setState(() {
        if (cars.isEmpty) {
          isLoading = true;
        }
        loadErrorMessage = null;
      });
    }
    Map<String, String> filters = _buildFilters();
    // Reset pagination
    _page = 1;
    _hasNext = true;
    filters['page'] = _page.toString();
    filters['per_page'] = '20';

    String query = Uri(queryParameters: filters).query;
    final url = Uri.parse(
      '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
    );

    // Debug: Print the URL being called
    _debugLog('[home-feed] Fetching cars from: $url');
    _debugLog('[home-feed] Applied filters: $filters');
    _debugLog('[home-feed] Sort parameter: ${filters['sort_by']}');

    // Offline-first cache (skip cache if bypassCache is true)
    final sp = await SharedPreferences.getInstance();
    final cacheKey = 'cache_home_${query.hashCode}';
    String? cached;
    if (!bypassCache) {
      // Use cached data to improve reliability and reduce API dependency
      cached = sp.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        _debugLog('[home-feed] Using cached data for key: $cacheKey');
        try {
          final decoded = json.decode(cached);
          final List<Map<String, dynamic>> parsed =
              listingMapsFromApiResponse(decoded);
          if (mounted) {
            setState(() {
              cars = _applyDamagedPartsExactFilter(parsed);
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
              if (parsed.isNotEmpty) _autoFetchedForEmptyWithSort = false;
            });
            _scheduleHomeScrollRestoreAfterListReady();
          }
        } catch (e, st) { logNonFatal(e, st); }
      }
    } else {
      _debugLog('[home-feed] Bypassing cache for key: $cacheKey');
    }

    try {
      // Use longer timeout for sorting requests and add connection headers
      final timeout = filters.containsKey('sort_by')
          ? Duration(seconds: 30)
          : Duration(seconds: 15);
      final response = await ApiService.getCarsRaw(
        filters,
        timeout: timeout,
        extraHeaders: {
              'Connection': 'keep-alive',
              'Accept': 'application/json',
              'User-Agent': 'CarNet-Mobile/1.0',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
      );

      _debugLog('[home-feed] Response status: ${response.statusCode}');
      _debugLog('[home-feed] Response body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map) {
          try {
            final pg = (decoded['pagination'] as Map?);
            if (pg != null && pg['has_next'] is bool) {
              _hasNext = pg['has_next'] as bool;
            }
          } catch (e, st) { logNonFatal(e, st); }
        }
        final List<Map<String, dynamic>> parsed =
            listingMapsFromApiResponse(decoded);

        _debugLog('[home-feed] Parsed ${parsed.length} cars from response');

        if (mounted) {
          setState(() {
            cars = _applyDamagedPartsExactFilter(parsed);
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage =
                null; // Clear any previous error message on success
            if (parsed.isNotEmpty) _autoFetchedForEmptyWithSort = false;
          });
          _HomePageFields._homeFeedCache = copyListingMapList(cars);
          _HomePageFields._homeFeedCachePage = _page;
          _HomePageFields._homeFeedCacheHasNext = _hasNext;
        }
        // Save fresh cache
        unawaited(sp.setString(cacheKey, response.body));
        _debugLog('[home-feed] Found ${parsed.length} cars with applied filters');
        _page = 2; // next page to request
        // Reset retry count on success
        _fetchRetryCount = 0;
      } else {
        _debugLog('[home-feed] Server error: ${response.statusCode}');
        _debugLog('[home-feed] Response body: ${response.body}');
        await _handleFetchError(
          bypassCache,
          cached,
          HomeFeedErrors.server(response.statusCode),
          isRetry: isRetry,
        );
      }
    } catch (e) {
      _debugLog('[home-feed] Network error: $e');
      await _handleFetchError(
        bypassCache,
        cached,
        HomeFeedErrors.network,
        isRetry: isRetry,
      );
    }
    if (mounted) {
      _scheduleHomeScrollRestoreAfterListReady();
    }
  }

  Future<void> _handleFetchError(
    bool bypassCache,
    String? cached,
    String errorMessage, {
    bool isRetry = false,
  }) async {
    // Don't show error immediately - try fallback strategies first
    _debugLog('[home-feed] Handling fetch error: $errorMessage, isRetry: $isRetry');

    // First, attempt the alternative endpoint /api/cars (server returns { cars: [...], pagination: {...} })
    try {
      final ok = await _fetchFromApiCars(includeSort: true);
      if (ok) return; // Success via /api/cars; stop handling error
    } catch (e, st) { logNonFatal(e, st); }

    // If sorting failed and we have a sort parameter, try without sorting first
    if (selectedSortBy != null && selectedSortBy!.isNotEmpty && !isRetry) {
      _debugLog('[home-feed] Sorting failed, trying without sort parameter');
      try {
        await _fetchWithoutSort();
        return; // Success, don't show error
      } catch (e) {
        _debugLog('[home-feed] Fallback without sort also failed: $e');
      }
    }

    // Auto-retry logic for network errors
    if (_fetchRetryCount < _HomePageFields._maxRetries &&
        errorMessage == HomeFeedErrors.network &&
        !isRetry) {
      _fetchRetryCount++;
      _debugLog(
      '[home-feed] Auto-retrying fetch (attempt $_fetchRetryCount/$_HomePageFields._maxRetries)',
      );
      await Future.delayed(Duration(seconds: 1)); // Shorter delay for better UX
      if (mounted) {
        try {
          await fetchCars(bypassCache: bypassCache, isRetry: true);
          return; // Success, don't show error
        } catch (e) {
          _debugLog('[home-feed] Auto-retry failed: $e');
        }
      }
    }

    // Only show error if all fallback strategies failed
    if (mounted) {
      setState(() {
        isLoading = false;
        hasLoadedOnce = true;
        // Only show error if bypassing cache OR no cached data is available
        if (bypassCache || cached == null) {
          loadErrorMessage = errorMessage;
        } else {
          loadErrorMessage = null; // Clear error when using cached data
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasNext) return;
    _isLoadingMore = true;
    try {
      final Map<String, String> filters = _buildFilters();
      filters['page'] = _page.toString();
      filters['per_page'] = '20';
      final resp = await ApiService.getCarsRaw(
        filters,
        timeout: const Duration(seconds: 20),
        extraHeaders: {'Accept': 'application/json'},
      );
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        if (decoded is Map) {
          try {
            final pg = (decoded['pagination'] as Map?);
            if (pg != null && pg['has_next'] is bool) {
              _hasNext = pg['has_next'] as bool;
            }
          } catch (e, st) { logNonFatal(e, st); }
        }
        final List<Map<String, dynamic>> more =
            listingMapsFromApiResponse(decoded);
        if (mounted && more.isNotEmpty) {
          setState(() {
            cars.addAll(_applyDamagedPartsExactFilter(more));
          });
          _HomePageFields._homeFeedCache = copyListingMapList(cars);
          _HomePageFields._homeFeedCachePage = _page;
          _HomePageFields._homeFeedCacheHasNext = _hasNext;
        }
        _page += 1;
      }
    } catch (e, st) { logNonFatal(e, st); }
    _isLoadingMore = false;
  }

  void _scrollHomeToTopAndResetCardImages() {
    _homeScrollRestoreScheduleGen++;
    _pendingHomeScrollRestore = null;
    _lastHomeScrollPixels = 0;
    _HomeFeedScrollPersistence.markTop();
    if (_homeScrollController.hasClients) {
      _homeScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) {
      setState(() {
        _homeCarouselResetSeed++;
      });
    }
  }

  // Fallback fetch using /api/cars which wraps results in { cars: [...], pagination: { has_next: bool } }
  Future<bool> _fetchFromApiCars({bool includeSort = true}) async {
    try {
      Map<String, String> filters = _buildFilters(includeSort: includeSort);
      final resp = await ApiService.getCarsRaw(
        filters,
        timeout: const Duration(seconds: 20),
        extraHeaders: {
              'Accept': 'application/json',
              'Connection': 'close',
              'Cache-Control': 'no-cache',
            },
      );
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        if (decoded is Map && decoded['cars'] is List) {
          final List<Map<String, dynamic>> parsed =
              listingMapsFromApiResponse(decoded);
          if (mounted) {
            setState(() {
              cars = _applyDamagedPartsExactFilter(parsed);
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
            });
          }
          return true;
        }
      }
    } catch (e, st) { logNonFatal(e, st); }
    return false;
  }

  Future<void> _fetchWithoutSort() async {
    try {
      _debugLog('[home-feed] Attempting fetch without sort parameter');
      Map<String, String> filters = _buildFilters(includeSort: false);

      String query = Uri(queryParameters: filters).query;
      final url = Uri.parse(
        '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
      );

      _debugLog('[home-feed] Fallback URL: $url');

      final response = await ApiService.getCarsRaw(
        filters,
        timeout: const Duration(seconds: 10),
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<Map<String, dynamic>> parsed =
            listingMapsFromApiResponse(decoded);

        if (mounted) {
          setState(() {
            cars = _applyDamagedPartsExactFilter(parsed);
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage = null;
          });
        }

        _debugLog(
      '[home-feed] Fallback fetch successful: ${parsed.length} cars loaded',
        );

        // Show a message that sorting was disabled
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(homeFeedSortDisabledText(context)),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        _debugLog('[home-feed] Fallback fetch failed: ${response.statusCode}');
        if (mounted) {
          setState(() {
            loadErrorMessage = HomeFeedErrors.server(response.statusCode);
            isLoading = false;
          });
        }
      }
    } catch (e) {
      _debugLog('[home-feed] Fallback fetch error: $e');
      if (mounted) {
        setState(() {
          loadErrorMessage = HomeFeedErrors.network;
          isLoading = false;
        });
      }
    }
  }

  void onFilterChanged() {
    // Analytics tracking for filters applied
    fetchCars();
    // Auto-save search after applying filters
    unawaited(_autoSaveSearch());
  }

  List<Map<String, dynamic>> _applyDamagedPartsExactFilter(
    List<Map<String, dynamic>> input,
  ) =>
      applyDamagedPartsListingFilter(
        input,
        selectedTitleStatus: selectedTitleStatus,
        selectedDamagedParts: selectedDamagedParts,
      );

  Map<String, String> _buildFilters({bool includeSort = true}) {
    final apiSortValue = includeSort
        ? _convertSortToApiValue(context, selectedSortBy)
        : null;
    return homeFiltersToApiQuery(
      _homeFiltersSnapshot(),
      apiSortValue: apiSortValue,
      includeSort: includeSort,
    );
  }

  void onSortChanged() async {
    _debugLog('[home-feed] Sort changed to: $selectedSortBy');
    // Analytics tracking for sort changed

    // Cancel any pending sort operation
    _sortDebounceTimer?.cancel();

    // Immediate response - no debounce for better UX
    if (!mounted) return;

    // Reset retry count when sorting changes
    _fetchRetryCount = 0;

    // Clear any previous error messages but do NOT set isLoading = true so we
    // keep showing the current list until the sorted result arrives (avoids
    // flashing empty state when only sort changed).
    if (mounted) {
      setState(() {
        loadErrorMessage = null;
      });
    }

    // Clear cache for current filters
    try {
      final sp = await SharedPreferences.getInstance();
      final currentFilters = _buildFilters();
      final query = Uri(queryParameters: currentFilters).query;
      final cacheKey = 'cache_home_${query.hashCode}';
      await sp.remove(cacheKey);
      _debugLog('[home-feed] Cleared cache for current filters: $cacheKey');
    } catch (e) {
      _debugLog('[home-feed] Error clearing cache: $e');
    }

    // Try the sort operation immediately
    await _performSortWithFallback();
  }

  Future<void> _performSortWithFallback() async {
    // Validate sort parameter before attempting
    final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
    _debugLog(
      '[home-feed] Sort parameter validation: $selectedSortBy -> $apiSortValue',
    );

    if (apiSortValue == null || apiSortValue.isEmpty) {
      _debugLog('[home-feed] Invalid sort parameter, skipping sort');
      await fetchCars(bypassCache: true);
      return;
    }

    // Try multiple strategies in sequence
    List<Future<void> Function()> strategies = [
      () => _tryDirectSort(apiSortValue),
      () => _tryAlternativeSort(apiSortValue),
      () => _trySimpleSort(apiSortValue),
      () => _tryConnectionReset(apiSortValue),
      () => _tryWithoutSort(),
    ];

    for (int i = 0; i < strategies.length; i++) {
      try {
        _debugLog('[home-feed] Trying strategy ${i + 1}/${strategies.length}');
        await strategies[i]();
        _debugLog('[home-feed] Strategy ${i + 1} successful');
        return;
      } catch (e) {
        _debugLog('[home-feed] Strategy ${i + 1} failed: $e');
        if (i < strategies.length - 1) {
          await Future.delayed(Duration(milliseconds: 200));
        }
      }
    }

    // If all strategies fail, show error
    if (mounted) {
      setState(() {
        loadErrorMessage = 'Failed to load listings';
        isLoading = false;
      });
    }
  }

  Future<void> _tryDirectSort(String apiSortValue) async {
    _debugLog('[home-feed] Direct sort attempt with: $apiSortValue');

    // Try up to 5 times with increasing delays and different approaches
    for (int attempt = 1; attempt <= 5; attempt++) {
      try {
        // Use different timeout and connection settings based on attempt
        final timeout = Duration(seconds: 10 + (attempt * 5));
        _debugLog('[home-feed] Attempt $attempt with ${timeout.inSeconds}s timeout');

        Map<String, String> filters = _buildFilters();
        final response = await ApiService.getCarsRaw(
          filters,
          timeout: timeout,
          extraHeaders: {
                'Accept': 'application/json',
                'User-Agent': 'CarNet-Mobile/1.0',
                'Connection': attempt % 2 == 0 ? 'close' : 'keep-alive',
                'Cache-Control': 'no-cache',
              },
        );

        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          final List<Map<String, dynamic>> parsed =
              listingMapsFromApiResponse(decoded);

          if (mounted) {
            setState(() {
              if (parsed.isNotEmpty) {
                cars = _applyDamagedPartsExactFilter(parsed);
              } else if (cars.isEmpty) {
                cars = _applyDamagedPartsExactFilter(parsed);
              }
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
            });
          }

          // Save to cache
          final sp = await SharedPreferences.getInstance();
          final query = Uri(queryParameters: filters).query;
          final cacheKey = 'cache_home_${query.hashCode}';
          unawaited(sp.setString(cacheKey, response.body));

          unawaited(_autoSaveSearch());
          _debugLog('[home-feed] Direct sort successful on attempt $attempt');
          return;
        } else {
          throw Exception('Server error: ${response.statusCode}');
        }
      } catch (e) {
        _debugLog('[home-feed] Direct sort attempt $attempt failed: $e');
        if (attempt < 5) {
          await Future.delayed(Duration(milliseconds: 200 * attempt));
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> _tryAlternativeSort(String apiSortValue) async {
    _debugLog('[home-feed] Alternative sort attempt with: $apiSortValue');

    // Try with different connection approaches
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        Map<String, String> filters = _buildFilters();
        final response = await ApiService.getCarsRaw(
          filters,
          timeout: const Duration(seconds: 15),
          extraHeaders: {
                'Accept': 'application/json',
                'User-Agent': 'CarNet-Mobile/1.0',
                'Connection': 'close',
                'Cache-Control': 'no-cache',
                'Pragma': 'no-cache',
                'If-None-Match': '*',
              },
        );

        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          final List<Map<String, dynamic>> parsed =
              listingMapsFromApiResponse(decoded);

          if (mounted) {
            setState(() {
              if (parsed.isNotEmpty) {
                cars = _applyDamagedPartsExactFilter(parsed);
              } else if (cars.isEmpty) {
                cars = _applyDamagedPartsExactFilter(parsed);
              }
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
            });
          }

          unawaited(_autoSaveSearch());
          _debugLog('[home-feed] Alternative sort successful on attempt $attempt');
          return;
        } else {
          throw Exception('Server error: ${response.statusCode}');
        }
      } catch (e) {
        _debugLog('[home-feed] Alternative sort attempt $attempt failed: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 300));
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> _trySimpleSort(String apiSortValue) async {
    _debugLog('[home-feed] Simple sort attempt with: $apiSortValue');
    // Try with minimal headers and shorter timeout
    Map<String, String> filters = _buildFilters();

    final response = await ApiService.getCarsRaw(
      filters,
      timeout: const Duration(seconds: 10),
      extraHeaders: {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final List<Map<String, dynamic>> parsed =
          listingMapsFromApiResponse(decoded);

      if (mounted) {
        setState(() {
          if (parsed.isNotEmpty) {
            cars = _applyDamagedPartsExactFilter(parsed);
          } else if (cars.isEmpty) {
            cars = _applyDamagedPartsExactFilter(parsed);
          }
          isLoading = false;
          hasLoadedOnce = true;
          loadErrorMessage = null;
        });
      }
      unawaited(_autoSaveSearch());
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  Future<void> _tryConnectionReset(String apiSortValue) async {
    _debugLog('[home-feed] Connection reset attempt with: $apiSortValue');

    // Wait a bit longer and try with a completely fresh approach
    await Future.delayed(Duration(milliseconds: 1000));

    try {
      Map<String, String> filters = _buildFilters();

      // Try with a very simple request
      final response = await ApiService.getCarsRaw(
        filters,
        timeout: const Duration(seconds: 20),
        extraHeaders: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<Map<String, dynamic>> parsed =
            listingMapsFromApiResponse(decoded);

        if (mounted) {
          setState(() {
            if (parsed.isNotEmpty) {
              cars = _applyDamagedPartsExactFilter(parsed);
            } else if (cars.isEmpty) {
              cars = _applyDamagedPartsExactFilter(parsed);
            }
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage = null;
          });
        }

        unawaited(_autoSaveSearch());
        _debugLog('[home-feed] Connection reset successful');
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      _debugLog('[home-feed] Connection reset failed: $e');
      rethrow;
    }
  }

  Future<void> _tryWithoutSort() async {
    _debugLog('[home-feed] Fallback: trying without sort');
    try {
      await _fetchWithoutSort();
      // If we get here, try client-side sorting as a last resort
      await _tryClientSideSort();
    } catch (e) {
      _debugLog('[home-feed] Fallback also failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sorting temporarily unavailable'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _tryClientSideSort() async {
    _debugLog('[home-feed] Attempting client-side sort');
    final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
    if (apiSortValue == null || selectedSortBy == null) return;

    List<Map<String, dynamic>> sortedCars = List.from(cars);

    try {
      switch (apiSortValue) {
        case 'price_asc':
          sortedCars.sort((a, b) {
            final priceA = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
            final priceB = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
            return priceA.compareTo(priceB);
          });
          break;
        case 'price_desc':
          sortedCars.sort((a, b) {
            final priceA = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
            final priceB = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
            return priceB.compareTo(priceA);
          });
          break;
        case 'year_desc':
          sortedCars.sort((a, b) {
            final yearA = int.tryParse(a['year']?.toString() ?? '0') ?? 0;
            final yearB = int.tryParse(b['year']?.toString() ?? '0') ?? 0;
            return yearB.compareTo(yearA);
          });
          break;
        case 'year_asc':
          sortedCars.sort((a, b) {
            final yearA = int.tryParse(a['year']?.toString() ?? '0') ?? 0;
            final yearB = int.tryParse(b['year']?.toString() ?? '0') ?? 0;
            return yearA.compareTo(yearB);
          });
          break;
        case 'mileage_asc':
          sortedCars.sort((a, b) {
            final mileageA = int.tryParse(a['mileage']?.toString() ?? '0') ?? 0;
            final mileageB = int.tryParse(b['mileage']?.toString() ?? '0') ?? 0;
            return mileageA.compareTo(mileageB);
          });
          break;
        case 'mileage_desc':
          sortedCars.sort((a, b) {
            final mileageA = int.tryParse(a['mileage']?.toString() ?? '0') ?? 0;
            final mileageB = int.tryParse(b['mileage']?.toString() ?? '0') ?? 0;
            return mileageB.compareTo(mileageA);
          });
          break;
        case 'newest':
          sortedCars.sort((a, b) {
            final dateA =
                DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                DateTime(1970);
            final dateB =
                DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                DateTime(1970);
            return dateB.compareTo(dateA);
          });
          break;
      }

      if (mounted) {
        setState(() {
          cars = sortedCars;
          isLoading = false;
          loadErrorMessage = null;
        });
      }

      _debugLog('[home-feed] Client-side sort successful');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(homeFeedSortedLocallyText(context)),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      _debugLog('[home-feed] Client-side sort failed: $e');
      rethrow;
    }
  }

  // Intentionally disabled: auto-saving on every filter change created many duplicates.
  Future<void> _autoSaveSearch() async {}
}
