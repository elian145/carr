import '../../models/online_spec_variant.dart';
import '../../shared/i18n/region_spec_labels.dart';

Map<String, dynamic> buildSellCarUpdatePayload(Map<String, dynamic> carData) {
  final brand = carData['brand']?.toString() ?? '';
  final model = carData['model']?.toString() ?? '';
  final trim = carData['trim']?.toString() ?? 'Base';
  final year =
      int.tryParse(carData['year']?.toString() ?? '') ?? DateTime.now().year;
  final mileage = int.tryParse(carData['mileage']?.toString() ?? '0') ?? 0;
  final condition =
      (carData['condition']?.toString() ?? 'used').toLowerCase();
  final transmission =
      (carData['transmission']?.toString() ?? 'automatic').toLowerCase();
  final fuelType =
      (carData['fuel_type']?.toString() ?? 'gasoline').toLowerCase();
  final color = (carData['color']?.toString() ?? 'black').toLowerCase();
  final bodyType = (carData['body_type']?.toString() ?? 'sedan').toLowerCase();
  final seating = int.tryParse(carData['seating']?.toString() ?? '5') ?? 5;
  final driveType = (carData['drive_type']?.toString() ?? 'fwd').toLowerCase();
  final regionSpecsRaw =
      carData['region_specs']?.toString().trim().toLowerCase() ?? '';
  final regionSpecs =
      isValidCarRegionSpecCode(regionSpecsRaw) ? regionSpecsRaw : null;
  final titleStatus =
      (carData['title_status']?.toString() ?? 'clean').toLowerCase();
  final damagedParts = titleStatus == 'damaged'
      ? int.tryParse(carData['damaged_parts']?.toString() ?? '')
      : null;
  final cylinderCount = int.tryParse(
    carData['cylinder_count']?.toString() ?? '',
  );
  final engineSizeRaw = (carData['engine_size']?.toString() ?? '').trim();
  final engineSize = OnlineSpecVariant.parseLeadingEngineLiters(engineSizeRaw) ??
      double.tryParse(engineSizeRaw);
  final priceStr = (carData['price']?.toString() ?? '').replaceAll(
    RegExp(r'[^0-9\.-]'),
    '',
  );
  final dynamic priceValue = priceStr.isEmpty
      ? null
      : (int.tryParse(priceStr) ?? double.tryParse(priceStr));
  final location = (carData['location']?.toString().trim().isNotEmpty == true)
      ? carData['location'].toString().trim()
      : (carData['city']?.toString().trim() ?? '');
  final plateType =
      (carData['plate_type']?.toString() ?? '').trim().toLowerCase();
  final plateCity = (carData['plate_city']?.toString() ?? '').trim();
  final fuelEconomy = (carData['fuel_economy']?.toString() ?? '').trim();
  final description = (carData['description']?.toString() ?? '').trim();

  return {
    'title': '$brand $model $trim'.trim(),
    'brand': brand.toLowerCase().replaceAll(' ', '-'),
    'model': model,
    'trim': trim,
    'year': year,
    'price': priceValue,
    'mileage': mileage,
    'condition': condition,
    'transmission': transmission,
    'engine_type': fuelType,
    'fuel_type': fuelType,
    'color': color,
    'body_type': bodyType,
    'seating': seating,
    'drive_type': driveType,
    'region_specs': regionSpecs,
    'title_status': titleStatus,
    'damaged_parts': damagedParts,
    'cylinder_count': cylinderCount,
    'engine_size': engineSize,
    'location': location,
    'plate_type': plateType.isNotEmpty ? plateType : null,
    'plate_city': plateCity.isNotEmpty ? plateCity : null,
    if (fuelEconomy.isNotEmpty) 'fuel_economy': fuelEconomy,
    if (description.isNotEmpty) 'description': description,
    if ((carData['vin']?.toString() ?? '').trim().isNotEmpty)
      'vin': carData['vin'].toString().trim(),
  }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
}

