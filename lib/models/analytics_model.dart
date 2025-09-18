class ListingAnalytics {
  final String listingId;
  final String title;
  final String brand;
  final String model;
  final int year;
  final double price;
  final String? imageUrl;
  final int views;
  final int messages;
  final int calls;
  final int shares;
  final int favorites;
  final DateTime createdAt;
  final DateTime lastUpdated;

  ListingAnalytics({
    required this.listingId,
    required this.title,
    required this.brand,
    required this.model,
    required this.year,
    required this.price,
    this.imageUrl,
    required this.views,
    required this.messages,
    required this.calls,
    required this.shares,
    required this.favorites,
    required this.createdAt,
    required this.lastUpdated,
  });

  factory ListingAnalytics.fromJson(Map<String, dynamic> json) {
    return ListingAnalytics(
      listingId: json['listing_id'] ?? json['id'] ?? '',
      title: json['title'] ?? '',
      brand: json['brand'] ?? '',
      model: json['model'] ?? '',
      year: json['year'] ?? 0,
      price: (json['price'] ?? 0).toDouble(),
      imageUrl: json['image_url'],
      views: json['views'] ?? 0,
      messages: json['messages'] ?? 0,
      calls: json['calls'] ?? 0,
      shares: json['shares'] ?? 0,
      favorites: json['favorites'] ?? 0,
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      lastUpdated: DateTime.parse(json['last_updated'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'listing_id': listingId,
      'title': title,
      'brand': brand,
      'model': model,
      'year': year,
      'price': price,
      'image_url': imageUrl,
      'views': views,
      'messages': messages,
      'calls': calls,
      'shares': shares,
      'favorites': favorites,
      'created_at': createdAt.toIso8601String(),
      'last_updated': lastUpdated.toIso8601String(),
    };
  }

  // Helper methods for analytics calculations
  int get totalInteractions => views + messages + calls + shares + favorites;
  
  double get engagementRate {
    if (views == 0) return 0.0;
    return (totalInteractions - views) / views * 100;
  }

  String get formattedPrice {
    return '\$${price.toStringAsFixed(0)}';
  }

  String get carTitle {
    return '$brand $model ($year)';
  }
}

class AnalyticsSummary {
  final int totalListings;
  final int totalViews;
  final int totalMessages;
  final int totalCalls;
  final int totalShares;
  final int totalFavorites;
  final double averageEngagementRate;
  final List<ListingAnalytics> topPerformers;

  AnalyticsSummary({
    required this.totalListings,
    required this.totalViews,
    required this.totalMessages,
    required this.totalCalls,
    required this.totalShares,
    required this.totalFavorites,
    required this.averageEngagementRate,
    required this.topPerformers,
  });

  factory AnalyticsSummary.fromListings(List<ListingAnalytics> listings) {
    if (listings.isEmpty) {
      return AnalyticsSummary(
        totalListings: 0,
        totalViews: 0,
        totalMessages: 0,
        totalCalls: 0,
        totalShares: 0,
        totalFavorites: 0,
        averageEngagementRate: 0.0,
        topPerformers: [],
      );
    }

    final totalViews = listings.fold(0, (sum, listing) => sum + listing.views);
    final totalMessages = listings.fold(0, (sum, listing) => sum + listing.messages);
    final totalCalls = listings.fold(0, (sum, listing) => sum + listing.calls);
    final totalShares = listings.fold(0, (sum, listing) => sum + listing.shares);
    final totalFavorites = listings.fold(0, (sum, listing) => sum + listing.favorites);

    final averageEngagementRate = listings.isEmpty 
        ? 0.0 
        : listings.fold(0.0, (sum, listing) => sum + listing.engagementRate) / listings.length;

    // Sort by total interactions and take top 3
    final sortedListings = List<ListingAnalytics>.from(listings);
    sortedListings.sort((a, b) => b.totalInteractions.compareTo(a.totalInteractions));
    final topPerformers = sortedListings.take(3).toList();

    return AnalyticsSummary(
      totalListings: listings.length,
      totalViews: totalViews,
      totalMessages: totalMessages,
      totalCalls: totalCalls,
      totalShares: totalShares,
      totalFavorites: totalFavorites,
      averageEngagementRate: averageEngagementRate,
      topPerformers: topPerformers,
    );
  }
}
