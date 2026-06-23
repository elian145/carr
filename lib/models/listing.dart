/// Lightweight listing summary for feeds and cards.
class ListingSummary {
  const ListingSummary({
    required this.id,
    required this.title,
    this.brand,
    this.model,
    this.year,
    this.price,
    this.currency,
    this.imageUrl,
    this.status,
    this.sellerId,
  });

  final String id;
  final String title;
  final String? brand;
  final String? model;
  final int? year;
  final num? price;
  final String? currency;
  final String? imageUrl;
  final String? status;
  final String? sellerId;

  factory ListingSummary.fromJson(Map<String, dynamic> json) {
    final id = json['id'] ?? json['car_id'] ?? json['listing_id'];
    return ListingSummary(
      id: id?.toString() ?? '',
      title: (json['title'] ?? json['name'] ?? '').toString(),
      brand: json['brand']?.toString(),
      model: json['model']?.toString(),
      year: intOrNull(json['year']),
      price: json['price'] is num
          ? json['price'] as num
          : num.tryParse('${json['price']}'),
      currency: json['currency']?.toString(),
      imageUrl: (json['image_url'] ?? json['thumbnail_url'])?.toString(),
      status: json['status']?.toString(),
      sellerId: (json['seller_id'] ?? json['user_id'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (brand != null) 'brand': brand,
    if (model != null) 'model': model,
    if (year != null) 'year': year,
    if (price != null) 'price': price,
    if (currency != null) 'currency': currency,
    if (imageUrl != null) 'image_url': imageUrl,
    if (status != null) 'status': status,
    if (sellerId != null) 'seller_id': sellerId,
  };

  static int? intOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

/// Full listing detail (extends summary fields).
class Listing extends ListingSummary {
  const Listing({
    required super.id,
    required super.title,
    super.brand,
    super.model,
    super.year,
    super.price,
    super.currency,
    super.imageUrl,
    super.status,
    super.sellerId,
    this.description,
    this.mileage,
    this.location,
    this.images = const [],
    this.videos = const [],
    this.raw = const {},
  });

  final String? description;
  final int? mileage;
  final String? location;
  final List<String> images;
  final List<String> videos;
  final Map<String, dynamic> raw;

  factory Listing.fromJson(Map<String, dynamic> json) {
    final summary = ListingSummary.fromJson(json);
    final imgs = <String>[];
    final rawImages = json['images'] ?? json['photos'];
    if (rawImages is List) {
      for (final item in rawImages) {
        if (item is String) {
          imgs.add(item);
        } else if (item is Map) {
          final u = item['url'] ?? item['image_url'];
          if (u != null) imgs.add(u.toString());
        }
      }
    }
    final vids = <String>[];
    final rawVideos = json['videos'];
    if (rawVideos is List) {
      for (final item in rawVideos) {
        if (item is String) {
          vids.add(item);
        } else if (item is Map) {
          final u = item['url'] ?? item['video_url'];
          if (u != null) vids.add(u.toString());
        }
      }
    }
    return Listing(
      id: summary.id,
      title: summary.title,
      brand: summary.brand,
      model: summary.model,
      year: summary.year,
      price: summary.price,
      currency: summary.currency,
      imageUrl: summary.imageUrl,
      status: summary.status,
      sellerId: summary.sellerId,
      description: json['description']?.toString(),
      mileage: ListingSummary.intOrNull(json['mileage'] ?? json['odometer']),
      location: (json['location'] ?? json['city'])?.toString(),
      images: imgs,
      videos: vids,
      raw: Map<String, dynamic>.from(json),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    if (description != null) 'description': description,
    if (mileage != null) 'mileage': mileage,
    if (location != null) 'location': location,
    if (images.isNotEmpty) 'images': images,
    if (videos.isNotEmpty) 'videos': videos,
  };
}
