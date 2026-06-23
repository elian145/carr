part of 'home_flow.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

abstract class _HomePageFields extends State<HomePage> {
  // Keep a lightweight in-memory feed snapshot across route replacement.
  static List<Map<String, dynamic>> _homeFeedCache = <Map<String, dynamic>>[];
  static int _homeFeedCachePage = 1;
  static bool _homeFeedCacheHasNext = true;
  static bool _homeDeleteHandlerRegistered = false;

  List<Map<String, dynamic>> cars = [];
  bool isLoading = true;
  bool hasLoadedOnce = false;
  String? loadErrorMessage;

  // Filter variables
  String? selectedBrand;
  String? selectedModel;
  String? selectedTrim;
  String? selectedMinPrice;
  String? selectedMaxPrice;
  String? selectedMinYear;
  String? selectedMaxYear;
  String? selectedMinMileage;
  String? selectedMaxMileage;
  String? selectedCondition;
  String? selectedTransmission;
  String? selectedFuelType;
  String? selectedBodyType;
  String? selectedColor;
  String? selectedDriveType;

  /// Lowercase API code: us, gcc, iraq, … (see [kCarRegionSpecCodes]).
  String? selectedRegionSpecs;
  String? selectedCylinderCount;
  String? selectedSeating;
  String? selectedEngineSize;
  String? selectedCity;
  String? selectedPlateType;
  String? selectedPlateCity;
  String? selectedTitleStatus;
  String? selectedDamagedParts;
  String? contactPhone;
  String? selectedSortBy;

  // Toggle states for unified filters
  bool isPriceDropdown = true;
  bool isYearDropdown = true;
  bool isMileageDropdown = true;
  bool isEngineSizeDropdown = true;
  static const String _filtersKey = 'home_filters_v1';
  static const String _sellFiltersKey = 'sell_filters_v1';
  static const String _savedSearchesKey = 'saved_searches_v1';

  // Listings layout
  int listingColumns = 2;
  // Infinite scroll state (offset restored via [_HomeFeedScrollPersistence] after tab switches)
  late final ScrollController _homeScrollController;
  /// Target scroll offset to apply after listings finish loading (initial offset is lost while `isLoading`).
  double? _pendingHomeScrollRestore;
  int _homeScrollRestoreScheduleGen = 0;
  /// Last known pixels (updated in scroll listener); [dispose] often runs after the viewport dropped [ScrollPosition] clients.
  double _lastHomeScrollPixels = 0;
  int _homeCarouselResetSeed = 0;
  int _page = 1;
  bool _hasNext = true;
  bool _isLoadingMore = false;

  /// When the list is empty but a non-default sort is set, auto-fetch once
  /// (no sort/apply UI on the empty state).
  bool _autoFetchedForEmptyWithSort = false;

  // Toggle state for inline engine size picker on the sell page.
  bool isInlineEngineSizeDropdown = true;

  /// Bumped when More Filters form fields are reset so dropdowns remount
  /// (`initialValue` is otherwise ignored after the first build).
  int _moreFiltersDialogFieldGeneration = 0;

  /// Bundled spec DB for model-aware engine / cylinder pick lists in More Filters.
  CarSpecIndex? _homeCarSpecIdx;
  String? _homeMotorOptsCacheKey;
  ({List<String> engines, List<String> cylinders})? _homeMotorOptsCache;
  String? _homeFilterSpecVariantsCacheKey;
  List<OnlineSpecVariant>? _homeFilterSpecVariantsCache;

  Timer? _sortDebounceTimer;
  int _fetchRetryCount = 0;
  static const int _maxRetries = 3;
  // Static options
  List<String> get homeBrands => CarCatalog.brands;
  Map<String, List<String>> get models => CarCatalog.models;
  Map<String, Map<String, List<String>>> get trimsByBrandModel =>
      CarCatalog.trimsByBrandModel;

