import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
