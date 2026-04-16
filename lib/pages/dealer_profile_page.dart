import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../shared/media/media_url.dart';

class DealerProfilePage extends StatefulWidget {
  final String dealerPublicId;
  const DealerProfilePage({super.key, required this.dealerPublicId});

  @override
  State<DealerProfilePage> createState() => _DealerProfilePageState();
}

class _DealerProfilePageState extends State<DealerProfilePage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _dealer;
  List<Map<String, dynamic>> _listings = const [];
  Map<String, dynamic> _stats = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getDealerProfile(widget.dealerPublicId);
      final dealerRaw = data['dealer'];
      final listingsRaw = data['listings'];
      final statsRaw = data['stats'];
      setState(() {
        _dealer = dealerRaw is Map
            ? Map<String, dynamic>.from(dealerRaw.cast<String, dynamic>())
            : null;
        _listings = listingsRaw is List
            ? listingsRaw
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
                .toList()
            : <Map<String, dynamic>>[];
        _stats = statsRaw is Map
            ? Map<String, dynamic>.from(statsRaw.cast<String, dynamic>())
            : <String, dynamic>{};
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _firstListingImage() {
    for (final listing in _listings) {
      final direct = (listing['image_url'] ?? '').toString().trim();
      if (direct.isNotEmpty) return buildMediaUrl(direct);
      final images = listing['images'];
      if (images is List && images.isNotEmpty) {
        final first = images.first;
        if (first is Map) {
          final v = (first['image_url'] ?? '').toString().trim();
          if (v.isNotEmpty) return buildMediaUrl(v);
        }
      }
    }
    return '';
  }

  String _cardImage(Map<String, dynamic> listing) {
    final direct = (listing['image_url'] ?? '').toString().trim();
    if (direct.isNotEmpty) return buildMediaUrl(direct);
    final images = listing['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) {
        final v = (first['image_url'] ?? '').toString().trim();
        if (v.isNotEmpty) return buildMediaUrl(v);
      }
    }
    return '';
  }

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dealer = _dealer;
    final dealershipName = (dealer?['dealership_name'] ?? '').toString().trim();
    final firstName = (dealer?['first_name'] ?? '').toString().trim();
    final lastName = (dealer?['last_name'] ?? '').toString().trim();
    final fallbackName = ('$firstName $lastName').trim();
    final displayName = dealershipName.isNotEmpty
        ? dealershipName
        : (fallbackName.isNotEmpty ? fallbackName : 'Dealer');
    final logoUrl = buildMediaUrl((dealer?['profile_picture'] ?? '').toString().trim());
    final coverUrl = _firstListingImage();
    final location = (dealer?['dealership_location'] ?? dealer?['location'] ?? '')
        .toString()
        .trim();
    final phone = (dealer?['dealership_phone'] ?? dealer?['phone_number'] ?? '')
        .toString()
        .trim();
    final createdAt = (dealer?['created_at'] ?? '').toString().trim();
    final totalListings = (_stats['total_listings'] ?? _listings.length).toString();
    final featuredListings = (_stats['featured_listings'] ?? 0).toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Dealer')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  )
                : ListView(
                    children: [
                      if (coverUrl.isNotEmpty)
                        SizedBox(
                          height: 180,
                          child: Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(color: Colors.black12),
                          ),
                        )
                      else
                        Container(height: 140, color: Colors.black12),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 34,
                                  backgroundImage: logoUrl.isNotEmpty
                                      ? NetworkImage(logoUrl)
                                      : null,
                                  child: logoUrl.isEmpty
                                      ? Text(
                                          displayName.isNotEmpty
                                              ? displayName[0].toUpperCase()
                                              : 'D',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Listings: $totalListings  •  Featured: $featuredListings',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _infoRow(Icons.location_on_outlined, 'Location', location),
                            _infoRow(Icons.phone_outlined, 'Phone', phone),
                            _infoRow(Icons.calendar_today_outlined, 'Member since', createdAt),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Listings',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_listings.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('No active listings right now.'),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: _listings.length,
                          separatorBuilder: (context, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _listings[index];
                            final id = (item['id'] ?? '').toString().trim();
                            final title = (item['title'] ??
                                    '${item['brand'] ?? ''} ${item['model'] ?? ''} ${item['year'] ?? ''}')
                                .toString()
                                .trim();
                            final price = (item['price'] ?? '').toString().trim();
                            final currency = (item['currency'] ?? '').toString().trim();
                            final carLocation = (item['location'] ?? item['city'] ?? '')
                                .toString()
                                .trim();
                            final img = _cardImage(item);
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: id.isEmpty
                                  ? null
                                  : () => Navigator.pushNamed(
                                        context,
                                        '/car_detail',
                                        arguments: {'carId': id},
                                      ),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.horizontal(
                                        left: Radius.circular(12),
                                      ),
                                      child: SizedBox(
                                        width: 110,
                                        height: 90,
                                        child: img.isEmpty
                                            ? Container(color: Colors.black12)
                                            : Image.network(img, fit: BoxFit.cover),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title.isNotEmpty ? title : 'Listing',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w700),
                                            ),
                                            const SizedBox(height: 6),
                                            Text([price, currency].where((e) => e.isNotEmpty).join(' ')),
                                            if (carLocation.isNotEmpty)
                                              Text(
                                                carLocation,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
      ),
    );
  }
}

