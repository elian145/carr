import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../shared/maps/ios_google_maps_config.dart';

/// Read-only mini map with a transparent tap layer to open external maps.
class DealerLocationMapPreview extends StatefulWidget {
  const DealerLocationMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onOpenInGoogleMaps,
    this.height = 200,
  });

  final double latitude;
  final double longitude;
  final VoidCallback onOpenInGoogleMaps;
  final double height;

  @override
  State<DealerLocationMapPreview> createState() => _DealerLocationMapPreviewState();
}

class _DealerLocationMapPreviewState extends State<DealerLocationMapPreview>
    with WidgetsBindingObserver {
  int _iosProbeGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isIOS) {
      resetIosGoogleMapsSdkConfiguredCache();
      setState(() => _iosProbeGeneration++);
    }
  }

  Widget _fallbackNoSdk(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onOpenInGoogleMaps,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                const Text('Open in Google Maps'),
                const SizedBox(height: 4),
                Text(
                  '${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'If the map does not load: fully quit the app, run flutter clean, '
                    'rebuild, and ensure GMSApiKey is set in Info-Debug.plist (Debug).',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _googleMapStack(BuildContext context) {
    final target = LatLng(widget.latitude, widget.longitude);
    final lite = !kIsWeb && Platform.isAndroid;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: target, zoom: 15),
              markers: {
                Marker(
                  markerId: const MarkerId('dealer_preview'),
                  position: target,
                ),
              },
              liteModeEnabled: lite,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
            Material(
              color: Colors.black.withOpacity(0.03),
              child: InkWell(
                onTap: widget.onOpenInGoogleMaps,
                child: const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xE6FFFFFF),
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new, size: 18),
                          SizedBox(width: 8),
                          Text('Open in Google Maps'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _fallbackNoSdk(context);
    }

    if (Platform.isIOS) {
      return FutureBuilder<bool>(
        key: ValueKey<int>(_iosProbeGeneration),
        future: isIosGoogleMapsSdkConfigured(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return SizedBox(
              height: widget.height,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data != true) {
            return _fallbackNoSdk(context);
          }
          return _googleMapStack(context);
        },
      );
    }

    return _googleMapStack(context);
  }
}
