import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/config.dart';
import '../shared/media/media_url.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/text/pretty_title_case.dart';
import '../data/car_name_translations.dart';
import '../l10n/app_localizations.dart';
import '../globals.dart';

part 'tiktok_scroll_listing_card.dart';

class TikTokScrollPage extends StatefulWidget {
  final List<Map<String, dynamic>> cars;
  final int initialIndex;

  const TikTokScrollPage({
    super.key,
    required this.cars,
    required this.initialIndex,
  });

  @override
  State<TikTokScrollPage> createState() => _TikTokScrollPageState();
}

class _TikTokScrollPageState extends State<TikTokScrollPage> {
  late final PageController _pageController;
  late List<Map<String, dynamic>> _cars;

  @override
  void initState() {
    super.initState();
    _cars = List.from(widget.cars);
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    if (_cars.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Text(
            loc.noListingsFound,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _cars.length,
        itemBuilder: (context, index) {
          final car = _cars[index];
          return _TikTokListingCard(car: car);
        },
      ),
    );
  }
}
