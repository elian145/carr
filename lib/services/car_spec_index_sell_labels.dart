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

String sellFlowBodyLabel(String api) {
  switch (api.toLowerCase()) {
    case 'suv':
      return 'SUV';
    case 'hatchback':
      return 'Hatchback';
    case 'coupe':
      return 'Coupe';
    case 'pickup':
      return 'Pickup';
    case 'van':
      return 'Van';
    default:
      return 'Sedan';
  }
}

String sellFlowDriveLabel(String api) {
  switch (api.toLowerCase()) {
    case 'rwd':
      return 'RWD';
    case 'awd':
      return 'AWD';
    case '4wd':
      return '4WD';
    default:
      return 'FWD';
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
