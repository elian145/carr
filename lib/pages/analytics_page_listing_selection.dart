part of 'analytics_page.dart';

mixin _AnalyticsPageListingSelection on _AnalyticsPageListingCard {
  Widget _buildListingSelection(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.all(8), // Same padding as home page
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.62, // Match home listing grid (tall enough for card content)
        crossAxisSpacing: 8, // Same spacing as home page
        mainAxisSpacing: 8, // Same spacing as home page
      ),
      itemCount: _listings.length,
      itemBuilder: (context, index) {
        final listing = _listings[index];
        return _buildListingCard(listing);
      },
    );
  }
}
