/// Sort home feed listing maps client-side when the API sort fails.
List<Map<String, dynamic>> homeFeedClientSortedListings(
  List<Map<String, dynamic>> input,
  String apiSortValue,
) {
  final sorted = List<Map<String, dynamic>>.from(input);

  switch (apiSortValue) {
    case 'price_asc':
      sorted.sort((a, b) {
        final priceA = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
        final priceB = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
        return priceA.compareTo(priceB);
      });
    case 'price_desc':
      sorted.sort((a, b) {
        final priceA = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
        final priceB = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
        return priceB.compareTo(priceA);
      });
    case 'year_desc':
      sorted.sort((a, b) {
        final yearA = int.tryParse(a['year']?.toString() ?? '0') ?? 0;
        final yearB = int.tryParse(b['year']?.toString() ?? '0') ?? 0;
        return yearB.compareTo(yearA);
      });
    case 'year_asc':
      sorted.sort((a, b) {
        final yearA = int.tryParse(a['year']?.toString() ?? '0') ?? 0;
        final yearB = int.tryParse(b['year']?.toString() ?? '0') ?? 0;
        return yearA.compareTo(yearB);
      });
    case 'mileage_asc':
      sorted.sort((a, b) {
        final mileageA = int.tryParse(a['mileage']?.toString() ?? '0') ?? 0;
        final mileageB = int.tryParse(b['mileage']?.toString() ?? '0') ?? 0;
        return mileageA.compareTo(mileageB);
      });
    case 'mileage_desc':
      sorted.sort((a, b) {
        final mileageA = int.tryParse(a['mileage']?.toString() ?? '0') ?? 0;
        final mileageB = int.tryParse(b['mileage']?.toString() ?? '0') ?? 0;
        return mileageB.compareTo(mileageA);
      });
    case 'newest':
      sorted.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime(1970);
        final dateB =
            DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime(1970);
        return dateB.compareTo(dateA);
      });
  }

  return sorted;
}
