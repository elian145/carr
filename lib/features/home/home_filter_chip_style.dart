import 'package:flutter/material.dart';

/// Icon for home filter chips keyed by body type.
IconData homeFilterBodyTypeIcon(String bodyType) {
  switch (bodyType.toLowerCase()) {
    case 'suv':
      return Icons.directions_car_filled;
    case 'pickup':
      return Icons.local_shipping;
    case 'van':
    case 'minivan':
      return Icons.airport_shuttle;
    case 'motorcycle':
      return Icons.motorcycle;
    default:
      return Icons.directions_car;
  }
}

/// Swatch for home filter chips keyed by color name.
Color homeFilterNamedColor(String colorName) {
  switch (colorName.toLowerCase()) {
    case 'black':
      return Colors.black;
    case 'white':
      return Colors.white;
    case 'silver':
      return Colors.grey[300]!;
    case 'gray':
      return Colors.grey[600]!;
    case 'red':
      return Colors.red;
    case 'blue':
      return Colors.blue;
    case 'green':
      return Colors.green;
    case 'yellow':
      return Colors.yellow;
    case 'orange':
      return Colors.orange;
    case 'purple':
      return Colors.purple;
    case 'brown':
      return Colors.brown;
    case 'beige':
      return const Color(0xFFF5F5DC);
    case 'gold':
      return const Color(0xFFFFD700);
    default:
      return Colors.grey;
  }
}
