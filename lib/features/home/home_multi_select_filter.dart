/// Comma-separated multi-value encoding for home filters (brand, body type).
const String homeFilterListSeparator = ',';

/// Separator between chip filter type and a single list item value.
const String homeFilterChipItemSeparator = '\x1e';

List<String> homeFilterDecodeList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(homeFilterListSeparator)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s.toLowerCase() != 'any')
      .toList();
}

String? homeFilterEncodeList(Iterable<String> values) {
  final cleaned = values
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s.toLowerCase() != 'any')
      .toList();
  if (cleaned.isEmpty) return null;
  return cleaned.join(homeFilterListSeparator);
}

List<String> homeFilterToggleValue(List<String> current, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'any') {
    return const [];
  }
  final next = List<String>.from(current);
  if (next.contains(trimmed)) {
    next.remove(trimmed);
  } else {
    next.add(trimmed);
  }
  return next;
}

String homeFilterChipItemKey(String type, String value) =>
    '$type$homeFilterChipItemSeparator$value';

(String type, String? value) homeFilterParseChipKey(String filterType) {
  final i = filterType.indexOf(homeFilterChipItemSeparator);
  if (i < 0) return (filterType, null);
  return (
    filterType.substring(0, i),
    filterType.substring(i + homeFilterChipItemSeparator.length),
  );
}

String homeFilterSummaryLabel(
  String anyLabel,
  List<String> values,
  String Function(String value) localize, {
  int maxVisible = 2,
}) {
  if (values.isEmpty) return anyLabel;
  if (values.length == 1) return localize(values.first);
  if (values.length <= maxVisible) {
    return values.map(localize).join(', ');
  }
  final visible = values.take(maxVisible).map(localize).join(', ');
  return '$visible +${values.length - maxVisible}';
}
