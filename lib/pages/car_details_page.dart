import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/widgets/listing_network_image.dart';
import '../data/car_name_translations.dart';
import '../features/listing/car_details_listing_fields.dart';
import '../features/listing/car_details_recommendations.dart';
import '../features/listing/widgets/car_details_contact_bar.dart';
import '../features/listing/widgets/car_details_horizontal_list.dart';
import '../features/listing/widgets/car_details_seller_section.dart';
import '../features/chat/chat_pages.dart' as carzo_chat;
import '../features/comparison/widgets/comparison_button.dart';
import '../features/listing/car_listing_specs_grid.dart';
import '../l10n/app_localizations.dart';
import '../pages/listing_image_gallery_page.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/debug/app_log.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/i18n/listing_value_labels.dart';
import '../shared/i18n/locale_formatting.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/listings/listing_management.dart'
    show
        confirmAndDeleteListing,
        confirmMarkListingSold,
        openEditListingPage,
        setListingSoldStatus;
import '../shared/listings/listing_owner.dart';
import '../shared/listings/listing_share.dart';
import '../shared/listings/listing_sold_badge.dart';
import '../shared/listings/listing_status.dart';
import '../shared/listings/listing_uploaded_ago.dart';
import '../shared/media/media_url.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../shared/text/pretty_title_case.dart';
import '../shared/trust/report_dialog.dart';
import '../theme_provider.dart';
import '../widgets/network_video_thumbnail.dart';

// Placeholder classes for other pages
class CarDetailsPage extends StatefulWidget {
  final String carId;
  const CarDetailsPage({super.key, required this.carId});
  @override
  State<CarDetailsPage> createState() => _CarDetailsPageState();
}

class _CarDetailsPageState extends State<CarDetailsPage> {
  Map<String, dynamic>? car;
  bool loading = true;
  bool isFavorite = false;
  List<Map<String, dynamic>> similarCars = [];
  List<Map<String, dynamic>> relatedCars = [];
  bool loadingSimilar = false;
  bool loadingRelated = false;
  final PageController _imagePageController = PageController();
  final PageController _similarSnapController = PageController();
  final PageController _relatedSnapController = PageController();
  int _currentImageIndex = 0;
  int _listingColumnsPref = 2;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _contactButtonsKey = GlobalKey();
  bool _showStickyButtons = true;

  void _onListingLayoutChanged() {
    if (!mounted) return;
    setState(() {
      _listingColumnsPref = ListingLayoutPrefs.columns.value;
    });
  }

  String _displayCarTitle(BuildContext context) {
    if (car == null) return '';
    final brand = (car!['brand'] ?? '').toString().trim();
    final model = (car!['model'] ?? '').toString().trim();
    final year = (car!['year'] ?? '').toString().trim();
    final trim = (car!['trim'] ?? '').toString().trim();

    final locBrand = CarNameTranslations.getLocalizedBrand(
      context,
      brand.isEmpty ? null : brand,
    );
    final locModel = CarNameTranslations.getLocalizedModel(
      context,
      brand.isEmpty ? null : brand,
      model.isEmpty ? null : model,
    );
    final parts = <String>[];
    if (locBrand.isNotEmpty) parts.add(locBrand);
    if (locModel.isNotEmpty) parts.add(locModel);
    if (trim.isNotEmpty && trim.toLowerCase() != 'base') {
      parts.add(trim);
    }
    if (year.isNotEmpty) parts.add(year);
    final title = parts.join(' ').trim();
    final raw = title.isNotEmpty ? title : ((car!['title'] ?? '').toString().trim());
    return prettyTitleCase(raw);
  }

  String _displayBrandName(BuildContext context) {
    if (car == null) return '';
    final brand = (car!['brand'] ?? '').toString().trim();
    final locBrand = CarNameTranslations.getLocalizedBrand(
      context,
      brand.isEmpty ? null : brand,
    );
    if (locBrand.isNotEmpty) return prettyTitleCase(locBrand);
    return prettyTitleCase(brand.isNotEmpty ? brand : (car!['title'] ?? '').toString().trim());
  }

