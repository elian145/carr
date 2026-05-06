import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_places_autocomplete/google_places_autocomplete.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/app_localizations.dart';
import '../shared/maps/dealer_map_coords.dart';

/// Default map center (Baghdad) when the dealer has no saved pin yet.
const LatLng _kDefaultMapCenter = LatLng(33.3152, 44.3661);

/// Full-screen map: tap or drag the pin, then confirm.
class DealerLocationPickerPage extends StatefulWidget {
  const DealerLocationPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<DealerLocationPickerPage> createState() => _DealerLocationPickerPageState();
}

class _DealerLocationPickerPageState extends State<DealerLocationPickerPage> {
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
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _placesReady = false;
        _placesInitError = e.toString();
      });
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _places?.dispose();
    super.dispose();
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
              'Search unavailable: ${_placesInitError!}',
              ar: 'البحث غير متاح: ${_placesInitError!}',
              ku: 'گەڕان بەردەست نییە: ${_placesInitError!}',
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Search failed: $e', ar: 'فشل البحث: $e', ku: 'گەڕان شکستی هێنا: $e'))),
      );
    }
  }

  void _confirmFromMap() {
    Navigator.pop<Map<String, double>>(
      context,
      {'lat': _markerPosition.latitude, 'lng': _markerPosition.longitude},
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: Text(_tr('Map location', ar: 'موقع الخريطة', ku: 'شوێنی نەخشە'))),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              _tr(
                'The in-app map picker is available on Android and iOS. On web, set latitude and longitude in the edit form, or open Google Maps in your browser to copy coordinates.',
                ar: 'محدد الموقع داخل التطبيق متاح على Android و iOS. على الويب، أدخل خط العرض وخط الطول في نموذج التعديل أو افتح خرائط Google في المتصفح لنسخ الإحداثيات.',
                ku: 'هەڵبژێرەری شوێنی ناو ئەپ لە Android و iOS بەردەستە. لە وێبدا، لاتیتوود و لۆنگیتوود لە فۆڕمی دەستکاریکردندا دابنێ یان نەخشەی گووگڵ لە وێبگەڕەکەت بکەرەوە بۆ کۆپیکردنی کۆئۆردینات.',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Pin dealership location', ar: 'تثبيت موقع المعرض', ku: 'پینی شوێنی نمایشگا')),
        actions: [
          TextButton(
            onPressed: _confirmFromMap,
            child: Text(_tr('USE THIS PIN', ar: 'استخدم هذا الدبوس', ku: 'ئەم پینە بەکاربهێنە')),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _markerPosition,
              zoom: 15,
            ),
            markers: _markers,
            onMapCreated: _onMapCreated,
            onTap: (p) => setState(() => _markerPosition = p),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                      child: Row(
                        children: [
                          const Icon(Icons.search_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _searchPlace(),
                              decoration: InputDecoration(
                                hintText: _tr('Search in Google Maps', ar: 'ابحث في خرائط Google', ku: 'لە نەخشەی گووگڵ بگەڕێ'),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          if (_searchController.text.trim().isNotEmpty)
                            IconButton(
                              tooltip: _tr('Clear', ar: 'مسح', ku: 'پاککردنەوە'),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _predictions = const []);
                              },
                              icon: const Icon(Icons.close),
                            ),
                          FilledButton(
                            onPressed: (_searching || !_placesReady)
                                ? null
                                : () => _searchPlace(),
                            child: _searching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _placesReady
                                        ? _tr('Search', ar: 'بحث', ku: 'گەڕان')
                                        : _tr('Loading', ar: 'جارٍ التحميل', ku: 'بار دەبێت'),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_placesReady) ...[
                    const SizedBox(height: 8),
                    Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Row(
                          children: [
                            if (_placesInitError == null) ...[
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(_tr('Loading Google Maps search...', ar: 'جارٍ تحميل بحث خرائط Google...', ku: 'بارکردنی گەڕانی نەخشەی گووگڵ...')),
                              ),
                            ] else ...[
                              const Icon(Icons.warning_amber_rounded),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _tr(
                                    'Search unavailable. Check Places API + billing/key restrictions.',
                                    ar: 'البحث غير متاح. تحقق من Places API والفوترة وقيود المفتاح.',
                                    ku: 'گەڕان بەردەست نییە. Places API و billing و قەیدەکانی key بپشکنە.',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              TextButton(
                                onPressed: _initPlaces,
                                child: Text(AppLocalizations.of(context)?.retryAction ?? 'Retry'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_predictions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Material(
                      elevation: 3,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      color: Theme.of(context).colorScheme.surface,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _predictions.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final p = _predictions[i];
                            return ListTile(
                              leading:
                                  const Icon(Icons.place_outlined, size: 22),
                              title: Text(
                                (p.title ?? '').trim().isEmpty
                                    ? (p.description ?? _tr('Result', ar: 'نتيجة', ku: 'ئەنجام'))
                                    : p.title!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: (p.description ?? '').trim().isEmpty
                                  ? null
                                  : Text(
                                      p.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () => _pickPrediction(p),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _confirmFromMap,
        icon: const Icon(Icons.check),
        label: Text(_tr('Save pin', ar: 'حفظ الدبوس', ku: 'پاشەکەوتکردنی پین')),
      ),
    );
  }
}