Map<String, dynamic> buildSellCarCreatePayload(Map<String, dynamic> carData) {
  final brand = carData['brand']?.toString() ?? '';
  final model = carData['model']?.toString() ?? '';
  final trim = carData['trim']?.toString() ?? 'Base';
  final year =
      int.tryParse(carData['year']?.toString() ?? '') ?? DateTime.now().year;
  final mileage = int.tryParse(carData['mileage']?.toString() ?? '0') ?? 0;
  final condition = (carData['condition']?.toString() ?? 'Used')
      .toLowerCase();
  final transmission = (carData['transmission']?.toString() ?? 'Automatic')
      .toLowerCase();
  final fuelType = (carData['fuel_type']?.toString() ?? 'Gasoline')
      .toLowerCase();
  final color = (carData['color']?.toString() ?? 'Black').toLowerCase();
  final bodyType = (carData['body_type']?.toString() ?? 'Sedan')
      .toLowerCase();
  final seating = int.tryParse(carData['seating']?.toString() ?? '5') ?? 5;
  final driveType = (carData['drive_type']?.toString() ?? 'fwd')
      .toLowerCase();
  final regionSpecsRaw =
      carData['region_specs']?.toString().trim().toLowerCase() ?? '';
  final regionSpecs = isValidCarRegionSpecCode(regionSpecsRaw)
      ? regionSpecsRaw
      : null;
  final titleStatus = (carData['title_status']?.toString() ?? 'clean')
      .toLowerCase();
  final damagedParts = titleStatus == 'damaged'
      ? int.tryParse(carData['damaged_parts']?.toString() ?? '')
      : null;
  final cylinderCount = int.tryParse(
    carData['cylinder_count']?.toString() ?? '',
  );
  final String engineSizeRaw = (carData['engine_size']?.toString() ?? '').trim();
  final engineSize = OnlineSpecVariant.parseLeadingEngineLiters(engineSizeRaw) ??
      double.tryParse(engineSizeRaw);
  final price = int.tryParse(carData['price']?.toString() ?? '');
  final city = (carData['city']?.toString() ?? 'Baghdad').toLowerCase();
  final plateType =
      (carData['plate_type']?.toString() ?? '').trim().toLowerCase();
  final plateCity = (carData['plate_city']?.toString() ?? '').trim();
  final title = '$brand $model $trim'.trim();

  final String priceStr = (carData['price']?.toString() ?? '').replaceAll(
    RegExp(r'[^0-9\.-]'),
    '',
  );
  final dynamic priceValue = priceStr.isEmpty
      ? null
      : (int.tryParse(priceStr) ?? double.tryParse(priceStr) ?? price);
  final String engineType = fuelType;
  final String location = (carData['location']?.toString() ?? city)
      .toString();

  return {
    'title': title,
    'brand': brand.toLowerCase().replaceAll(' ', '-'),
    'model': model,
    'trim': trim,
    'year': year,
    'price': priceValue,
    'mileage': mileage,
    'condition': condition,
    'transmission': transmission,
    'engine_type': engineType.isNotEmpty ? engineType : null,
    'fuel_type': fuelType.isNotEmpty ? fuelType : null,
    'color': color,
    'body_type': bodyType,
    'seating': seating,
    'drive_type': driveType,
    'region_specs': regionSpecs,
    'title_status': titleStatus,
    'damaged_parts': damagedParts,
    'cylinder_count': cylinderCount,
    'engine_size': engineSize,
    'location': location,
    'city': city,
    'plate_type': plateType.isNotEmpty ? plateType : null,
    'plateType': plateType.isNotEmpty ? plateType : null,
    'plate_city': plateCity.isNotEmpty ? plateCity : null,
    'plateCity': plateCity.isNotEmpty ? plateCity : null,
    'contact_phone': (carData['contact_phone']?.toString() ?? '').trim(),
    'description': (carData['description']?.toString() ?? '').trim(),
    'is_quick_sell': carData['is_quick_sell'] ?? false,
    if ((carData['vin']?.toString() ?? '').trim().isNotEmpty)
      'vin': carData['vin'].toString().trim(),
  }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
}
