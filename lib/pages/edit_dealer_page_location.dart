part of 'edit_dealer_page.dart';

mixin _EditDealerPageLocation on _EditDealerPageProfile {

  Future<void> _openMapPicker() async {
    if (kIsWeb) return;
    final res = await Navigator.push<Map<String, double>>(
      context,
      AppPageRoute(
        builder: (_) => DealerLocationPickerPage(
          initialLatitude: _pickLat,
          initialLongitude: _pickLng,
        ),
      ),
    );
    if (!mounted || res == null) return;
    final lat = res['lat'];
    final lng = res['lng'];
    if (lat == null || lng == null) return;
    setState(() {
      _pickLat = lat;
      _pickLng = lng;
      _coordLat.text = lat.toString();
      _coordLng.text = lng.toString();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _mapPreviewKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.2,
        );
      }
    });
  }

  void _clearMapPin() {
    setState(() {
      _pickLat = null;
      _pickLng = null;
      _coordLat.clear();
      _coordLng.clear();
    });
  }

  ({double lat, double lng})? _effectivePinForPreview() {
    if (kIsWeb) {
      final lat = double.tryParse(_coordLat.text.trim());
      final lng = double.tryParse(_coordLng.text.trim());
      if (lat == null || lng == null) return null;
      if (!isValidDealerLatLng(lat, lng)) return null;
      return (lat: lat, lng: lng);
    }
    final lat = _pickLat;
    final lng = _pickLng;
    if (lat == null || lng == null) return null;
    if (!isValidDealerLatLng(lat, lng)) return null;
    return (lat: lat, lng: lng);
  }

  Future<void> _openPinInGoogleMaps(double lat, double lng) async {
    final ok = await openGoogleMapsAt(lat, lng).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Could not open Google Maps', ar: 'تعذر فتح خرائط Google', ku: 'نەکرا نەخشەی گووگڵ بکرێتەوە'))),
      );
    }
  }
}
