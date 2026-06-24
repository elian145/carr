part of 'dealer_location_picker_page.dart';

abstract class _DealerLocationPickerPageFields extends State<DealerLocationPickerPage> {
  late LatLng _markerPosition;
  GoogleMapController? _mapController;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _searching = false;
  GooglePlacesAutocomplete? _places;
  List<Prediction> _predictions = const [];
  bool _placesReady = false;
  String? _placesInitError;
  String _lastQuery = '';
  String _lastExplicitSearchQuery = '';

  String _tr(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _places?.dispose();
    super.dispose();
  }
}
