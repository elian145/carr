String prettyTitleCase(String input) {
  var s = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return s;

  // Only apply to Latin text. Arabic/Kurdish/etc should be left untouched.
  final hasLatin = RegExp(r'[A-Za-z]').hasMatch(s);
  if (!hasLatin) return s;

  String cap(String seg) {
    if (seg.isEmpty) return seg;
    // Roman numerals.
    if (RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(seg)) {
      return seg.toUpperCase();
    }

    final hasLower = RegExp(r'[a-z]').hasMatch(seg);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(seg);
    // Preserve mixed-case tokens like "eTron" or "iPhone".
    if (hasLower && hasUpper) return seg;

    // Uppercase acronyms/short trims: bmw, gxr, le, lx, us.
    final lettersOnly = RegExp(r'^[A-Za-z]+$').hasMatch(seg);
    if (lettersOnly && seg.length <= 3) return seg.toUpperCase();

    // If it contains digits, consider uppercasing the alpha prefix when short.
    final m = RegExp(r'^([A-Za-z]+)([0-9].*)$').firstMatch(seg);
    if (m != null) {
      final alpha = m.group(1) ?? '';
      final rest = m.group(2) ?? '';
      if (alpha.length <= 3) return '${alpha.toUpperCase()}$rest';
    }

    final first = seg.substring(0, 1).toUpperCase();
    final rest = seg.length > 1 ? seg.substring(1).toLowerCase() : '';
    return '$first$rest';
  }

  String transformToken(String token) {
    // Preserve separators inside a token (e.g. "land-cruiser", "cx-5", "x5/40i").
    final buf = StringBuffer();
    var start = 0;
    for (var i = 0; i <= token.length; i++) {
      final isEnd = i == token.length;
      final ch = isEnd ? '' : token[i];
      final isSep = !isEnd && (ch == '-' || ch == '/' || ch == '_');
      if (isEnd || isSep) {
        final part = token.substring(start, i);
        if (part.isNotEmpty) {
          buf.write(cap(part));
        }
        if (isSep) buf.write(ch);
        start = i + 1;
      }
    }
    return buf.toString();
  }

  return s.split(' ').map(transformToken).join(' ');
}

