import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_places_autocomplete/google_places_autocomplete.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/app_localizations.dart';
import '../shared/maps/dealer_map_coords.dart';
import '../shared/debug/app_log.dart';

/// Default map center (Baghdad) when the dealer has no saved pin yet.

part 'dealer_location_picker_page_fields.dart';
part 'dealer_location_picker_page_load.dart';
part 'dealer_location_picker_page_core.dart';



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

class _DealerLocationPickerPageState extends _DealerLocationPickerPageFields
    with _DealerLocationPickerPageLoad, _DealerLocationPickerPageCore {}