  final List<String> trims = [
    'Base',
    'Sport',
    'Luxury',
    'Premium',
    'Limited',
    'Platinum',
    'Signature',
    'Touring',
    'SE',
    'LE',
    'XLE',
    'XSE',
  ];
  final List<String> conditions = ['Any', 'New', 'Used'];
  // Same options as sell page (with 'Any' for filter)
  final List<String> transmissions = ['Any', 'Automatic', 'Manual'];
  final List<String> fuelTypes = [
    'Any',
    'Gasoline',
    'Diesel',
    'Electric',
    'Hybrid',
    'Plug-in Hybrid',
  ];
  // Same options as sell page (with 'Any' for filter); keep fixed list so More Filters matches sell page
  List<String> bodyTypes = [
    'Any',
    'Sedan',
    'SUV',
    'Hatchback',
    'Coupe',
    'Convertible',
    'Wagon',
    'Pickup',
    'Van',
    'Minivan',
  ];
  final List<String> colors = [
    'Any',
    'Black',
    'White',
    'Silver',
    'Gray',
    'Red',
    'Blue',
    'Green',
    'Yellow',
    'Orange',
    'Purple',
    'Brown',
    'Beige',
    'Gold',
  ];
  final List<String> driveTypes = ['Any', 'FWD', 'RWD', 'AWD', '4WD'];
  final List<String> cylinderCounts = [
    'Any',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
  ];
  final List<String> seatings = [
    'Any',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
    '17',
    '18',
    '19',
    '20',
    '21',
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
    '28',
    '29',
    '30',
    '31',
    '32',
    '33',
    '34',
    '35',
    '36',
    '37',
    '38',
    '39',
    '40',
    '41',
    '42',
    '43',
    '44',
    '45',
    '46',
    '47',
    '48',
    '49',
    '50',
  ];
  final List<String> engineSizes = [
    'Any',
    '0.5',
    '0.6',
    '0.7',
    '0.8',
    '0.9',
    '1.0',
    '1.1',
    '1.2',
    '1.3',
    '1.4',
    '1.5',
    '1.6',
    '1.7',
    '1.8',
    '1.9',
    '2.0',
    '2.1',
    '2.2',
    '2.3',
    '2.4',
    '2.5',
    '2.6',
    '2.7',
    '2.8',
    '2.9',
    '3.0',
    '3.1',
    '3.2',
    '3.3',
    '3.4',
    '3.5',
    '3.6',
    '3.7',
    '3.8',
    '3.9',
    '4.0',
    '4.1',
    '4.2',
    '4.3',
    '4.4',
    '4.5',
    '4.6',
    '4.7',
    '4.8',
    '4.9',
    '5.0',
    '5.1',
    '5.2',
    '5.3',
    '5.4',
    '5.5',
    '5.6',
    '5.7',
    '5.8',
    '5.9',
    '6.0',
    '6.1',
    '6.2',
    '6.3',
    '6.4',
    '6.5',
    '6.6',
    '6.7',
    '6.8',
    '6.9',
    '7.0',
    '7.1',
    '7.2',
    '7.3',
    '7.4',
    '7.5',
    '7.6',
    '7.7',
    '7.8',
    '7.9',
    '8.0',
    '8.1',
    '8.2',
    '8.3',
    '8.4',
    '8.5',
    '8.6',
    '8.7',
    '8.8',
    '8.9',
    '9.0',
    '9.1',
    '9.2',
    '9.3',
    '9.4',
    '9.5',
    '9.6',
    '9.7',
    '9.8',
    '9.9',
    '10.0',
    '10.1',
    '10.2',
    '10.3',
    '10.4',
    '10.5',
    '10.6',
    '10.7',
    '10.8',
    '10.9',
    '11.0',
    '11.1',
    '11.2',
    '11.3',
    '11.4',
    '11.5',
    '11.6',
    '11.7',
    '11.8',
    '11.9',
    '12.0',
    '12.1',
    '12.2',
    '12.3',
    '12.4',
    '12.5',
    '12.6',
    '12.7',
    '12.8',
    '12.9',
    '13.0',
    '13.1',
    '13.2',
    '13.3',
    '13.4',
    '13.5',
    '13.6',
    '13.7',
    '13.8',
    '13.9',
    '14.0',
    '14.1',
    '14.2',
    '14.3',
    '14.4',
    '14.5',
    '14.6',
    '14.7',
    '14.8',
    '14.9',
    '15.0',
    '15.1',
    '15.2',
    '15.3',
    '15.4',
    '15.5',
    '15.6',
    '15.7',
    '15.8',
    '15.9',
    '16.0',
  ];
  final List<String> cities = [
    'Any',
    'Baghdad',
    'Basra',
    'Erbil',
    'Najaf',
    'Karbala',
    'Kirkuk',
    'Mosul',
    'Sulaymaniyah',
    'Dohuk',
    'Anbar',
    'Halabja',
    'Diyala',
    'Diyarbakir',
    'Maysan',
    'Muthanna',
    'Dhi Qar',
    'Salaheldeen',
  ];
  List<String> getLocalizedSortOptions(BuildContext context) => [
    AppLocalizations.of(context)!.defaultSort,
    AppLocalizations.of(context)!.sort_newest,
    AppLocalizations.of(context)!.sort_price_low_high,
    AppLocalizations.of(context)!.sort_price_high_low,
    AppLocalizations.of(context)!.sort_year_newest,
    AppLocalizations.of(context)!.sort_year_oldest,
    AppLocalizations.of(context)!.sort_mileage_low_high,
    AppLocalizations.of(context)!.sort_mileage_high_low,
  ];

