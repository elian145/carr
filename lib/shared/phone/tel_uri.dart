import 'phone_normalizer.dart';

/// Number to hand to the system dialer for a stored contact phone, or `null`
/// when [raw] has no digits.
///
/// F-40: the call button used to keep only `[0-9]`, so the E.164 numbers the
/// API serves for listings (`+9647701234567`) became `tel:9647701234567`, which
/// dialers treat as a local number and fail to connect. A dial string must keep
/// its leading `+`:
///
/// * `+9647701234567`, `+964 770-123-4567`, `009647701234567`,
///   `9647701234567`, `07701234567`, `7701234567`  ->  `+9647701234567`
/// * the malformed legacy `+96407701234567` (trunk zero after the country code)
///   ->  `+9647701234567`
/// * Arabic-Indic / Persian digits are folded to ASCII first
/// * a foreign number keeps its explicit `+` (`+442071838750`); a bare local
///   number of another country stays digits-only (nothing to infer)
String? dialableTelNumber(String? raw) {
  var s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  s = _foldDigits(s);
  var out = normalizePhoneNumber(s);
  if (out.isEmpty || out == '+') return null;
  // +9640XXXXXXXXXX -> +964XXXXXXXXXX (malformed Iraqi spelling; mirrors the API).
  if (out.startsWith('+9640')) out = '+964${out.substring(5)}';
  if (!RegExp(r'[0-9]').hasMatch(out)) return null;
  return out;
}

/// `tel:` [Uri] for [raw] (see [dialableTelNumber]); `null` if not dialable.
Uri? telUriFor(String? raw) {
  final number = dialableTelNumber(raw);
  if (number == null) return null;
  return Uri(scheme: 'tel', path: number);
}

/// Folds Arabic-Indic (U+0660..U+0669) and Persian (U+06F0..U+06F9) digits.
String _foldDigits(String input) {
  final b = StringBuffer();
  for (final u in input.runes) {
    if (u >= 0x0660 && u <= 0x0669) {
      b.writeCharCode(0x30 + (u - 0x0660));
    } else if (u >= 0x06F0 && u <= 0x06F9) {
      b.writeCharCode(0x30 + (u - 0x06F0));
    } else {
      b.writeCharCode(u);
    }
  }
  return b.toString();
}
