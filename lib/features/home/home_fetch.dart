part of 'home_flow.dart';

mixin _HomePageFetch on _HomePageFetchCore {
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
