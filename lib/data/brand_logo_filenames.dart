// Brand logo filename slugs for static CDN paths:
// `{apiBase}/static/images/brands/{slug}.png`

/// Display-name → filename slug overrides (when the naive slug is wrong
/// or the file on disk uses a different name).
final Map<String, String> brandLogoFilenames = {
  'Acura': 'acura',
  'Alfa Romeo': 'alfa-romeo',
  'Aston Martin': 'aston-martin',
  'Audi': 'audi',
  'BAIC': 'baic',
  'Baic': 'baic',
  'Baojun': 'baojun',
  'Bentley': 'bentley',
  'BMW': 'bmw',
  'Bugatti': 'bugatti',
  'Buick': 'buick',
  'BYD': 'byd',
  'Cadillac': 'cadillac',
  'Changan': 'changan',
  'Chery': 'chery',
  'Chevrolet': 'chevrolet',
  'Chrysler': 'chrysler',
  'Citroën': 'citroen',
  'Dacia': 'dacia',
  'Daewoo': 'daewoo',
  'Dodge': 'dodge',
  'Dongfeng': 'dongfeng-motor',
  'FAW': 'faw',
  'Ferrari': 'ferrari',
  'Fiat': 'fiat',
  'Ford': 'ford',
  'Foton': 'foton',
  'GAC': 'gac',
  'Gac': 'gac',
  'Geely': 'geely-zgh',
  'Genesis': 'genesis',
  'GMC': 'gmc',
  'Great Wall': 'great-wall',
  'Gwm': 'great-wall',
  'Haval': 'haval',
  'Honda': 'honda',
  'Hyundai': 'hyundai',
  'Infiniti': 'infiniti',
  'Isuzu': 'isuzu',
  'JAC': 'jac-motors',
  'Jaguar': 'jaguar',
  'Jeep': 'jeep',
  'Jetour': 'jetour',
  'Kia': 'kia',
  'Koenigsegg': 'koenigsegg',
  'Lada': 'lada',
  'Lamborghini': 'lamborghini',
  'Land Rover': 'land-rover',
  'Leapmotor': 'leapmotor',
  'Lexus': 'lexus',
  'Li Auto': 'li-auto',
  'Lincoln': 'lincoln',
  'Lucid': 'lucid',
  'Mahindra': 'mahindra',
  'Maserati': 'maserati',
  'Mazda': 'mazda',
  'McLaren': 'mclaren',
  'Mercedes Maybach': 'mercedes-maybach',
  'Mercedes-Benz': 'mercedes-benz',
  'MG': 'mg',
  'Mg': 'mg',
  'Mini': 'mini',
  'Mitsubishi': 'mitsubishi',
  'Nio': 'nio',
  'Nissan': 'nissan',
  'Opel': 'opel',
  'Perodua': 'perodua',
  'Peugeot': 'peugeot',
  'Polestar': 'polestar',
  'Porsche': 'porsche',
  'Proton': 'proton',
  'RAM': 'ram',
  'Renault': 'renault',
  'Rivian': 'rivian',
  'Roewe': 'roewe',
  'Rolls-Royce': 'rolls-royce',
  'SAIC': 'saic',
  'SEAT': 'seat',
  'Škoda': 'skoda',
  'Smart': 'smart',
  'Soueast': 'soueast',
  'SsangYong': 'ssangyong',
  'Subaru': 'subaru',
  'Suzuki': 'suzuki',
  'Tata': 'tata',
  'Tesla': 'tesla',
  'Toyota': 'toyota',
  'Vauxhall': 'vauxhall',
  'VinFast': 'vinfast',
  'Volkswagen': 'volkswagen',
  'Volvo': 'volvo',
  'Wuling': 'wuling',
  'XPeng': 'xpeng',
  'ZAZ': 'zaz',
};

/// Naive-slug → on-disk filename when the file uses a longer/company name.
const Map<String, String> brandLogoSlugAliases = {
  'dongfeng': 'dongfeng-motor',
  'geely': 'geely-zgh',
  'jac': 'jac-motors',
  'gwm': 'great-wall',
  'mercedes-maybach': 'mercedes-benz',
  'citroën': 'citroen',
  'škoda': 'skoda',
};

/// Resolves a brand display name to the static logo filename slug (no `.png`).
String brandLogoSlug(String brand) {
  final trimmed = brand.trim();
  if (trimmed.isEmpty) return '';

  final mapped = brandLogoFilenames[trimmed];
  if (mapped != null) return mapped;

  final lower = trimmed.toLowerCase();
  for (final entry in brandLogoFilenames.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }

  final normalized = _normalizeBrandLogoSlug(trimmed);
  return brandLogoSlugAliases[normalized] ??
      brandLogoSlugAliases[lower] ??
      normalized;
}

String _normalizeBrandLogoSlug(String brand) {
  final buf = StringBuffer();
  for (final rune in brand.toLowerCase().trim().runes) {
    final ch = String.fromCharCode(rune);
    final mapped = _accentFold[ch];
    if (mapped != null) {
      buf.write(mapped);
      continue;
    }
    if ((rune >= 0x61 && rune <= 0x7a) || (rune >= 0x30 && rune <= 0x39)) {
      buf.write(ch);
    } else if (buf.isNotEmpty && !buf.toString().endsWith('-')) {
      buf.write('-');
    }
  }
  var s = buf.toString();
  while (s.endsWith('-')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

const Map<String, String> _accentFold = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ø': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ñ': 'n',
  'ç': 'c',
  'č': 'c',
  'ć': 'c',
  'š': 's',
  'ß': 'ss',
  'ž': 'z',
  'œ': 'oe',
  'æ': 'ae',
  'đ': 'd',
  'ł': 'l',
};
