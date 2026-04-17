import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../shared/maps/dealer_map_coords.dart';
import '../shared/maps/ios_google_maps_config.dart';

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
  bool? _iosMapsOk;
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

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
    _latCtrl.text = _markerPosition.latitude.toString();
    _lngCtrl.text = _markerPosition.longitude.toString();

    if (Platform.isIOS) {
      isIosGoogleMapsSdkConfigured().then((ok) {
        if (mounted) setState(() => _iosMapsOk = ok);
      });
    } else {
      _iosMapsOk = true;
    }
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
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
    await c.animateCamera(
      CameraUpdate.newLatLngZoom(_markerPosition, 15),
    );
  }

  void _confirmFromMap() {
    Navigator.pop<Map<String, double>>(
      context,
      {'lat': _markerPosition.latitude, 'lng': _markerPosition.longitude},
    );
  }

  void _confirmFromFields() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid latitude and longitude numbers.')),
      );
      return;
    }
    if (!isValidDealerLatLng(lat, lng)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinates are out of range.')),
      );
      return;
    }
    Navigator.pop<Map<String, double>>(context, {'lat': lat, 'lng': lng});
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Map location')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'The in-app map picker is available on Android and iOS. '
              'On web, set latitude and longitude in the edit form, or open '
              'Google Maps in your browser to copy coordinates.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (Platform.isIOS && _iosMapsOk == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (Platform.isIOS && _iosMapsOk == false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pin dealership location')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Google Maps is not configured for this build (missing or placeholder '
              'GMSApiKey in Info.plist). Enter coordinates manually, or add your iOS Maps API key.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _latCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Latitude',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lngCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Longitude',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _confirmFromFields,
              icon: const Icon(Icons.check),
              label: const Text('Use these coordinates'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pin dealership location'),
        actions: [
          TextButton(
            onPressed: _confirmFromMap,
            child: const Text('USE THIS PIN'),
          ),
        ],
      ),
      body: GoogleMap(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _confirmFromMap,
        icon: const Icon(Icons.check),
        label: const Text('Save pin'),
      ),
    );
  }
}
