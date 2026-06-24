part of 'car_details_page.dart';

abstract class _CarDetailsPageFields extends State<CarDetailsPage> {
  Map<String, dynamic>? car;
  bool loading = true;
  bool isFavorite = false;
  List<Map<String, dynamic>> similarCars = [];
  List<Map<String, dynamic>> relatedCars = [];
  bool loadingSimilar = false;
  bool loadingRelated = false;
  final PageController _imagePageController = PageController();
  final PageController _similarSnapController = PageController();
  final PageController _relatedSnapController = PageController();
  int _currentImageIndex = 0;
  int _listingColumnsPref = 2;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _contactButtonsKey = GlobalKey();
  bool _showStickyButtons = true;
}
