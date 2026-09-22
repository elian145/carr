part of 'home_flow.dart';

mixin _HomePageFetch on _HomePageFetchCore {
  void onSortChanged() async {
    _debugLog('[home-feed] Sort changed to: $selectedSortBy');
    // Analytics tracking for sort changed

    // Cancel any pending sort operation
    _sortDebounceTimer?.cancel();

    // Immediate response - no debounce for better UX
    if (!mounted) return;

    // Claims a new generation so any in-flight search/feed fetch (or an
    // earlier sort attempt) can never overwrite this one's result, and vice
    // versa — see `_feedRequestGeneration`'s doc comment on `_HomePageFields`.
    final int requestGen = ++_feedRequestGeneration;

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
      await _invalidateHomeDiskCache(sp, _homeDiskCacheKey(query));
      _debugLog('[home-feed] Cleared cache for current filters');
    } catch (e) {
      _debugLog('[home-feed] Error clearing cache: $e');
    }

    // Try the sort operation immediately
    await _performSortWithFallback(requestGen);
  }

  Future<void> _performSortWithFallback(int requestGen) async {
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
      () => _tryDirectSort(apiSortValue, requestGen),
      () => _tryAlternativeSort(apiSortValue, requestGen),
      () => _trySimpleSort(apiSortValue, requestGen),
      () => _tryConnectionReset(apiSortValue, requestGen),
      () => _tryWithoutSort(requestGen),
    ];

    for (int i = 0; i < strategies.length; i++) {
      // A newer request (another sort change or a fresh search) has since
      // started — stop trying strategies for this now-stale one instead of
      // possibly overwriting the newer request's results below.
      if (requestGen != _feedRequestGeneration) return;
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

    if (requestGen != _feedRequestGeneration) return;

    // If all strategies fail, show error
    if (mounted) {
      setState(() {
        loadErrorMessage = 'Failed to load listings';
        isLoading = false;
      });
    }
  }

  Future<void> _tryDirectSort(String apiSortValue, int requestGen) async {
    _debugLog('[home-feed] Direct sort attempt with: $apiSortValue');

    // Try up to 5 times with increasing delays and different approaches
    for (int attempt = 1; attempt <= 5; attempt++) {
      try {
        // Use different timeout and connection settings based on attempt
        final timeout = Duration(seconds: 10 + (attempt * 5));
        _debugLog('[home-feed] Attempt $attempt with ${timeout.inSeconds}s timeout');

        Map<String, String> filters = _buildFilters();
        final int traceId = ++_searchTraceRequestSeq;
        _debugLog(
          '[search-trace] REQUEST trace=$traceId gen=$requestGen endpoint=/api/cars '
          'source=_tryDirectSort q=${filters['q']} model=${filters['model']} '
          'brand=${filters['brand']} page=${filters['page']} '
          'per_page=${filters['per_page']} sort_by=${filters['sort_by']} '
          'all_params=$filters',
        );
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
          // A newer request (search/filter change/another sort) superseded
          // this one while it was in flight — treat as done, not a
          // failure, and never overwrite the newer request's results.
          if (requestGen != _feedRequestGeneration) {
            _debugLog(
              '[search-trace] STALE-DISCARDED trace=$traceId gen=$requestGen '
              'current_gen=$_feedRequestGeneration source=_tryDirectSort',
            );
            return;
          }
          final decoded = json.decode(response.body);
          final List<Map<String, dynamic>> parsed =
              listingMapsFromApiResponse(decoded);
          _debugLog(
            '[search-trace] RESPONSE trace=$traceId gen=$requestGen '
            'query="${filters['q']}" status=${response.statusCode} '
            'models=${_searchTraceListingSummary(parsed)}',
          );

          if (mounted) {
            setState(() {
              if (parsed.isNotEmpty) {
                cars = _applyClientPostFilters(parsed);
              } else if (cars.isEmpty) {
                cars = _applyClientPostFilters(parsed);
              }
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
            });
          }

          // Save to cache
          final sp = await SharedPreferences.getInstance();
          final query = Uri(queryParameters: filters).query;
          final cacheKey = _homeDiskCacheKey(query);
          unawaited(_writeHomeDiskCache(sp, cacheKey, response.body));
          _HomePageFields._homeFeedCacheFetchedAt = DateTime.now();

          _debugLog(
            '[search-trace] STATE-APPLIED trace=$traceId gen=$requestGen '
            'query="${filters['q']}" source=_tryDirectSort '
            'cars.length=${cars.length} models=${_searchTraceListingSummary(cars)}',
          );

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

  Future<void> _tryAlternativeSort(String apiSortValue, int requestGen) async {
    _debugLog('[home-feed] Alternative sort attempt with: $apiSortValue');

    // Try with different connection approaches
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        Map<String, String> filters = _buildFilters();
        final int traceId = ++_searchTraceRequestSeq;
        _debugLog(
          '[search-trace] REQUEST trace=$traceId gen=$requestGen endpoint=/api/cars '
          'source=_tryAlternativeSort q=${filters['q']} all_params=$filters',
        );
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
          if (requestGen != _feedRequestGeneration) {
            _debugLog(
              '[search-trace] STALE-DISCARDED trace=$traceId gen=$requestGen '
              'current_gen=$_feedRequestGeneration source=_tryAlternativeSort',
            );
            return;
          }
          final decoded = json.decode(response.body);
          final List<Map<String, dynamic>> parsed =
              listingMapsFromApiResponse(decoded);
          _debugLog(
            '[search-trace] RESPONSE trace=$traceId gen=$requestGen '
            'query="${filters['q']}" status=${response.statusCode} '
            'models=${_searchTraceListingSummary(parsed)}',
          );

          if (mounted) {
            setState(() {
              if (parsed.isNotEmpty) {
                cars = _applyClientPostFilters(parsed);
              } else if (cars.isEmpty) {
                cars = _applyClientPostFilters(parsed);
              }
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
            });
          }

          _debugLog(
            '[search-trace] STATE-APPLIED trace=$traceId gen=$requestGen '
            'query="${filters['q']}" source=_tryAlternativeSort '
            'cars.length=${cars.length} models=${_searchTraceListingSummary(cars)}',
          );
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

  Future<void> _trySimpleSort(String apiSortValue, int requestGen) async {
    _debugLog('[home-feed] Simple sort attempt with: $apiSortValue');
    // Try with minimal headers and shorter timeout
    Map<String, String> filters = _buildFilters();
    final int traceId = ++_searchTraceRequestSeq;
    _debugLog(
      '[search-trace] REQUEST trace=$traceId gen=$requestGen endpoint=/api/cars '
      'source=_trySimpleSort q=${filters['q']} all_params=$filters',
    );

    final response = await ApiService.getCarsRaw(
      filters,
      timeout: const Duration(seconds: 10),
      extraHeaders: {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      if (requestGen != _feedRequestGeneration) {
        _debugLog(
          '[search-trace] STALE-DISCARDED trace=$traceId gen=$requestGen '
          'current_gen=$_feedRequestGeneration source=_trySimpleSort',
        );
        return;
      }
      final decoded = json.decode(response.body);
      final List<Map<String, dynamic>> parsed =
          listingMapsFromApiResponse(decoded);
      _debugLog(
        '[search-trace] RESPONSE trace=$traceId gen=$requestGen '
        'query="${filters['q']}" status=${response.statusCode} '
        'models=${_searchTraceListingSummary(parsed)}',
      );

      if (mounted) {
        setState(() {
          if (parsed.isNotEmpty) {
            cars = _applyClientPostFilters(parsed);
          } else if (cars.isEmpty) {
            cars = _applyClientPostFilters(parsed);
          }
          isLoading = false;
          hasLoadedOnce = true;
          loadErrorMessage = null;
        });
        _debugLog(
          '[search-trace] STATE-APPLIED trace=$traceId gen=$requestGen '
          'query="${filters['q']}" source=_trySimpleSort '
          'cars.length=${cars.length} models=${_searchTraceListingSummary(cars)}',
        );
      }
      unawaited(_autoSaveSearch());
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  Future<void> _tryConnectionReset(String apiSortValue, int requestGen) async {
    _debugLog('[home-feed] Connection reset attempt with: $apiSortValue');

    // Wait a bit longer and try with a completely fresh approach
    await Future.delayed(Duration(milliseconds: 1000));

    try {
      Map<String, String> filters = _buildFilters();
      final int traceId = ++_searchTraceRequestSeq;
      _debugLog(
        '[search-trace] REQUEST trace=$traceId gen=$requestGen endpoint=/api/cars '
        'source=_tryConnectionReset q=${filters['q']} all_params=$filters',
      );

      // Try with a very simple request
      final response = await ApiService.getCarsRaw(
        filters,
        timeout: const Duration(seconds: 20),
        extraHeaders: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        if (requestGen != _feedRequestGeneration) {
          _debugLog(
            '[search-trace] STALE-DISCARDED trace=$traceId gen=$requestGen '
            'current_gen=$_feedRequestGeneration source=_tryConnectionReset',
          );
          return;
        }
        final decoded = json.decode(response.body);
        final List<Map<String, dynamic>> parsed =
            listingMapsFromApiResponse(decoded);
        _debugLog(
          '[search-trace] RESPONSE trace=$traceId gen=$requestGen '
          'query="${filters['q']}" status=${response.statusCode} '
          'models=${_searchTraceListingSummary(parsed)}',
        );

        if (mounted) {
          setState(() {
            if (parsed.isNotEmpty) {
              cars = _applyClientPostFilters(parsed);
            } else if (cars.isEmpty) {
              cars = _applyClientPostFilters(parsed);
            }
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage = null;
          });
          _debugLog(
            '[search-trace] STATE-APPLIED trace=$traceId gen=$requestGen '
            'query="${filters['q']}" source=_tryConnectionReset '
            'cars.length=${cars.length} models=${_searchTraceListingSummary(cars)}',
          );
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

  Future<void> _tryWithoutSort(int requestGen) async {
    _debugLog('[home-feed] Fallback: trying without sort');
    try {
      await _fetchWithoutSort(requestGen: requestGen);
      // If we get here, try client-side sorting as a last resort
      await _tryClientSideSort(requestGen);
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

  Future<void> _tryClientSideSort(int requestGen) async {
    _debugLog('[home-feed] Attempting client-side sort');
    final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
    if (apiSortValue == null || selectedSortBy == null) return;
    if (requestGen != _feedRequestGeneration) return;

    try {
      final sortedCars = homeFeedClientSortedListings(cars, apiSortValue);

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
}
