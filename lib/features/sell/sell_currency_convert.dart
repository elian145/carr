/// Converts a formatted sell-flow price string between USD and IQD.
String convertSellListingPrice(
  String price,
  String fromCurrency,
  String toCurrency,
) {
  if (price.isEmpty) return price;

  final numericValue = price.replaceAll(RegExp(r'[^\d.]'), '');
  final value = double.tryParse(numericValue) ?? 0;

  if (value == 0) return price;

  final double convertedValue;
  if (fromCurrency == 'USD' && toCurrency == 'IQD') {
    convertedValue = value * 1420;
  } else if (fromCurrency == 'IQD' && toCurrency == 'USD') {
    convertedValue = value / 1420;
  } else {
    return price;
  }

  if (toCurrency == 'IQD') {
    return 'IQD ${convertedValue.toStringAsFixed(0)}';
  }
  return '\$${convertedValue.toStringAsFixed(0)}';
}
