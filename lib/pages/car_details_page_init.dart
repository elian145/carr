part of 'car_details_page.dart';

mixin _CarDetailsPageInit on _CarDetailsPageLoad {
  @override
  void initState() {
    super.initState();
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
    try {
      ListingLayoutPrefs.columns.removeListener(_onListingLayoutChanged);
    } catch (e, st) { logNonFatal(e, st); }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _imagePageController.dispose();
    _similarSnapController.dispose();
    _relatedSnapController.dispose();
    super.dispose();
  }
}
