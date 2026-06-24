part of 'car_details_page.dart';

mixin _CarDetailsPageTitles on _CarDetailsPageFields {
  void _onListingLayoutChanged() {
    if (!mounted) return;
    setState(() {
      _listingColumnsPref = ListingLayoutPrefs.columns.value;
    });
  }

  String _displayCarTitle(BuildContext context) {
    if (car == null) return '';
    final brand = (car!['brand'] ?? '').toString().trim();
    final model = (car!['model'] ?? '').toString().trim();
    final year = (car!['year'] ?? '').toString().trim();
    final trim = (car!['trim'] ?? '').toString().trim();

    final locBrand = CarNameTranslations.getLocalizedBrand(
      context,
      brand.isEmpty ? null : brand,
    );
    final locModel = CarNameTranslations.getLocalizedModel(
      context,
      brand.isEmpty ? null : brand,
      model.isEmpty ? null : model,
    );
    final parts = <String>[];
    if (locBrand.isNotEmpty) parts.add(locBrand);
    if (locModel.isNotEmpty) parts.add(locModel);
    if (trim.isNotEmpty && trim.toLowerCase() != 'base') {
      parts.add(trim);
    }
    if (year.isNotEmpty) parts.add(year);
    final title = parts.join(' ').trim();
    final raw = title.isNotEmpty ? title : ((car!['title'] ?? '').toString().trim());
    return prettyTitleCase(raw);
  }

  String _displayBrandName(BuildContext context) {
    if (car == null) return '';
    final brand = (car!['brand'] ?? '').toString().trim();
    final locBrand = CarNameTranslations.getLocalizedBrand(
      context,
      brand.isEmpty ? null : brand,
    );
    if (locBrand.isNotEmpty) return prettyTitleCase(locBrand);
    return prettyTitleCase(brand.isNotEmpty ? brand : (car!['title'] ?? '').toString().trim());
  }

  String _displayModelName(BuildContext context) {
    if (car == null) return '';
    final brand = (car!['brand'] ?? '').toString().trim();
    final model = (car!['model'] ?? '').toString().trim();
    final year = (car!['year'] ?? '').toString().trim();

    final locModel = CarNameTranslations.getLocalizedModel(
      context,
      brand.isEmpty ? null : brand,
      model.isEmpty ? null : model,
    );
    final raw = [
      if (locModel.isNotEmpty) locModel else model,
      if (year.isNotEmpty) year,
    ].join(' ').trim();
    return prettyTitleCase(raw);
  }
}
