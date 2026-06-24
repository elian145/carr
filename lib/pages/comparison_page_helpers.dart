part of 'comparison_page.dart';

extension _CarComparisonPageHelpers on CarComparisonPage {
  Widget _buildCarImage(Map<String, dynamic> car) {
    final imageUrl = car['image_url']?.toString();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final built = buildLegacyFullImageUrl(imageUrl);
      return listingNetworkImage(built, fit: BoxFit.cover);
    }
    return Container(
      color: Colors.white10,
      child: Icon(Icons.directions_car, color: Colors.white24),
    );
  }
}
