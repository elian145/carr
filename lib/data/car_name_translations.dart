import 'package:flutter/widgets.dart';

/// Arabic and Kurdish names for car brands and common models.
/// Keys are lowercase English; lookup is case-insensitive.
class CarNameTranslations {
  CarNameTranslations._();

  static const Map<String, String> _brandAr = {
    'acura': 'أكورا',
    'aston martin': 'أستون مارتن',
    'audi': 'أودي',
    'bentley': 'بنتلي',
    'bmw': 'بي إم دبليو',
    'buick': 'بويك',
    'cadillac': 'كاديلاك',
    'chevrolet': 'شفروليه',
    'chrysler': 'كرايسلر',
    'citroën': 'سيتروين',
    'dodge': 'دودج',
    'ferrari': 'فيراري',
    'ford': 'فورد',
    'genesis': 'جنسيس',
    'gmc': 'جي إم سي',
    'honda': 'هوندا',
    'hyundai': 'هيونداي',
    'infiniti': 'إنفينيتي',
    'jaguar': 'جاكوار',
    'jeep': 'جيب',
    'kia': 'كيا',
    'lamborghini': 'لامبورغيني',
    'land rover': 'لاند روفر',
    'lexus': 'لكزس',
    'lincoln': 'لينكولن',
    'maserati': 'مازيراتي',
    'mazda': 'مازدا',
    'mercedes-benz': 'مرسيدس-بنز',
    'mercedes maybach': 'مرسيدس مايباخ',
    'mini': 'ميني',
    'mitsubishi': 'ميتسوبيشي',
    'nissan': 'نيسان',
    'peugeot': 'بيجو',
    'porsche': 'بورش',
    'ram': 'رام',
    'renault': 'رينو',
    'rolls-royce': 'رولز رويس',
    'skoda': 'سكودا',
    'subaru': 'سوبارو',
    'suzuki': 'سوزوكي',
    'tesla': 'تسلا',
    'toyota': 'تويوتا',
    'volkswagen': 'فولكس واجن',
    'volvo': 'فولفو',
  };

  static const Map<String, String> _brandKu = {
    'acura': 'ئەکیورا',
    'aston martin': 'ئاستۆن مارتن',
    'audi': 'ئۆدی',
    'bentley': 'بێنتلی',
    'bmw': 'بی ئێم دەبڵیو',
    'buick': 'بوویک',
    'cadillac': 'کادیلاک',
    'chevrolet': 'شێڤرۆلێ',
    'chrysler': 'کرایسلەر',
    'citroën': 'سیترۆین',
    'dodge': 'دۆدج',
    'ferrari': 'فێراری',
    'ford': 'فۆرد',
    'genesis': 'جێنەسیس',
    'gmc': 'جی ئێم سی',
    'honda': 'هۆندا',
    'hyundai': 'هایووندای',
    'infiniti': 'ئینفینیتی',
    'jaguar': 'جاکوار',
    'jeep': 'جیپ',
    'kia': 'کیا',
    'lamborghini': 'لامبۆرگینی',
    'land rover': 'لاند ڕۆڤەر',
    'lexus': 'لێکسەس',
    'lincoln': 'لینکۆڵن',
    'maserati': 'ماسێراتی',
    'mazda': 'مازدا',
    'mercedes-benz': 'مێرسیدس-بێنز',
    'mercedes maybach': 'مێرسیدس مایباخ',
    'mini': 'مینی',
    'mitsubishi': 'میتسوبیشی',
    'nissan': 'نیسان',
    'peugeot': 'پێژۆ',
    'porsche': 'پۆرسش',
    'ram': 'ڕام',
    'renault': 'رینۆ',
    'rolls-royce': 'ڕۆڵز ڕۆیس',
    'skoda': 'سکۆدا',
    'subaru': 'سوبارو',
    'suzuki': 'سوزوکی',
    'tesla': 'تێسلا',
    'toyota': 'تۆیۆتا',
    'volkswagen': 'فۆڵکسڤاگن',
    'volvo': 'ڤۆڵڤۆ',
  };

  /// Model translations: key "brand|model" lowercase.
  static const Map<String, String> _modelAr = {
    'toyota|camry': 'كامري',
    'toyota|corolla': 'كورولا',
    'toyota|land cruiser': 'لاند كروزر',
    'toyota|prado': 'برادو',
    'toyota|rav4': 'آر إيه في 4',
    'toyota|hilux': 'هايلكس',
    'toyota|yaris': 'ياريس',
    'toyota|avalon': 'أفالون',
    'toyota|highlander': 'هايلاندر',
    'toyota|4runner': 'فور رنر',
    'toyota|sequoia': 'سيكويا',
    'toyota|tacoma': 'تاكوما',
    'toyota|tundra': 'تندرا',
    'toyota|prius': 'بريوس',
    'honda|civic': 'سيفيك',
    'honda|accord': 'أكورد',
    'honda|cr-v': 'سي آر-في',
    'honda|pilot': 'بايلوت',
    'hyundai|elantra': 'إلنترا',
    'hyundai|sonata': 'سوناتا',
    'hyundai|tucson': 'توسان',
    'hyundai|santa fe': 'سانتا في',
    'hyundai|palisade': 'باليسيد',
    'kia|sportage': 'سبورتاج',
    'kia|sorento': 'سورينتو',
    'kia|telluride': 'تيلورايد',
    'kia|optima': 'أوبتيما',
    'kia|k5': 'كاي 5',
    'nissan|altima': 'ألتيما',
    'nissan|maxima': 'ماكسيما',
    'nissan|rogue': 'روغ',
    'nissan|patrol': 'باترول',
    'nissan|xtrail': 'اكس ترايل',
    'ford|f-150': 'إف-150',
    'ford|mustang': 'موستانج',
    'ford|explorer': 'إكسبلورر',
    'chevrolet|silverado': 'سيلفرادو',
    'chevrolet|tahoe': 'تاهو',
    'chevrolet|camaro': 'كامارو',
    'bmw|3 series': 'سيريز 3',
    'bmw|5 series': 'سيريز 5',
    'bmw|x5': 'إكس 5',
    'mercedes-benz|c-class': 'فئة سي',
    'mercedes-benz|e-class': 'فئة إي',
    'mercedes-benz|s-class': 'فئة إس',
    'audi|a3': 'إيه 3',
    'audi|a4': 'إيه 4',
    'audi|q5': 'كيو 5',
    'audi|q7': 'كيو 7',
    'bentley|bentayga': 'بنتايغا',
    'bentley|continental': 'كونتيننتال',
    'cadillac|ct4': 'سي تي 4',
    'cadillac|ct5': 'سي تي 5',
    'cadillac|escalade': 'إسكاليد',
    'lexus|rx': 'آر إكس',
    'lexus|lx': 'إل إكس',
    'lexus|es': 'إي إس',
    'lexus|ls': 'إل إس',
  };

