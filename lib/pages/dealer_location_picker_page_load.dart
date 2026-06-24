part of 'dealer_location_picker_page.dart';

mixin _DealerLocationPickerPageLoad on _DealerLocationPickerPageFields {
  @override
  void initState() {
    super.initState();
    final lat = widget.initialLatitude;
    final lng = widget.initialLongitude;
    if (lat != null &&
        lng != null &&
        isValidDealerLatLng(lat, lng)) {
      _markerPosition = LatLng(lat, lng);
    } else {
      _markerPosition = _kDefaultMapCenter;
    }

    _initPlaces();

    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q == _lastQuery) return;
      _lastQuery = q;
      if (!mounted) return;
      if (q.isEmpty) {
        setState(() => _predictions = const []);
        return;
      }
      if (_placesReady) {
        _places!.getPredictions(q);
      } else {
        // Still initializing (or failed): just clear stale results.
        setState(() => _predictions = const []);
      }
    });
  }

  void _initPlaces() {
    _places?.dispose();
    _placesReady = false;
    _placesInitError = null;
    _predictions = const [];
    _searching = false;

    final places = GooglePlacesAutocomplete(
      predictionsListener: (predictions) {
        if (!mounted) return;
        setState(() => _predictions = predictions);
      },
      loadingListener: (isLoading) {
        if (!mounted) return;
        setState(() => _searching = isLoading);
      },
    );
    _places = places;

    places.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _placesReady = true;
        _placesInitError = null;
      });
      final q = _searchController.text.trim();
      if (q.isNotEmpty) {
        places.getPredictions(q);
      }
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _placesReady = false;
        _placesInitError = 'init_failed';
      });
    });
  }


  Set<Marker> get _markers => {
        Marker(
          markerId: const MarkerId('dealership_pin'),
          position: _markerPosition,
          draggable: true,
          onDragEnd: (p) => setState(() => _markerPosition = p),
        ),
      };

  Future<void> _onMapCreated(GoogleMapController c) async {
    _mapController = c;
    await c.animateCamera(
      CameraUpdate.newLatLngZoom(_markerPosition, 15),
    );
  }

  Future<void> _searchPlace({bool openKeyboard = false}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _predictions = const []);
      return;
    }
    if (openKeyboard) {
      _searchFocusNode.requestFocus();
    }
    if (!_placesReady) {
      if (!mounted) return;
      final msg = _placesInitError == null
          ? _tr(
              'Search is still loading. Please try again in a moment.',
              ar: 'لا يزال البحث قيد التحميل. يرجى المحاولة بعد قليل.',
              ku: 'گەڕان هێشتا بار دەبێت. تکایە دواتر هەوڵ بدەوە.',
            )
          : _tr(
              'Search is unavailable right now. Please try again.',
              ar: 'البحث غير متاح حالياً. يرجى المحاولة مرة أخرى.',
              ku: 'گەڕان لەم کاتەدا بەردەست نییە. تکایە دووبارە هەوڵبدەوە.',
            );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    _lastExplicitSearchQuery = query;
    _places!.getPredictions(query);

    // If Places returns nothing (common when Places API isn't enabled or billing is off),
    // show a helpful hint after a short delay.
    Future<void>.delayed(const Duration(milliseconds: 1100)).then((_) {
      if (!mounted) return;
      if (_searchController.text.trim() != _lastExplicitSearchQuery) return;
      if (_searching) return;
      if (_predictions.isNotEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'No results. If this keeps happening, enable the Places API for your key (and ensure billing / restrictions allow Places).',
              ar: 'لا توجد نتائج. إذا استمرت المشكلة، فعّل Places API للمفتاح وتأكد من الفوترة وصلاحيات القيود.',
              ku: 'هیچ ئەنجامێک نەدۆزرایەوە. ئەگەر بەردەوام بوو، Places API بۆ key ـەکەت چالاک بکە و دڵنیابە لە billing و قەیدەکان.',
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
    });
  }

  Future<void> _pickPrediction(Prediction p) async {
    final placeId = p.placeId;
    if (placeId == null || placeId.isEmpty) return;
    if (!_placesReady) return;

    setState(() => _searching = true);
    try {
      final details = await _places!.getPlaceDetails(placeId);
      final lat = details?.location?.lat;
      final lng = details?.location?.lng;
      if (!mounted) return;
      if (lat == null || lng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr('Could not get place coordinates.', ar: 'تعذر جلب إحداثيات المكان.', ku: 'نەتوانرا کۆئۆردیناتەکانی شوێن وەربگیرێت.'))),
        );
        setState(() => _searching = false);
        return;
      }

      final pos = LatLng(lat, lng);
      setState(() {
        _markerPosition = pos;
        _predictions = const [];
        _searching = false;
      });
      _searchFocusNode.unfocus();
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 15));
    } catch (e, st) { logNonFatal(e, st); 
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Search failed. Please try again.',
              ar: 'فشل البحث. يرجى المحاولة مرة أخرى.',
              ku: 'گەڕان شکستی هێنا. تکایە دووبارە هەوڵبدەوە.',
            ),
          ),
        ),
      );
    }
  }

  void _confirmFromMap() {
    Navigator.pop<Map<String, double>>(
      context,
      {'lat': _markerPosition.latitude, 'lng': _markerPosition.longitude},
    );
  }
}
