import 'package:flutter/material.dart';
import '../models/analytics_model.dart';
import '../services/analytics_service.dart';

class AnalyticsPage extends StatefulWidget {
  @override
  _AnalyticsPageState createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  List<ListingAnalytics> _listings = [];
  ListingAnalytics? _selectedListing;
  bool _isLoading = true;
  String? _error;
  AnalyticsSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final listings = await AnalyticsService.getUserListingsAnalytics();
      setState(() {
        _listings = listings;
        _summary = AnalyticsSummary.fromListings(listings);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load your listings: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Analytics'),
        backgroundColor: Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _buildAnalyticsContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadAnalytics,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF6B00),
              foregroundColor: Colors.white,
            ),
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsContent() {
    if (_listings.isEmpty) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Card
          if (_summary != null) _buildSummaryCard(),
          SizedBox(height: 24),

          // Listing Selection
          _buildListingSelection(),
          SizedBox(height: 24),

          // Selected Listing Analytics
          if (_selectedListing != null) _buildSelectedListingAnalytics(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'No Listings Found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Create your first listing to see analytics',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/sell'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF6B00),
              foregroundColor: Colors.white,
            ),
            child: Text('Create Listing'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
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
            color: Color(0xFFFF6B00).withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analytics Overview',
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
                child: _buildSummaryItem('Listings', _summary!.totalListings.toString(), Icons.directions_car),
              ),
              Expanded(
                child: _buildSummaryItem('Views', _summary!.totalViews.toString(), Icons.visibility),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem('Messages', _summary!.totalMessages.toString(), Icons.message),
              ),
              Expanded(
                child: _buildSummaryItem('Calls', _summary!.totalCalls.toString(), Icons.phone),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem('Shares', _summary!.totalShares.toString(), Icons.share),
              ),
              Expanded(
                child: _buildSummaryItem('Favorites', _summary!.totalFavorites.toString(), Icons.favorite),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
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
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildListingSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select a Listing',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ListingAnalytics>(
              value: _selectedListing,
              hint: Text('Choose a listing to view analytics'),
              isExpanded: true,
              items: _listings.map((listing) {
                return DropdownMenuItem<ListingAnalytics>(
                  value: listing,
                  child: Text(
                    '${listing.carTitle} - ${listing.formattedPrice}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (ListingAnalytics? newValue) {
                setState(() {
                  _selectedListing = newValue;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedListingAnalytics() {
    final listing = _selectedListing!;
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Color(0xFFFF6B00).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.directions_car,
                  color: Color(0xFFFF6B00),
                  size: 30,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.carTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    Text(
                      listing.formattedPrice,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFFFF6B00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          
          // Analytics Metrics
          Text(
            'Performance Metrics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 16),
          
          _buildMetricRow('Views', listing.views, Icons.visibility, Colors.blue),
          _buildMetricRow('Messages', listing.messages, Icons.message, Colors.green),
          _buildMetricRow('Calls', listing.calls, Icons.phone, Colors.orange),
          _buildMetricRow('Shares', listing.shares, Icons.share, Colors.purple),
          _buildMetricRow('Favorites', listing.favorites, Icons.favorite, Colors.red),
          
          SizedBox(height: 20),
          
          // Engagement Rate
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  'Engagement Rate',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '${listing.engagementRate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF6B00),
                  ),
                ),
                Text(
                  '${listing.totalInteractions} total interactions',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, int value, IconData icon, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          Spacer(),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}
