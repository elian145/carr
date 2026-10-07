part of 'car_spec_index.dart';

String sellFlowTransmissionLabel(String api) {
  switch (api.toLowerCase()) {
    case 'manual':
      return 'Manual';
    default:
      return 'Automatic';
  }
}

String sellFlowFuelLabel(String api) {
  switch (api.toLowerCase()) {
    case 'diesel':
      return 'Diesel';
    case 'electric':
      return 'Electric';
    case 'hybrid':
      return 'Hybrid';
    default:
      return 'Gasoline';
  }
}

/// Display label of an app body key, or null for anything that is not an
/// explicit, known body key. There is deliberately NO default: an unknown or
/// blank value must never become Sedan (or any other factual spec).
String? sellFlowBodyLabel(String? api) {
  switch ((api ?? '').trim().toLowerCase()) {
    case 'sedan':
      return 'Sedan';
    case 'suv':
      return 'SUV';
    case 'hatchback':
      return 'Hatchback';
    case 'coupe':
      return 'Coupe';
    case 'pickup':
      return 'Pickup';
    case 'wagon':
      return 'Wagon';
    case 'convertible':
      return 'Convertible';
    case 'minivan':
      return 'Minivan';
    case 'van':
      return 'Van';
    default:
      return null;
  }
}

/// Display label of an app drivetrain key, or null for anything that is not an
/// explicit, known drivetrain key. There is deliberately NO default: an unknown
/// or blank value must never become FWD. `4wd` is CarNet's AWD (the Search/Sell
/// lists only offer FWD / RWD / AWD).
String? sellFlowDriveLabel(String? api) {
  switch ((api ?? '').trim().toLowerCase()) {
    case 'fwd':
      return 'FWD';
    case 'rwd':
      return 'RWD';
    case 'awd':
    case '4wd':
      return 'AWD';
    default:
      return null;
  }
}

const List<String> _kSellFlowSeatOptions = ['2', '4', '5', '6', '7', '8'];

String? sellFlowNearestSeatingLabel(int? seats) {
  if (seats == null || seats <= 0) return null;
  final s = '$seats';
  if (_kSellFlowSeatOptions.contains(s)) return s;
  if (seats <= 2) return '2';
  if (seats <= 4) return '4';
  if (seats <= 5) return '5';
  if (seats <= 6) return '6';
  if (seats <= 7) return '7';
  return '8';
}
