/// Normalizes a brand display name into the slug used for static logo URLs.
String sellBrandSlug(String brand) {
  String s = brand.toLowerCase().trim();
  const replacements = {
    'Ã¡': 'a',
    'Ã ': 'a',
    'Ã¢': 'a',
    'Ã¤': 'a',
    'Ã£': 'a',
    'Ã¥': 'a',
    'Ã©': 'e',
    'Ã¨': 'e',
    'Ãª': 'e',
    'Ã«': 'e',
    'Ã­': 'i',
    'Ã¬': 'i',
    'Ã®': 'i',
    'Ã¯': 'i',
    'Ã³': 'o',
    'Ã²': 'o',
    'Ã´': 'o',
    'Ã¶': 'o',
    'Ãµ': 'o',
    'Ã¸': 'o',
    'Ãº': 'u',
    'Ã¹': 'u',
    'Ã»': 'u',
    'Ã¼': 'u',
    'Ã½': 'y',
    'Ã¿': 'y',
    'Ã±': 'n',
    'Ã§': 'c',
    'Ä': 'c',
    'Ä‡': 'c',
    'Å¡': 's',
    'ÃŸ': 'ss',
    'Å¾': 'z',
    'Å“': 'oe',
    'Ã¦': 'ae',
    'Ä‘': 'd',
    'Å‚': 'l',
  };
  replacements.forEach((k, v) {
    s = s.replaceAll(k, v);
  });
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  s = s.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'(^-|-$)'), '');
  return s;
}
