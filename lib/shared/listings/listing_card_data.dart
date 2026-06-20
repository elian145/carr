import 'package:flutter/widgets.dart';

import '../i18n/locale_formatting.dart';
import '../text/pretty_title_case.dart';
/// Normalizes API listing / favorite payloads into the shape expected by listing cards.
Map<String, dynamic> mapListingToGlobalCarCardData(
  BuildContext context,
  Map<String, dynamic> listing,
) {
  final String brand = (listing['brand'] ?? '').toString().trim();
  final String model = (listing['model'] ?? '').toString().trim();
  final String yearStr = (listing['year']?.toString() ?? '').trim();
  final String apiTitle = (listing['title'] ?? '').toString().trim();
  String displayTitle;
  if (apiTitle.isNotEmpty) {
    displayTitle = apiTitle;
  } else {
    final String base = [
      if (brand.isNotEmpty) prettyTitleCase(brand),
      if (model.isNotEmpty) prettyTitleCase(model),
    ].join(' ');
    displayTitle = yearStr.isNotEmpty ? ('$base ($yearStr)') : base;
  }
  displayTitle = prettyTitleCase(displayTitle);

  final num? mileageNum = () {
    final v = listing['mileage'];
    if (v == null) return null;
    if (v is num) return v;
    final s = v.toString().replaceAll(RegExp(r'[^0-9.-]'), '');
    return num.tryParse(s);
  }();
  final formatter = decimalFormatterForLocale(context);
  final String mileageFormatted = mileageNum == null
      ? (listing['mileage']?.toString() ?? '')
      : formatter.format(mileageNum);

  final String carId =
      (listing['public_id'] ?? listing['id'] ?? listing['car_id'] ?? '')
          .toString();

  return {
    'id': carId,
    'brand': brand,
    'model': model,
    'trim': listing['trim'],
    'title': displayTitle,
    'price': listing['price'],
    'year': listing['year'],
    'mileage': mileageFormatted,
    'city': listing['city'] ?? listing['location'] ?? listing['city_name'],
    'image_url': listing['image_url'],
    'images': listing['images'],
    'videos': listing['videos'],
    'is_quick_sell': listing['is_quick_sell'] ?? false,
    'status': listing['status'],
    'created_at': listing['created_at'],
  };
}