  bool useCustomMinPrice = false;
  bool useCustomMaxPrice = false;
  bool useCustomMinMileage = false;
  bool useCustomMaxMileage = false;

  // Controllers for manual (non-dropdown) filter inputs in the "More Filters" dialog.
  // These avoid creating new controllers on every rebuild (which can cause churn/leaks).
  late final TextEditingController _minPriceController;
  late final TextEditingController _maxPriceController;
  late final TextEditingController _minYearController;
  late final TextEditingController _maxYearController;
  late final TextEditingController _minMileageController;
  late final TextEditingController _maxMileageController;
  late final TextEditingController _engineSizeController;

}

class _HomePageState extends _HomePageFields
    with _HomePageFetch, _HomePageFilterLogic, _HomePageFilterBar, _HomePageMoreFiltersDialog, _HomePageBuild {
  @override
  void initState() {
    super.initState();
    final seededOffset = _HomeFeedScrollPersistence.initialOffset;
    _homeScrollController = ScrollController(
      initialScrollOffset: seededOffset > 0 ? seededOffset : 0,
    );
    _primePendingHomeScrollRestoreFromPersistence();
    _minPriceController = TextEditingController();
    _maxPriceController = TextEditingController();
    _minYearController = TextEditingController();
    _maxYearController = TextEditingController();
    _minMileageController = TextEditingController();
    _maxMileageController = TextEditingController();
    _engineSizeController = TextEditingController();
    if (_HomePageFields._homeFeedCache.isNotEmpty) {
      cars = copyListingMapList(_HomePageFields._homeFeedCache);
      isLoading = false;
      hasLoadedOnce = true;
      _page = _HomePageFields._homeFeedCachePage;
      _hasNext = _HomePageFields._homeFeedCacheHasNext;
    }
    // Restore last chosen layout (grid vs list) across pages.
    ListingLayoutPrefs.load().then((cols) {
      if (!mounted) return;
      setState(() {
        listingColumns = cols;
      });
    });
    _loadBodyTypesFromAssets();
    CarSpecIndex.loadWithResult().then((r) {
      if (!mounted) return;
      setState(() {
        _homeCarSpecIdx = r.index;
        _invalidateHomeCatalogFilterCaches();
        _pruneHomeMotorFilterSelectionsIfInvalid();
      });
    });
    if (!_HomePageFields._homeDeleteHandlerRegistered) {
      _HomePageFields._homeDeleteHandlerRegistered = true;
      ListingEvents.addDeleteHandler(_purgeDeletedFromHomeFeedCache);
    }
    ListingEvents.deletedListingId.addListener(_onHomeListingDeleted);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Avoid network calls during `flutter test` runs.
      // `FLUTTER_TEST` isn't reliably set as a compile-time define for all builds,
      // so we also check the runtime environment variable.
      if (_kFlutterTest || Platform.environment.containsKey('FLUTTER_TEST')) {
        return;
      }
      await _restoreFilters();
      if (!mounted) return;
      final oneTimeFilters = await SavedSearchHomeBridge.consumeOneTimeFilters();
      final pendingSavedSearch = await SavedSearchHomeBridge.consumePendingFetch();
      if (oneTimeFilters != null) {
        setState(() {
          applyFiltersFromHomePersistMap(oneTimeFilters);
        });
      }
      if (pendingSavedSearch || oneTimeFilters != null) {
        _HomePageFields._homeFeedCache.clear();
        if (mounted) {
          setState(() {
            cars = [];
            _page = 1;
            _hasNext = true;
          });
        }
        fetchCars(bypassCache: true);
      } else if (cars.isEmpty) {
        // If we already rehydrated listings from memory (tab return), do not run an
        // immediate fetchCars(): the first-page API response would replace a deep
        // scroll's many rows with ~20 items, collapse maxScrollExtent, and wipe the
        // saved offset. User can pull-to-refresh or change filters to refetch.
        fetchCars();
      }
      // Kick restoration once the first frame is mounted, instead of waiting
      // for user interaction/layout changes.
      _scheduleHomeScrollRestoreAfterListReady();
    });
    // Hook up infinite scroll
    _homeScrollController.addListener(() {
      try {
        final pos = _homeScrollController.position;
        _lastHomeScrollPixels = pos.pixels.clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        // Never persist while loading overlay replaces the feed (short extent).
        if (isLoading || _isLoadingMore) return;
        // Persist continuously, but don't let temporary clamped restore values
        // overwrite a higher pending target that we still need to reach.
        final pending = _pendingHomeScrollRestore;
        final snapshot = (pending != null && pending > _lastHomeScrollPixels)
            ? pending
            : _lastHomeScrollPixels;
        _HomeFeedScrollPersistence.savePixels(snapshot);
        if (_hasNext &&
            !_isLoadingMore &&
            pos.pixels >= (pos.maxScrollExtent - 400)) {
          _loadMore();
        }
      } catch (e, st) { logNonFatal(e, st); }
    });
  }

  /// Runs on delete even when [HomePage] is disposed (tab uses route replacement).
  static void _purgeDeletedFromHomeFeedCache(String id) {
    _HomePageFields._homeFeedCache.removeWhere((c) => listingMatchesId(c, id));
  }

  void _onHomeListingDeleted() {
    final id = ListingEvents.deletedListingId.value;
    if (id == null || id.isEmpty || !mounted) return;
    setState(() {
      cars.removeWhere((c) => listingMatchesId(c, id));
    });
  }
  @override
  void dispose() {
    ListingEvents.deletedListingId.removeListener(_onHomeListingDeleted);
    _sortDebounceTimer?.cancel();
    unawaited(_persistFilters());
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _minYearController.dispose();
    _maxYearController.dispose();
    _minMileageController.dispose();
    _maxMileageController.dispose();
    _engineSizeController.dispose();
    try {
      _homeScrollRestoreScheduleGen++;
      // Prefer live controller position; on tab replacement the viewport is often
      // gone already (`!hasClients`), so fall back to [_lastHomeScrollPixels] / pending.
      var best = _lastHomeScrollPixels;
      try {
        if (_homeScrollController.hasClients) {
          final pos = _homeScrollController.position;
          best = pos.pixels.clamp(
            pos.minScrollExtent,
            pos.maxScrollExtent,
          );
        }
      } catch (e, st) { logNonFatal(e, st); }
      if (best <= 0 && _pendingHomeScrollRestore != null) {
        best = _pendingHomeScrollRestore!;
      }
      _HomeFeedScrollPersistence.savePixels(best);
      _HomePageFields._homeFeedCache = copyListingMapList(cars);
      _HomePageFields._homeFeedCachePage = _page;
      _HomePageFields._homeFeedCacheHasNext = _hasNext;
      _homeScrollController.dispose();
    } catch (e, st) { logNonFatal(e, st); }
    super.dispose();
  }
}
