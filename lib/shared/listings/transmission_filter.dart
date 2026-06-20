/// Options removed from filter UI; still used to drop spec-driven list entries.
bool isExcludedTransmissionFilter(String value) {
  final compact = value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  return compact == 'semiautomatic' || compact == 'semiauto' || compact == 'cvt';
}
