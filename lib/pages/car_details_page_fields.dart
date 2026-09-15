part of 'car_details_page.dart';

abstract class _CarDetailsPageFields extends State<CarDetailsPage> {
  Map<String, dynamic>? car;
  bool loading = true;

  /// Set when a load attempt leaves [car] null for a reason other than the
  /// initial spinner (F-01/B-02): selects which failure UI
  /// `_CarDetailsPageBuild` renders instead of always showing the generic
  /// "Car not found" text. Null while loading or once [car] is populated.
  _CarDetailLoadError? loadError;

  /// Cancels the in-flight `ApiService.getCarDetail` call started by the
  /// most recent [_CarDetailsPageLoad._loadCar] (F-06). Cancelled from
  /// `dispose()` and re-created at the start of each `_loadCar()` call
  /// (including retries), so at most one load is ever "live" at a time.
  ApiCancelToken? _loadCarCancelToken;

  /// Exposed only so widget tests can assert that disposing this page
  /// cancels its in-flight car-detail load (F-06). Not read by production
  /// code — mirrors the existing `@visibleForTesting` debug-hook convention
  /// (e.g. `AuthGuard.debugTerminalTimeoutOverride`).
  @visibleForTesting
  ApiCancelToken? get debugLoadCarCancelToken => _loadCarCancelToken;

  bool isFavorite = false;
  List<Map<String, dynamic>> similarCars = [];
  bool loadingSimilar = false;
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;
  int _listingColumnsPref = 2;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _contactButtonsKey = GlobalKey();
  bool _showStickyButtons = true;
}