  String _displayModelName(BuildContext context) {
    if (car == null) return '';
    final brand = (car!['brand'] ?? '').toString().trim();
    final model = (car!['model'] ?? '').toString().trim();
    final year = (car!['year'] ?? '').toString().trim();

    final locModel = CarNameTranslations.getLocalizedModel(
      context,
      brand.isEmpty ? null : brand,
      model.isEmpty ? null : model,
    );
    final raw = [
      if (locModel.isNotEmpty) locModel else model,
      if (year.isNotEmpty) year,
    ].join(' ').trim();
    return prettyTitleCase(raw);
  }

  Future<void> _loadFavoriteStatus() async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) return;
      // Prefer the loaded car's id (public_id) when available.
      final targetId = (car?['public_id'] ?? car?['id'] ?? widget.carId)
          .toString();
      final fav = await ApiService.isCarFavorited(targetId);
      if (mounted) setState(() => isFavorite = fav);
    } catch (e, st) { logNonFatal(e, st); 
      // ignore: keep existing UI state
    }
  }

  bool get _isListingOwner {
    final auth = Provider.of<AuthService>(context, listen: false);
    return isListingOwner(car, auth.userId);
  }

  Future<void> _editOwnListing() async {
    final current = car;
    if (current == null) return;
    final updated = await openEditListingPage(
      context,
      Map<String, dynamic>.from(current),
    );
    if (!mounted || updated == null) return;
    setState(() => car = {...current, ...updated});
  }

  Future<void> _deleteOwnListing() async {
    final id = listingPrimaryId(car ?? {});
    if (id.isEmpty) return;
    final deleted = await confirmAndDeleteListing(context, id);
    if (!deleted || !mounted) return;
    Navigator.pop(context, {'deleted': true, 'carId': id});
  }

  bool get _isListingSold => isListingSold(car);

  Future<void> _toggleListingSoldStatus() async {
    final id = listingPrimaryId(car ?? {});
    if (id.isEmpty) return;
    if (!_isListingSold) {
      final ok = await confirmMarkListingSold(context);
      if (!ok || !mounted) return;
    }
    final updated = await setListingSoldStatus(
      context,
      id,
      sold: !_isListingSold,
    );
    if (!mounted || updated == null) return;
    final nowSold = isListingSold(updated);
    setState(() {
      car = {...?car, ...updated};
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          trLegacyText(
            context,
            nowSold ? 'Listing marked as sold' : 'Listing is available again',
            ar: nowSold ? 'تم تحديد الإعلان كمباع' : 'الإعلان متاح مجدداً',
            ku: nowSold ? 'ڕیکلام وەک فرۆشراو نیشانکرا' : 'ڕیکلام دووبارە بەردەستە',
          ),
        ),
      ),
    );
  }

  void _onCarDetailMenuSelected(String value) {
    final listingId = listingPrimaryId(car ?? {'id': widget.carId});
    if (value == 'report_listing' && listingId.isNotEmpty) {
      showReportListingDialog(context, listingId: listingId);
      return;
    }
    if (value == 'report_user') {
      final seller = sellerMapFromListing(car);
      final sellerId =
          (seller?['id'] ?? seller?['user_id'] ?? '').toString().trim();
      if (sellerId.isNotEmpty) {
        showReportUserDialog(context, userPublicId: sellerId);
      }
    }
  }

  Future<void> _toggleFavoriteOnServer() async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.loginRequired)),
        );
        return;
      }
      // Backend expects: POST /api/cars/<car_id>/favorite and returns { is_favorited: bool }
      final targetId = (car?['public_id'] ?? car?['id'] ?? widget.carId)
          .toString();
      final res = await ApiService.toggleFavorite(targetId);
      final bool favorited =
          (res['is_favorited'] == true) || (res['favorited'] == true);
      if (mounted) {
        setState(() {
          isFavorite = favorited;
        });
      }
      if (favorited) {
        unawaited(AnalyticsService.trackFavorite(targetId));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)!.error,
            ),
          ),
        ),
      );
    }
  }

  List<String> get _imageUrls {
    final List<String> urls = [];
    if (car != null) {
      final String primary = (car!['image_url'] ?? '').toString();
      final List<dynamic> imgs = (car!['images'] is List)
          ? (car!['images'] as List)
          : const [];
      if (primary.isNotEmpty) {
        urls.add(buildLegacyFullImageUrl(primary));
      }
      for (final dynamic it in imgs) {
        if (it is Map &&
            (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
          continue;
        }
        String s;
        if (it is Map) {
          s = (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
              .toString();
        } else {
          s = it.toString();
        }
        if (s.isNotEmpty) {
          final full = buildLegacyFullImageUrl(s);
          if (!urls.contains(full)) urls.add(full);
        }
      }
      // If no explicit primary but images exist, treat first as primary
      if (urls.isEmpty && imgs.isNotEmpty) {
        final dynamic first = imgs.first;
        if (first is Map &&
            (first['kind'] ?? '').toString().toLowerCase() == 'damage') {
          // First row is damage-only; find first listing image for hero.
          for (final dynamic it in imgs) {
            if (it is Map &&
                (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
              continue;
            }
            final String s = it is Map
                ? (it['image_url'] ??
                          it['url'] ??
                          it['path'] ??
                          it['src'] ??
                          '')
                      .toString()
                : it.toString();
            if (s.isNotEmpty) {
              urls.add(buildLegacyFullImageUrl(s));
              break;
            }
          }
        } else {
          final String s = first is Map
              ? (first['image_url'] ??
                        first['url'] ??
                        first['path'] ??
                        first['src'] ??
                        '')
                    .toString()
              : first.toString();
          if (s.isNotEmpty) urls.add(buildLegacyFullImageUrl(s));
        }
      }
    }
    return urls;
  }

  /// Normalizes API `videos` (strings and/or `{video_url: ...}` maps) to relative paths.
  static List<String> _normalizeVideoPaths(dynamic raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    final List<String> out = [];
    for (final dynamic it in raw) {
      String s = '';
      if (it is String) {
        s = it.trim();
      } else if (it is Map) {
        final map = Map<String, dynamic>.from(it);
        s = (map['video_url'] ?? map['url'] ?? map['path'] ?? '')
            .toString()
            .trim();
      } else {
        s = it.toString().trim();
      }
      if (s.isNotEmpty && !s.startsWith('{') && s != 'null') {
        out.add(s);
      }
    }
    return out;
  }

  Map<String, dynamic> _normalizeCarDetailMap(Map<String, dynamic> src) {
    final m = Map<String, dynamic>.from(src);
    m['videos'] = _normalizeVideoPaths(m['videos']);
    return m;
  }

  List<String> get _videoUrls {
    final List<String> urls = [];
    if (car == null) return urls;
    final paths = _normalizeVideoPaths(car!['videos']);
    for (final String s in paths) {
      final full = buildLegacyFullImageUrl(s);
      if (full.isNotEmpty && !urls.contains(full)) urls.add(full);
    }
    return urls;
  }

  int get _heroMediaCount => _imageUrls.length + _videoUrls.length;

  Widget _buildHeroVideoSlide(BuildContext context, int videoIndex) {
    final videoUrl = _videoUrls[videoIndex];
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        NetworkVideoThumbnailPreview(
          videoUrl: videoUrl,
          maxWidth: 720,
          timeMs: 800,
          fillParent: true,
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'VIDEO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            padding: EdgeInsets.all(14),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
          ),
        ),
      ],
    );
  }

  void _onScroll() {
    final keyContext = _contactButtonsKey.currentContext;
    if (keyContext == null) return;
    final box = keyContext.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final pos = box.localToGlobal(Offset.zero);
    final screenH = MediaQuery.of(context).size.height;
    final visible = pos.dy < screenH;
    if (visible == !_showStickyButtons) return;
    setState(() => _showStickyButtons = !visible);
  }

  @override
  void initState() {
    super.initState();
    _listingColumnsPref = ListingLayoutPrefs.columns.value;
    ListingLayoutPrefs.load();
    ListingLayoutPrefs.columns.addListener(_onListingLayoutChanged);
    _scrollController.addListener(_onScroll);
    unawaited(
      AnalyticsService.trackView(widget.carId.toString()),
    );
    _loadCar();
  }

  @override
  void dispose() {
    try {
      ListingLayoutPrefs.columns.removeListener(_onListingLayoutChanged);
    } catch (e, st) { logNonFatal(e, st); }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _imagePageController.dispose();
    _similarSnapController.dispose();
    _relatedSnapController.dispose();
    super.dispose();
  }

  /// Start loading all listing images into cache so they appear immediately when the user views the carousel.
  void _precacheListingImages() {
    if (!mounted || car == null) return;
    final urls = _imageUrls;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in urls) {
        if (url.isEmpty) continue;
        precacheImage(NetworkImage(url), context);
      }
    });
  }

  void _clampHeroMediaIndex() {
    final n = _heroMediaCount;
    if (n <= 0) {
      if (_currentImageIndex != 0) {
        if (mounted) setState(() => _currentImageIndex = 0);
      }
      return;
    }
    if (_currentImageIndex >= n) {
      final newIndex = n - 1;
      if (mounted) setState(() => _currentImageIndex = newIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_imagePageController.hasClients) {
          _imagePageController.jumpToPage(newIndex);
        }
      });
    }
  }

  Future<void> _loadCar() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cacheKey = 'cache_car_${widget.carId}';

      // Prefer network first so new uploads (images/videos) are not hidden behind stale cache.
      bool appliedFromNetwork = false;
      try {
        final loaded = await ApiService.getCarDetail(widget.carId);
        if (loaded != null && mounted) {
          setState(() {
            car = _normalizeCarDetailMap(loaded);
            loading = false;
          });
          _clampHeroMediaIndex();
          appliedFromNetwork = true;
        }
      } catch (e, st) {
        logNonFatal(e, st);
      }

      if (appliedFromNetwork && car != null) {
        _precacheListingImages();
        unawaited(_loadFavoriteStatus());
        _loadSimilarAndRelated();
        unawaited(sp.setString(cacheKey, json.encode(car)));
        _trackView();
        return;
      }

      // Offline / error: fall back to cached listing
      final cached = sp.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          final data = json.decode(cached);
          if (data is Map) {
            if (mounted) {
              setState(() {
                car = _normalizeCarDetailMap(Map<String, dynamic>.from(data));
                loading = false;
              });
              _clampHeroMediaIndex();
            }
            _precacheListingImages();
            unawaited(_loadFavoriteStatus());
            unawaited(_trackView());
          } else if (data is List && data.isNotEmpty) {
            if (mounted) {
              setState(() {
                car = _normalizeCarDetailMap(
                  Map<String, dynamic>.from(data.first),
                );
                loading = false;
              });
              _clampHeroMediaIndex();
            }
            _precacheListingImages();
            unawaited(_loadFavoriteStatus());
            unawaited(_trackView());
          }
        } catch (e, st) { logNonFatal(e, st); }
      }

      if (!mounted) return;
      setState(() {
        loading = false;
      });
    } catch (e, st) { logNonFatal(e, st); 
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> _trackView() async {
    try {
      final id = (car != null && listingPrimaryId(car!).isNotEmpty)
          ? listingPrimaryId(car!)
          : widget.carId.toString();
      final snap = car != null
          ? Map<String, dynamic>.from(car!)
          : null;
      await AnalyticsService.trackView(id, listingSnapshot: snap);
    } catch (e) {
      appLog('Failed to track view: $e');
    }
  }

  Widget _buildContactButtonsRow() {
    return CarDetailsContactBar(
      onWhatsApp: _openWhatsAppToSeller,
      onCall: _callSeller,
    );
  }

  Future<void> _callSeller() async {
    final String raw = sellerPhoneRawForContact(car) ?? '';
    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.sellerPhoneNotAvailable)),
        );
      }
      return;
    }
    final Uri callUri = Uri.parse('tel:$digits');
    final launched = await launchUrl(callUri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (launched) {
      await AnalyticsService.trackCall(widget.carId.toString());
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to make call')),
      );
    }
  }

  bool get _hasDialableSellerPhone => hasDialableSellerPhone(car);

  Future<void> _openWhatsAppToSeller() async {
    if (car == null) return;
    final String? raw = sellerPhoneRawForContact(car);
    if (raw == null || raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.sellerPhoneNotAvailable,
            ),
          ),
        );
      }
      return;
    }
    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.sellerPhoneNotAvailable,
            ),
          ),
        );
      }
      return;
    }
    final String msg = Uri.encodeComponent(
      'Hi, I am interested in your ${_displayCarTitle(context).isNotEmpty ? _displayCarTitle(context) : 'car'}',
    );
    final Uri waApp = Uri.parse('whatsapp://send?phone=$digits&text=$msg');
    final Uri waWeb = Uri.parse('https://wa.me/$digits?text=$msg');
    bool launched = await launchUrl(
      waApp,
      mode: LaunchMode.externalNonBrowserApplication,
    ).catchError((_) => false);
    if (!launched) {
      launched = await launchUrl(
        waWeb,
        mode: LaunchMode.externalApplication,
      ).catchError((_) => false);
    }
    if (!launched) {
      launched = await launchUrl(
        waWeb,
        mode: LaunchMode.platformDefault,
      ).catchError((_) => false);
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.unableToOpenWhatsApp),
        ),
      );
    } else if (launched) {
      await AnalyticsService.trackMessage(widget.carId.toString());
    }
  }

  void _openCarzoChat() {
    if (car == null || !mounted) return;
    final loc = AppLocalizations.of(context)!;
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.loginRequired)));
      return;
    }

    final String carIdForChat =
        (car!['public_id'] ?? car!['id'] ?? widget.carId).toString().trim();
    if (carIdForChat.isEmpty) return;

    final String title = _displayCarTitle(context).isNotEmpty
        ? _displayCarTitle(context)
        : '${car!['brand'] ?? ''} ${car!['model'] ?? ''} ${car!['year'] ?? ''}'
              .trim();
    final String starterMessage =
        'Hi, I am interested in "$title". What is the price for this listing?';

    String? receiverId;
    String? receiverName;
    final seller = car!['seller'];
    if (seller is Map) {
      final m = Map<String, dynamic>.from(seller);
      final rid = m['id'];
      if (rid != null) {
        final s = rid.toString().trim();
        if (s.isNotEmpty) receiverId = s;
      }
      final fullName = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'
          .trim();
      final at = (m['account_type'] ?? '').toString().trim();
      final ds = (m['dealer_status'] ?? '').toString().trim();
      final dn = (m['dealership_name'] ?? '').toString().trim();
      if (at == 'dealer' && ds == 'approved' && dn.isNotEmpty) {
        receiverName = dn;
      } else if (at == 'dealer') {
        receiverName = fullName.isNotEmpty ? fullName : 'Dealer';
      } else {
        receiverName = (m['name'] ?? m['username'] ?? '').toString().trim();
        if (receiverName.isEmpty && fullName.isNotEmpty) {
          receiverName = fullName;
        }
        if (receiverName.isEmpty) {
          receiverName = null;
        }
      }
    }

    final myId = auth.userId?.toString().trim();
    if (receiverId != null &&
        myId != null &&
        myId.isNotEmpty &&
        receiverId == myId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.chatCarzoOwnListing)));
      return;
    }

    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => carzo_chat.ChatConversationPage(
            carId: carIdForChat,
            receiverId: receiverId,
            receiverName: receiverName,
            initialDraft: starterMessage,
            initialListingPreview: {
              'id': carIdForChat,
              'title': title,
              'price': car!['price'],
              'currency': car!['currency'],
              'location': car!['location'] ?? car!['city'],
              'image_url': car!['image_url'],
              'images': car!['images'],
              'brand': car!['brand'],
              'model': car!['model'],
              'trim': car!['trim'],
              'year': car!['year'],
            },
        ),
      ),
    );
  }

  Future<void> _shareCar() async {
    try {
      if (car == null) return;

      final String id = listingPrimaryId(car!).isNotEmpty
          ? listingPrimaryId(car!)
          : widget.carId.toString();

      await shareListingAsLinkOnly(
        id,
        context: context,
        listingTitle: _displayCarTitle(context),
      );

      // Track share for analytics
      await AnalyticsService.trackShare(widget.carId.toString());
    } catch (e) {
      appLog('Failed to share car: $e');
    }
  }

  Future<void> _loadSimilarAndRelated() async {
    if (car == null) return;
    final String brand = (car!['brand'] ?? '').toString().trim();
    if (brand.isEmpty) return;
    if (!mounted) return;
    setState(() {
      loadingSimilar = true;
      loadingRelated = true;
    });
    try {
      final result = await loadCarDetailsRecommendations(
        car: car!,
        cacheCarId: widget.carId,
      );
      if (mounted) {
        setState(() {
          similarCars = result.similar;
          relatedCars = result.related;
        });
      }
    } catch (e) {
      appLog('Failed to load similar/related: $e');
    } finally {
      if (mounted) {
        setState(() {
          loadingSimilar = false;
          loadingRelated = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final stickyButtons = (!loading && car != null && !_isListingSold && _hasDialableSellerPhone && _showStickyButtons);

    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      body: Stack(
        children: [
          loading
          ? Center(child: CircularProgressIndicator())
          : car == null
          ? Center(child: Text(AppLocalizations.of(context)!.carNotFound))
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  stretch: true,
                  foregroundColor: isLightShell ? Colors.white : null,
                  expandedHeight: 300,
                  leading: Semantics(
                    button: true,
                    label: AppLocalizations.of(context)!.backAction,
                    child: IconButton(
                      icon: Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  actions: [
                    if (_isListingOwner) ...[
                      Semantics(
                        button: true,
                        label: _isListingSold
                            ? trLegacyText(
                                context,
                                'Mark as available',
                                ar: 'متاح مجدداً',
                                ku: 'بەردەست بکەرەوە',
                              )
                            : trLegacyText(
                                context,
                                'Mark as sold',
                                ar: 'تحديد كمباع',
                                ku: 'وەک فرۆشراو',
                              ),
                        child: IconButton(
                          tooltip: _isListingSold
                              ? trLegacyText(
                                  context,
                                  'Mark as available',
                                  ar: 'متاح مجدداً',
                                  ku: 'بەردەست بکەرەوە',
                                )
                              : trLegacyText(
                                  context,
                                  'Mark as sold',
                                  ar: 'تحديد كمباع',
                                  ku: 'وەک فرۆشراو',
                                ),
                          onPressed: _toggleListingSoldStatus,
                          icon: Icon(
                            _isListingSold
                                ? Icons.undo_outlined
                                : Icons.sell_outlined,
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: AppLocalizations.of(context)!.editAction,
                        child: IconButton(
                          tooltip: AppLocalizations.of(context)!.editAction,
                          onPressed: _editOwnListing,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: AppLocalizations.of(context)!.deleteAction,
                        child: IconButton(
                          tooltip: AppLocalizations.of(context)!.deleteAction,
                          onPressed: _deleteOwnListing,
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    Semantics(
                      button: true,
                      label: AppLocalizations.of(context)!.shareAction,
                      child: IconButton(
                        tooltip: AppLocalizations.of(context)!.shareAction,
                        onPressed: _shareCar,
                        icon: const Icon(Icons.share_outlined),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: AppLocalizations.of(context)!.favoriteAction,
                      child: IconButton(
                        tooltip: AppLocalizations.of(context)!.favoriteAction,
                        onPressed: _toggleFavoriteOnServer,
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                        ),
                      ),
                    ),
                    if (!_isListingOwner &&
                        ApiService.accessToken != null &&
                        ApiService.accessToken!.isNotEmpty)
                      PopupMenuButton<String>(
                        onSelected: _onCarDetailMenuSelected,
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'report_listing',
                            child: Text(
                              trLegacyText(
                                ctx,
                                'Report listing',
                                ar: 'الإبلاغ عن الإعلان',
                                ku: 'ڕاپۆرتکردنی ڕیکلام',
                              ),
                            ),
                          ),
                          if ((sellerMapFromListing(car)?['id'] ??
                                  sellerMapFromListing(car)?['user_id'] ??
                                  '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            PopupMenuItem(
                              value: 'report_user',
                              child: Text(
                                trLegacyText(
                                  ctx,
                                  'Report seller',
                                  ar: 'الإبلاغ عن البائع',
                                  ku: 'ڕاپۆرتکردنی فرۆشیار',
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.zero,
                          child: GestureDetector(
                            onTap: () {
                              if (_heroMediaCount == 0) return;
                              final idx = _currentImageIndex.clamp(
                                0,
                                _heroMediaCount - 1,
                              );
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ListingImageGalleryPage(
                                    imageUrls: _imageUrls,
                                    videoUrls: _videoUrls,
                                    initialIndex: idx,
                                  ),
                                ),
                              );
                            },
                            child: (_heroMediaCount > 0)
                                ? PageView.builder(
                                    controller: _imagePageController,
                                    onPageChanged: (idx) => setState(
                                      () => _currentImageIndex = idx,
                                    ),
                                    itemCount: _heroMediaCount,
                                    itemBuilder: (context, index) {
                                      if (index < _imageUrls.length) {
                                        final url = _imageUrls[index];
                                        return listingNetworkImage(
                                          url,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                        );
                                      }
                                      return _buildHeroVideoSlide(
                                        context,
                                        index - _imageUrls.length,
                                      );
                                    },
                                  )
                                : Container(
                                    color: Colors.grey[900],
                                    width: double.infinity,
                                    child: Icon(
                                      Icons.directions_car,
                                      size: 60,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                          ),
                        ),
                        if (_heroMediaCount > 1)
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: true,
                              child: Center(
                                child: () {
                                  const int kMaxVisible = 6;
                                  final int total = _heroMediaCount;
                                  final int visible =
                                      total < kMaxVisible ? total : kMaxVisible;
                                  if (visible <= 1) return const SizedBox.shrink();

                                  int computeDotStart(int index) {
                                    if (total <= visible) return 0;
                                    final int maxStart =
                                        (total - visible).clamp(0, total);
                                    return (index - (visible - 1))
                                        .clamp(0, maxStart);
                                  }

                                  final int start =
                                      computeDotStart(_currentImageIndex);

                                  Widget buildDotRow(int startIndex) {
                                    return Row(
                                      key: ValueKey<int>(startIndex),
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(visible, (j) {
                                        final i = startIndex + j;
                                        final active = i == _currentImageIndex;
                                        return Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                          ),
                                          width: active ? 10 : 6,
                                          height: active ? 10 : 6,
                                          decoration: BoxDecoration(
                                            color: active
                                                ? Colors.white
                                                : Colors.white70,
                                            shape: BoxShape.circle,
                                          ),
                                        );
                                      }),
                                    );
                                  }

                                  return buildDotRow(start);
                                }(),
                              ),
                            ),
                          ),
                        if (_isListingSold)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xCCD32F2F),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white54,
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    listingSoldLabel(context),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 26,
                                      letterSpacing: 2.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isLightShell
                          ? AppThemes.lightAppBackground
                          : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    child: Theme(
                      data: isLightShell
                          ? Theme.of(context)
                          : AppThemes.darkTheme,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Quick Sell Banner
                          if (car!['is_quick_sell'] == true ||
                              car!['is_quick_sell'] == 'true')
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              margin: EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.orange, Colors.deepOrange],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.flash_on,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    AppLocalizations.of(context)!.quickSell,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Brand full width; price aligns with model line (same row as model)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _displayBrandName(context),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isLightShell
                                            ? AppThemes.darkHomeShellBackground
                                            : Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (car!['price'] != null &&
                                      _displayModelName(context).isEmpty) ...[
                                    SizedBox(width: 12),
                                    Text(
                                      formatCurrency(
                                        context,
                                        car!['price'],
                                      ),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFFF6B00),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (_displayModelName(context).isNotEmpty) ...[
                                SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _displayModelName(context),
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: isLightShell
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant
                                              : Colors.white70,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (car!['price'] != null) ...[
                                      SizedBox(width: 12),
                                      Text(
                                        formatCurrency(
                                          context,
                                          car!['price'],
                                        ),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFFF6B00),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                          // City + listing age under model/price
                          Builder(
                            builder: (context) {
                              final cityDetail =
                                  (listingFirstNonEmpty(car!, [
                                            'city',
                                            'location',
                                          ]) ??
                                          '')
                                      .trim();
                              final cityLabelStyle = TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isLightShell
                                    ? const Color(0xFF757575)
                                    : Colors.white70,
                              );
                              final uploadedDetail = listingUploadedAgo(
                                context,
                                car!,
                              );
                              if (cityDetail.isEmpty &&
                                  uploadedDetail.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: cityDetail.isEmpty
                                            ? const SizedBox.shrink()
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.location_city,
                                                    size: 14,
                                                    color: isLightShell
                                                        ? const Color(
                                                            0xFF757575,
                                                          )
                                                        : Colors.white70,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      '${AppLocalizations.of(context)!.cityLabel}: '
                                                      '${translateListingValue(context, listingFirstNonEmpty(car!, ['city', 'location'])) ?? listingFirstNonEmpty(car!, ['city', 'location'])}',
                                                      style: cityLabelStyle,
                                                      // Allow long cities like "Sulaymaniyah" to show fully.
                                                      maxLines: 2,
                                                      overflow: TextOverflow.clip,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                      if (uploadedDetail.isNotEmpty) ...[
                                        if (cityDetail.isNotEmpty)
                                          const SizedBox(width: 8),
                                        Text(
                                          uploadedDetail,
                                          style: cityLabelStyle.copyWith(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),

                          Divider(
                            height: 1,
                            thickness: 1,
                            color: isLightShell
                                ? const Color(0xFFE0E0E0)
                                : Colors.white24,
                          ),
                          SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context)!.specificationsLabel,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6B00),
                            ),
                          ),
                          SizedBox(height: 20),
                          _buildSpecsGrid(),
                          SizedBox(height: 24),

                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_isListingSold && _hasDialableSellerPhone) ...[
                                Container(
                                  key: _contactButtonsKey,
                                  child: _buildContactButtonsRow(),
                                ),
                                SizedBox(height: 6),
                              ],
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: ComparisonButton(car: car!),
                              ),
                              if (!_isListingSold) ...[
                              SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Color(0xFFFF6B00),
                                    side: BorderSide(color: Color(0xFFFF6B00)),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size(0, 46),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(17),
                                    ),
                                  ),
                                  onPressed: _openCarzoChat,
                                  icon: Icon(Icons.forum_outlined, size: 19),
                                  label: Text(
                                    AppLocalizations.of(context)!.chatOnCarzo,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              ],
                              CarDetailsSellerSection(car: car!),
                            ],
                          ),
                          SizedBox(height: 28),
                          if (similarCars.isNotEmpty) ...[
                            Text(
                              AppLocalizations.of(context)!.similarListings,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                            ),
                            SizedBox(height: 12),
                            CarDetailsHorizontalList(
                              items: similarCars,
                              listingColumnsPref: _listingColumnsPref,
                              snapController: _similarSnapController,
                            ),
                            SizedBox(height: 28),
                          ] else if (loadingSimilar) ...[
                            Text(
                              AppLocalizations.of(context)!.similarListings,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            SizedBox(height: 28),
                          ],
                          if (relatedCars.isNotEmpty) ...[
                            Text(
                              AppLocalizations.of(context)!.relatedListings,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                            ),
                            SizedBox(height: 12),
                            CarDetailsHorizontalList(
                              items: relatedCars,
                              listingColumnsPref: _listingColumnsPref,
                              snapController: _relatedSnapController,
                            ),
                          ] else if (loadingRelated) ...[
                            Text(
                              AppLocalizations.of(context)!.relatedListings,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (stickyButtons)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: _buildContactButtonsRow(),
            ),
        ],
      ),
    );
  }

  Widget _buildSpecsGrid() => buildCarListingSpecsGrid(context, car!);
}
