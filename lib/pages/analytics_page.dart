import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../services/config.dart';
import '../models/analytics_model.dart';
import '../services/analytics_service.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/global_listing_card.dart';
import '../theme_provider.dart';
import '../shared/text/pretty_title_case.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  List<ListingAnalytics> _listings = [];
  ListingAnalytics? _selectedListing;
  bool _isLoading = true;
  String? _error;
  AnalyticsSummary? _summary;

  // Brand logo filenames map (copied from main.dart)
  final Map<String, String> brandLogoFilenames = {
    'toyota': 'toyota',
    'nissan': 'nissan',
    'mercedes-benz': 'mercedes-benz',
    'bmw': 'bmw',
    'audi': 'audi',
    'volkswagen': 'volkswagen',
    'kia': 'kia',
    'hyundai': 'hyundai',
    'honda': 'honda',
    'mazda': 'mazda',
    'ford': 'ford',
    'chevrolet': 'chevrolet',
    'lexus': 'lexus',
    'infiniti': 'infiniti',
    'mitsubishi': 'mitsubishi',
    'subaru': 'subaru',
    'suzuki': 'suzuki',
    'acura': 'acura',
    'buick': 'buick',
    'cadillac': 'cadillac',
    'chrysler': 'chrysler',
    'dodge': 'dodge',
    'genesis': 'genesis',
    'gmc': 'gmc',
    'jaguar': 'jaguar',
    'jeep': 'jeep',
    'lincoln': 'lincoln',
    'maserati': 'maserati',
    'mini': 'mini',
    'porsche': 'porsche',
    'ram': 'ram',
    'smart': 'smart',
    'tesla': 'tesla',
    'volvo': 'volvo',
    'dacia': 'dacia',
    'fiat': 'fiat',
    'lancia': 'lancia',
    'land-rover': 'land-rover',
    'skoda': 'skoda',
    'seat': 'seat',
    'peugeot': 'peugeot',
    'citroën': 'citroen',
    'citroen': 'citroen',
    'renault': 'renault',
    'opel': 'opel',
    'alfa-romeo': 'alfa-romeo',
    'ferrari': 'ferrari',
    'lamborghini': 'lamborghini',
    'bentley': 'bentley',
    'rolls-royce': 'rolls-royce',
    'aston-martin': 'aston-martin',
    'mclaren': 'mclaren',
    'lotus': 'lotus',
    'saab': 'saab',
    'scion': 'scion',
    'isuzu': 'isuzu',
    'daihatsu': 'daihatsu',
    'geo': 'geo',
    'hummer': 'hummer',
    'mercury': 'mercury',
    'oldsmobile': 'oldsmobile',
    'plymouth': 'plymouth',
    'pontiac': 'pontiac',
    'saturn': 'saturn',
    'daewoo': 'daewoo',
    'ssangyong': 'ssangyong',
    'great-wall': 'great-wall',
    'chery': 'chery',
    'byd': 'byd',
    'geely': 'geely',
    'mg': 'mg',
    'tata': 'tata',
    'mahindra': 'mahindra',
    'maruti-suzuki': 'maruti-suzuki',
    'proton': 'proton',
    'perodua': 'perodua',
    'dacia': 'dacia',
    'lada': 'lada',
    'uaz': 'uaz',
    'gaz': 'gaz',
    'zaz': 'zaz',
    'bogdan': 'bogdan',
    'changan': 'changan',
    'dongfeng': 'dongfeng',
    'faw': 'faw',
    'jac': 'jac',
    'jianghuai': 'jianghuai',
    'lifan': 'lifan',
    'zotye': 'zotye',
    'haval': 'haval',
    'wey': 'wey',
    'lynk-co': 'lynk-co',
    'polestar': 'polestar',
    'genesis': 'genesis',
    'ds': 'ds',
    'alpine': 'alpine',
    'cupra': 'cupra',
    'smart': 'smart',
    'maybach': 'maybach',
    'amg': 'amg',
    'brabus': 'brabus',
    'alpina': 'alpina',
    'ac-cars': 'ac-cars',
    'ariel': 'ariel',
    'caterham': 'caterham',
    'morgan': 'morgan',
    'tvr': 'tvr',
    'westfield': 'westfield',
  };

  // Helper functions (copied from main.dart)
  String getApiBase() {
    return apiBase();
  }

  NumberFormat _decimalFormatterGlobal(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode == 'ar' ||
        locale.languageCode == 'ku' ||
        locale.languageCode == 'ckb') {
      return NumberFormat.decimalPattern('en_US');
    }
    return NumberFormat.decimalPattern(locale.toLanguageTag());
  }

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
      if (!mounted) return;
      setState(() {
        _listings = listings;
        _summary = AnalyticsSummary.fromListings(listings);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback:
              AppLocalizations.of(context)?.failedToLoadListings ??
              'Failed to load your listings',
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.analyticsTitle),
        backgroundColor: Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: AppThemes.shellBackgroundDecoration(
          Theme.of(context).brightness,
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildErrorState(context)
            : _buildAnalyticsContent(context),
      ),
    );
  }

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

  Widget _buildListingCard(ListingAnalytics listing) {
    final isSelected = _selectedListing?.listingId == listing.listingId;

    // Convert analytics data to match home page car format EXACTLY like My Listings
    final String brand = (listing.brand ?? '').trim();
    final String model = (listing.model).trim();
    final String yearStr = (listing.year?.toString() ?? '').trim();
    final String apiTitle = (listing.title).trim();
    String displayTitle;
    if (apiTitle.isNotEmpty) {
      displayTitle = apiTitle;
    } else {
      final String base = [
        if (brand.isNotEmpty) prettyTitleCase(brand),
        if (model.isNotEmpty) prettyTitleCase(model),
      ].join(' ');
      displayTitle = yearStr.isNotEmpty ? '$base ($yearStr)' : base;
    }
    displayTitle = prettyTitleCase(displayTitle);

    final num? mileageNum = listing.mileage;
    final String mileageFormatted = mileageNum == null
        ? ''
        : _decimalFormatterGlobal(context).format(mileageNum);

    final car = {
      'id': listing.listingId,
      'brand': brand,
      'title': displayTitle,
      'price': listing.price,
      'year': listing.year,
      'mileage': mileageFormatted,
      'city': listing.city ?? '',
      'image_url':
          listing.imageUrl?.replaceFirst(
            '${getApiBase()}/static/uploads/',
            '',
          ) ??
          '',
      'images': [],
      'is_quick_sell': false,
    };

    Widget cardWidget = buildGlobalCarCard(
      context,
      Map<String, dynamic>.from(car),
    );
    if (isSelected) {
      cardWidget = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFF6B00), width: 2),
        ),
        child: cardWidget,
      );
    }

    // Override tap behavior for analytics modal
    return GestureDetector(
      onTap: () => _showAnalyticsModal(context, listing),
      child: AbsorbPointer(child: cardWidget),
    );
  }

  void _showAnalyticsModal(BuildContext context, ListingAnalytics listing) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            width: 360,
            height: 600,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Colors.grey[50]!],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 60,
                  offset: Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              children: [
                // Modern header with gradient
                Container(
                  padding: EdgeInsets.fromLTRB(24, 20, 20, 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF6B00), Color(0xFFFF8A50)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.analytics_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Analytics Dashboard',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Performance insights',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Content with modern styling
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Car image with modern styling
                        Container(
                          width: 240,
                          height: 160,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFFFF6B00).withValues(alpha: 0.2),
                                blurRadius: 20,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child:
                                listing.imageUrl != null &&
                                    listing.imageUrl!.isNotEmpty
                                ? Image.network(
                                    listing.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.grey[100]!,
                                              Colors.grey[200]!,
                                            ],
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.directions_car_outlined,
                                          color: Colors.grey[500],
                                          size: 60,
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.grey[100]!,
                                          Colors.grey[200]!,
                                        ],
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.directions_car_outlined,
                                      color: Colors.grey[500],
                                      size: 60,
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(height: 24),
                        // Car details with modern typography
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[100]!),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                listing.carTitle,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[900],
                                  letterSpacing: 0.3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 8),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFFFF6B00),
                                      Color(0xFFFF8A50),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  listing.formattedPrice,
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 32),
                        // Modern metrics section
                        Text(
                          'Performance Metrics',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 20),
                        // Modern metrics grid
                        Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey[100]!),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 15,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // First row
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildModernMetricItem(
                                      Icons.visibility_outlined,
                                      '${listing.views}',
                                      'Views',
                                      Color(0xFF4CAF50),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: _buildModernMetricItem(
                                      Icons.message_outlined,
                                      '${listing.messages}',
                                      'Messages',
                                      Color(0xFF2196F3),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              // Second row
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildModernMetricItem(
                                      Icons.phone_outlined,
                                      '${listing.calls}',
                                      'Calls',
                                      Color(0xFF9C27B0),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: _buildModernMetricItem(
                                      Icons.share_outlined,
                                      '${listing.shares}',
                                      'Shares',
                                      Color(0xFFFF9800),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              // Third row
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildModernMetricItem(
                                      Icons.favorite_outline,
                                      '${listing.favorites}',
                                      'Favorites',
                                      Color(0xFFE91E63),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: _buildModernMetricItem(
                                      Icons.trending_up_outlined,
                                      '${listing.engagementRate.toStringAsFixed(1)}%',
                                      'Engagement',
                                      Color(0xFF00BCD4),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernMetricItem(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[900],
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
