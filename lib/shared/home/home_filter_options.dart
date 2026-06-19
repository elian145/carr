/// Static filter option lists aligned with legacy home / sell flow.
class HomeFilterOptions {
  HomeFilterOptions._();

  static const String any = 'Any';

  static const List<String> cities = [
    any,
    'Baghdad',
    'Basra',
    'Erbil',
    'Najaf',
    'Karbala',
    'Kirkuk',
    'Mosul',
    'Sulaymaniyah',
    'Dohuk',
    'Anbar',
    'Halabja',
    'Diyala',
    'Diyarbakir',
    'Maysan',
    'Muthanna',
    'Dhi Qar',
    'Salaheldeen',
  ];

  static const List<String> conditions = [any, 'New', 'Used'];
  static const List<String> transmissions = [any, 'Automatic', 'Manual'];
  static const List<String> fuelTypes = [
    any,
    'Gasoline',
    'Diesel',
    'Electric',
    'Hybrid',
    'Plug-in Hybrid',
  ];
  static const List<String> bodyTypes = [
    any,
    'Sedan',
    'SUV',
    'Hatchback',
    'Coupe',
    'Convertible',
    'Wagon',
    'Pickup',
    'Van',
    'Minivan',
  ];
  static const List<String> colors = [
    any,
    'Black',
    'White',
    'Silver',
    'Gray',
    'Red',
    'Blue',
    'Green',
    'Yellow',
    'Orange',
    'Purple',
    'Brown',
    'Beige',
    'Gold',
  ];
  static const List<String> driveTypes = [any, 'FWD', 'RWD', 'AWD', '4WD'];
  static const List<String> plateTypes = [
    any,
    'Private',
    'Commercial',
    'Taxi',
    'Government',
    'Temporary',
    'Diplomatic',
    'Police',
  ];
  static const List<String> titleStatuses = [any, 'clean', 'damaged'];

  static List<String> cylinderCounts() =>
      [any, ...List.generate(16, (i) => '${i + 1}')];

  static List<String> seatings() =>
      [any, ...List.generate(50, (i) => '${i + 1}')];

  static String? fromDropdown(String? value) {
    if (value == null || value.isEmpty || value == any) return null;
    return value;
  }

  static String toDropdown(String? value) {
    if (value == null || value.isEmpty) return any;
    return value;
  }
}
