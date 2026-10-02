part of 'car_details_page.dart';

mixin _CarDetailsPageInit on _CarDetailsPageLoad {
  @override
  void initState() {
    super.initState();
    // Auto-reconciliation fix: observe app foreground/background so the
    // owner-media poll timer (see `_CarDetailsPageLoad
    // ._maybeScheduleOwnerMediaPoll`) pauses while backgrounded and
    // resumes on return, instead of silently polling (or silently never
    // resuming) regardless of visibility.
    WidgetsBinding.instance.addObserver(this);
    _listingColumnsPref = ListingLayoutPrefs.columns.value;
    ListingLayoutPrefs.load();
    ListingLayoutPrefs.columns.addListener(_onListingLayoutChanged);
    _scrollController.addListener(_onScroll);
    unawaited(
      AnalyticsService.trackView(widget.carId.toString()),
    );
    _loadCar();
  }

  @override
  void dispose() {
    // F-06: genuinely abort a still-in-flight car-detail load instead of
    // leaving it running in the background after this screen is gone.
    _loadCarCancelToken?.cancel();
    _cancelOwnerMediaPoll();
    WidgetsBinding.instance.removeObserver(this);
    try {
      ListingLayoutPrefs.columns.removeListener(_onListingLayoutChanged);
    } catch (e, st) { logNonFatal(e, st); }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _imagePageController.dispose();
    super.dispose();
  }
}
