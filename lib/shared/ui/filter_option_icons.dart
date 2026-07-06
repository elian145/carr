import 'package:flutter/material.dart';

const IconData kFilterAnyOptionIcon = Icons.grid_view_rounded;

IconData filterDriveTypeIcon(String drive) {
  switch (drive) {
    case 'FWD':
      return Icons.arrow_circle_up_outlined;
    case 'RWD':
      return Icons.arrow_circle_down_outlined;
    case 'AWD':
      return Icons.sync_alt_rounded;
    default:
      return kFilterAnyOptionIcon;
  }
}

IconData filterFuelTypeIcon(String fuel) {
  switch (fuel) {
    case 'Electric':
      return Icons.electric_bolt_outlined;
    case 'Hybrid':
    case 'Plug-in Hybrid':
      return Icons.energy_savings_leaf_outlined;
    case 'Diesel':
      return Icons.local_gas_station_outlined;
    default:
      return Icons.local_gas_station_outlined;
  }
}

IconData filterTransmissionIcon(String transmission) {
  switch (transmission) {
    case 'Manual':
      return Icons.pan_tool_alt_outlined;
    default:
      return Icons.settings_outlined;
  }
}

IconData filterRegionSpecIcon(String code) {
  switch (code) {
    case 'us':
      return Icons.flag_outlined;
    case 'gcc':
      return Icons.mosque_outlined;
    case 'iraq':
      return Icons.location_city_outlined;
    case 'canada':
      return Icons.map_outlined;
    case 'eu':
      return Icons.euro_outlined;
    case 'cn':
      return Icons.language_outlined;
    case 'korea':
      return Icons.star_outline;
    case 'ru':
      return Icons.ac_unit_outlined;
    case 'iran':
      return Icons.public_outlined;
    default:
      return kFilterAnyOptionIcon;
  }
}

IconData filterPlateTypeIcon(String plateType) {
  switch (plateType) {
    case 'private':
      return Icons.directions_car_outlined;
    case 'temporary':
      return Icons.schedule_outlined;
    case 'commercial':
      return Icons.local_shipping_outlined;
    case 'taxi':
      return Icons.local_taxi_outlined;
    default:
      return kFilterAnyOptionIcon;
  }
}

IconData filterPlateCityIcon(String city) => Icons.location_on_outlined;
