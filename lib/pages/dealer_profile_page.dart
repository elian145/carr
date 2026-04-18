import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../legacy/main_legacy.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../shared/maps/dealer_map_coords.dart';
import '../shared/maps/open_google_maps.dart';
import '../shared/media/media_url.dart';
import '../theme_provider.dart';
import '../widgets/dealer_location_map_preview.dart';
import 'edit_dealer_page.dart';

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

  String _normalizeTel(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '+' && buf.isEmpty) {
        buf.write(c);
      } else if (RegExp(r'[0-9]').hasMatch(c)) {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  Future<void> _callDealer(String rawPhone) async {
    final phone = _normalizeTel(rawPhone);
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');

    bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!launched) {
      launched = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      ).catchError((_) => false);
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start a call')),
      );
    }
  }

  Future<void> _emailDealer(String rawEmail) async {
    final addr = rawEmail.trim();
    if (addr.isEmpty) return;
    final uri = Uri(scheme: 'mailto', path: addr);

    bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!launched) {
      launched = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      ).catchError((_) => false);
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email app')),
      );
    }
  }

  void _copyToClipboard(String text, String snackbarMessage) {
    final t = text.trim();
    if (t.isEmpty) return;
    Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snackbarMessage)),
    );
  }

  Future<void> _openDealerOnGoogleMaps(
    double lat,
    double lng,
  ) async {
    final ok = await openGoogleMapsAt(lat, lng);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }

  Map<String, String> _openingHoursFromAnySource(
    Map<String, dynamic>? dealer,
    List<Map<String, dynamic>> listings,
    Map<String, dynamic>? currentUser,
    bool isDealerOwner,
  ) {
    dynamic raw;
    if (dealer != null) {
      raw = dealer['dealership_opening_hours'] ??
          dealer['opening_hours'] ??
          dealer['dealership_hours'];
    }
    // Fallback: sometimes the seller blob inside listings has more fields.
    if (raw is! Map && listings.isNotEmpty) {
      final seller = listings.first['seller'];
      if (seller is Map) {
        raw = seller['dealership_opening_hours'] ??
            seller['opening_hours'] ??
            seller['dealership_hours'];
      }
    }
    // Fallback for owner: use locally refreshed /auth/me payload.
    if (raw is! Map && isDealerOwner && currentUser != null) {
      raw = currentUser['dealership_opening_hours'] ??
          currentUser['opening_hours'] ??
          currentUser['dealership_hours'];
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) raw = decoded;
      } catch (_) {}
    }
    if (raw is! Map) return const {};

    final m = <String, String>{};
    for (final entry in raw.entries) {
      final key = (entry.key ?? '').toString().trim().toLowerCase();
      final val = (entry.value ?? '').toString().trim();
      if (key.isEmpty) continue;
      if (val.isEmpty) continue;
      m[key] = val;
    }
    return m;
  }

  Widget _openingHoursTable(Map<String, String> hours) {
    const rows = <({String label, String key})>[
      (label: 'Monday', key: 'mon'),
      (label: 'Tuesday', key: 'tue'),
      (label: 'Wednesday', key: 'wed'),
      (label: 'Thursday', key: 'thu'),
      (label: 'Friday', key: 'fri'),
      (label: 'Saturday', key: 'sat'),
      (label: 'Sunday', key: 'sun'),
    ];

    final allEmpty = rows.every((r) => (hours[r.key] ?? '').trim().isEmpty);
    final borderColor = Theme.of(context)
        .colorScheme
        .outline
        .withValues(alpha: Theme.of(context).brightness == Brightness.light ? 0.35 : 0.55);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Opening hours',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(2),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder(
                horizontalInside: BorderSide(color: borderColor, width: 1),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.55),
                  ),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        'Day',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        'Hours',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                for (final r in rows)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(r.label),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          allEmpty ? 'Not provided' : (hours[r.key] ?? '—'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final dealer = _dealer;
    final dealershipName = (dealer?['dealership_name'] ?? '').toString().trim();
    final firstName = (dealer?['first_name'] ?? '').toString().trim();
    final lastName = (dealer?['last_name'] ?? '').toString().trim();
    final fallbackName = ('$firstName $lastName').trim();
    final displayName = dealershipName.isNotEmpty
        ? dealershipName
        : (fallbackName.isNotEmpty ? fallbackName : 'Dealer');
    final logoUrl = buildMediaUrl((dealer?['profile_picture'] ?? '').toString().trim());
    final coverUrl = buildMediaUrl(
      (dealer?['dealership_cover_picture'] ?? '').toString().trim(),
    );
    final bannerUrl = coverUrl.isNotEmpty ? coverUrl : _firstListingImage();
    final location = (dealer?['dealership_location'] ?? dealer?['location'] ?? '')
        .toString()
        .trim();
    final double? mapLat = parseDealerCoord(dealer?['dealership_latitude']);
    final double? mapLng = parseDealerCoord(dealer?['dealership_longitude']);
    final phone = (dealer?['dealership_phone'] ?? dealer?['phone_number'] ?? '')
        .toString()
        .trim();
    final email = (dealer?['email'] ?? '').toString().trim();
    final description = (dealer?['dealership_description'] ?? '').toString().trim();
    final totalListings = (_stats['total_listings'] ?? _listings.length).toString();
    final featuredListings = (_stats['featured_listings'] ?? 0).toString();
    final currentUserPublicId =
        (auth.currentUser?['id'] ?? '').toString().trim();
    final isDealerOwner =
        auth.isAuthenticated && currentUserPublicId == widget.dealerPublicId;
    final openingHours = _openingHoursFromAnySource(
      dealer,
      _listings,
      auth.currentUser,
      isDealerOwner,
    );
    final isLightShell = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
      appBar: AppBar(title: const Text('Dealer')),
      backgroundColor: isLightShell ? AppThemes.lightAppBackground : null,
      body: Stack(
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          RefreshIndicator(
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
                      if (bannerUrl.isNotEmpty)
                        SizedBox(
                          height: 180,
                          child: Image.network(
                            bannerUrl,
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
                            if (isDealerOwner) ...[
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final changed = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const EditDealerPage(),
                                    ),
                                  );
                                  if (changed == true) {
                                    await _load();
                                  }
                                },
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit dealer page'),
                              ),
                            ],
                            const SizedBox(height: 12),
                            if (phone.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Tooltip(
                                  message: 'Tap to call • Hold to copy',
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: () => _callDealer(phone),
                                      onLongPress: () => _copyToClipboard(
                                        phone,
                                        'Phone number copied to clipboard',
                                      ),
                                      icon: const Icon(Icons.phone_outlined),
                                      label: Text(
                                        phone,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            _infoRow(
                              Icons.location_on_outlined,
                              'Location',
                              location,
                            ),
                            if (mapLat != null &&
                                mapLng != null &&
                                isValidDealerLatLng(mapLat, mapLng)) ...[
                              const SizedBox(height: 10),
                              DealerLocationMapPreview(
                                latitude: mapLat,
                                longitude: mapLng,
                                onOpenInGoogleMaps: () => _openDealerOnGoogleMaps(
                                  mapLat,
                                  mapLng,
                                ),
                              ),
                            ],
                            if (email.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Tooltip(
                                  message: 'Tap to send email • Hold to copy',
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _emailDealer(email),
                                      onLongPress: () => _copyToClipboard(
                                        email,
                                        'Email copied to clipboard',
                                      ),
                                      icon: const Icon(Icons.email_outlined),
                                      label: Text(
                                        email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            _openingHoursTable(openingHours),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'About dealership',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                description,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
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
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            // Match global card layout used on home/favorites.
                            childAspectRatio: 0.62,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _listings.length,
                          itemBuilder: (context, index) {
                            final item = _listings[index];
                            final mapped =
                                mapListingToGlobalCarCardData(context, item);
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                final card =
                                    buildGlobalCarCard(context, mapped);
                                return FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.topCenter,
                                  child: SizedBox(
                                    width: constraints.maxWidth,
                                    child: card,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

