part of 'dealers_directory_page.dart';

abstract class _DealersDirectoryPageFields extends State<DealersDirectoryPage> {
  static const Color _brandOrange = Color(0xFFFF6B00);

  final TextEditingController _query = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasNext = false;
  static const int _perPage = 20;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.dispose();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
