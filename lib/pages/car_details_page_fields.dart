part of 'car_details_page.dart';

abstract class _CarDetailsPageFields extends State<CarDetailsPage> {
  Map<String, dynamic>? car;
  bool loading = true;

  /// Set when a load attempt leaves [car] null for a reason other than the
  /// initial spinner (F-01/B-02): selects which failure UI
  /// `_CarDetailsPageBuild` renders instead of always showing the generic
  /// "Car not found" text. Null while loading or once [car] is populated.
  _CarDetailLoadError? loadError;
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