  static const Map<String, String> _modelKu = {
    'toyota|camry': 'کامری',
    'toyota|corolla': 'کۆرۆلا',
    'toyota|land cruiser': 'لاند کروزەر',
    'toyota|prado': 'پرادۆ',
    'toyota|rav4': 'ڕەی ڤی ٤',
    'toyota|hilux': 'هایلەکس',
    'toyota|yaris': 'یاریس',
    'toyota|avalon': 'ئەڤالۆن',
    'toyota|highlander': 'هایلاندەر',
    'toyota|4runner': 'فۆر ڕانەر',
    'toyota|prius': 'پرایەس',
    'honda|civic': 'سیڤیک',
    'honda|accord': 'ئەکۆرد',
    'honda|cr-v': 'سی ئار ڤی',
    'hyundai|elantra': 'ئێلانترا',
    'hyundai|sonata': 'سۆناتا',
    'hyundai|tucson': 'تووسۆن',
    'hyundai|santa fe': 'سانتا فێ',
    'kia|sportage': 'سبۆرتاج',
    'kia|sorento': 'سۆرێنتۆ',
    'kia|telluride': 'تێلۆراید',
    'nissan|altima': 'ئەلتیما',
    'nissan|patrol': 'پاترۆڵ',
    'ford|f-150': 'ئێف-150',
    'ford|mustang': 'مۆستەنگ',
    'bmw|3 series': 'سیریز ٣',
    'bmw|5 series': 'سیریز ٥',
    'bmw|x5': 'ئێکس ٥',
    'mercedes-benz|c-class': 'پۆلینی سی',
    'mercedes-benz|e-class': 'پۆلینی ئی',
    'audi|a3': 'ئەی ٣',
    'audi|a4': 'ئەی ٤',
    'audi|q5': 'کیو ٥',
    'bentley|bentayga': 'بێنتایگا',
    'cadillac|ct4': 'سی تی ٤',
    'cadillac|escalade': 'ئێسکالەید',
    'lexus|rx': 'ئار ئێکس',
    'lexus|lx': 'ئێل ئێکس',
  };

  static String _key(String s) => (s ?? '').trim().toLowerCase();

  static String getLocalizedBrand(BuildContext context, String? brand) {
    if (brand == null || brand.isEmpty) return '';
    final k = _key(brand);
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'ar') return _brandAr[k] ?? brand;
    if (locale == 'ku') return _brandKu[k] ?? brand;
    return brand;
  }

  static String getLocalizedModel(BuildContext context, String? brand, String? model) {
    if (model == null || model.isEmpty) return '';
    final key = '${_key(brand)}|${_key(model)}';
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'ar') return _modelAr[key] ?? model;
    if (locale == 'ku') return _modelKu[key] ?? model;
    return model;
  }

  /// Returns localized "Brand Model" or "Brand Model Trim" for display.
  static String getLocalizedCarTitle(BuildContext context, Map<String, dynamic>? car) {
    if (car == null) return '';
    final brand = car['brand']?.toString().trim() ?? '';
    final model = car['model']?.toString().trim() ?? '';
    final trim = car['trim']?.toString().trim();
    final year = car['year']?.toString().trim();

    final locBrand = getLocalizedBrand(context, brand.isEmpty ? null : brand);
    final locModel = getLocalizedModel(context, brand.isEmpty ? null : brand, model.isEmpty ? null : model);
    final parts = <String>[locBrand, locModel];
    if (trim != null && trim.isNotEmpty) {
      // Trim can use _translateValueGlobal in caller if needed (Base, Sport, etc.)
      parts.add(trim);
    }
    var title = parts.join(' ').trim();
    if (year != null && year.isNotEmpty) {
      title = '$title $year'.trim();
    }
    return title.isEmpty ? (car['title']?.toString() ?? '') : title;
  }

  /// Brand + model only (no trim, no year). Caller can append translated trim.
  static String getLocalizedCarTitleNoYear(BuildContext context, Map<String, dynamic>? car) {
    if (car == null) return '';
    final brand = car['brand']?.toString().trim() ?? '';
    final model = car['model']?.toString().trim() ?? '';

    final locBrand = getLocalizedBrand(context, brand.isEmpty ? null : brand);
    final locModel = getLocalizedModel(context, brand.isEmpty ? null : brand, model.isEmpty ? null : model);
    final title = [locBrand, locModel].join(' ').trim();
    return title.isEmpty ? (car['title']?.toString() ?? '') : title;
  }
}
