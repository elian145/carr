import '../../data/brand_logo_filenames.dart';

/// Normalizes a brand display name into the slug used for static logo URLs.
///
/// Prefer [brandLogoSlug] for new call sites; this remains as a thin alias
/// for sell-flow imports/tests.
String sellBrandSlug(String brand) => brandLogoSlug(brand);
