import 'package:flutter/services.dart';

/// Formats integer input with comma thousand separators while typing (e.g. 12500 → 12,500).
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter();

  static String digitsOnly(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  static String format(String value) {
    final digits = digitsOnly(value);
    if (digits.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newDigits = digitsOnly(newValue.text);
    if (newDigits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final formatted = format(newDigits);
    final selectionEnd = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBeforeCursor = digitsOnly(
      newValue.text.substring(0, selectionEnd),
    ).length;

    var cursor = formatted.length;
    if (digitsBeforeCursor == 0) {
      cursor = 0;
    } else if (digitsBeforeCursor < newDigits.length) {
      var digitCount = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted.codeUnitAt(i) >= 48 && formatted.codeUnitAt(i) <= 57) {
          digitCount++;
          if (digitCount == digitsBeforeCursor) {
            cursor = i + 1;
            break;
          }
        }
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}
