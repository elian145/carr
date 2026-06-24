part of 'analytics_page.dart';

mixin _AnalyticsPageWidgets on _AnalyticsPageListingWidgets {
  Widget _buildErrorState(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            loc.failedToLoadListings,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          if (_error != null && _error!.isNotEmpty) ...[
            SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadAnalytics,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF6B00),
              foregroundColor: Colors.white,
            ),
            child: Text(loc.retryAction),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsContent(BuildContext context) {
    if (_listings.isEmpty) {
      return _buildEmptyState(context);
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_summary != null)
            Padding(padding: EdgeInsets.all(16), child: _buildSummaryCard(context)),
          _buildListingSelection(context),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            loc.noListingsFound,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            loc.createFirstListingForAnalytics,
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/sell'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF6B00),
              foregroundColor: Colors.white,
            ),
            child: Text(loc.createListingButtonShort),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF6B00), Color(0xFFFF8C42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color(0xFFFF6B00).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.analyticsOverview,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  context,
                  loc.listingsLabel,
                  _summary!.totalListings.toString(),
                  Icons.directions_car,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  context,
                  loc.viewsLabel,
                  _summary!.totalViews.toString(),
                  Icons.visibility,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  context,
                  loc.messagesLabel,
                  _summary!.totalMessages.toString(),
                  Icons.message,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  context,
                  loc.callsLabel,
                  _summary!.totalCalls.toString(),
                  Icons.phone,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  context,
                  loc.sharesLabel,
                  _summary!.totalShares.toString(),
                  Icons.share,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  context,
                  loc.favoritesLabel,
                  _summary!.totalFavorites.toString(),
                  Icons.favorite,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(BuildContext context, String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }
}
