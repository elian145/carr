/// Phone number normalization helpers.
///
/// The backend (and stored user profiles) typically expect E.164-like strings,
/// while UI fields often allow spaces, dashes, parentheses, and local formats.
///
/// This normalizer is conservative:
/// - Preserves leading `+` when present.
/// - Converts `00` international prefix into `+`.
/// - Converts common Iraqi local formats into `+964...`:
///   - `07xxxxxxxxx` -> `+9647xxxxxxxx`
///   - `7xxxxxxxxx`  -> `+9647xxxxxxxx`
///   - `9647xxxxxxxx` -> `+9647xxxxxxxx`
/// - Otherwise falls back to digits-only (no `+`), since some backends store
///   local numbers as plain digits.
String normalizePhoneNumber(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return '';

  final digitsOnly = raw.replaceAll(RegExp(r'\D'), '');
  if (digitsOnly.isEmpty) return '';

  // Preserve explicit international format if user entered it.
  if (raw.startsWith('+')) {
    return '+$digitsOnly';
  }

  // Convert 00-prefixed international format (e.g. 00964...) into +964...
  if (digitsOnly.startsWith('00') && digitsOnly.length > 2) {
    return '+${digitsOnly.substring(2)}';
  }

  // If already includes Iraq country code without +, add it.
  if (digitsOnly.startsWith('964') && digitsOnly.length >= 12) {
    return '+$digitsOnly';
  }

  // Common Iraqi mobile local forms.
  // - 07XXXXXXXXX (11 digits) -> +9647XXXXXXXXX (drop leading 0)
  if (digitsOnly.length == 11 &&
      digitsOnly.startsWith('0') &&
      digitsOnly.substring(1).startsWith('7')) {
    return '+964${digitsOnly.substring(1)}';
  }
  // - 7XXXXXXXXX (10 digits) -> +9647XXXXXXXXX
  if (digitsOnly.length == 10 && digitsOnly.startsWith('7')) {
    return '+964$digitsOnly';
  }

  // Fallback: digits-only. This keeps behavior compatible with servers that
  // accept plain local numbers.
  return digitsOnly;
}

