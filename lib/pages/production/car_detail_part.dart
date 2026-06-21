part of 'carzo_pages.dart';

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
          _trLegacyText(
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
      final seller = _sellerMap();
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
      ).showSnackBar(SnackBar(content: Text(e.toString())));
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
        urls.add(_buildFullImageUrl(primary));
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
          final full = _buildFullImageUrl(s);
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
              urls.add(_buildFullImageUrl(s));
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
          if (s.isNotEmpty) urls.add(_buildFullImageUrl(s));
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
      final full = _buildFullImageUrl(s);
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
      _debugLog('Failed to track view: $e');
    }
  }

  Widget _buildContactButtonsRow() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor: Colors.black26,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(0, 46),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: const Icon(Icons.chat, size: 19),
              label: Text(
                AppLocalizations.of(context)!.chatOnWhatsApp,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: _openWhatsAppToSeller,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor: Colors.black26,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(0, 46),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: const Icon(Icons.phone, size: 19),
              label: Text(
                _trLegacyText(context, 'Call Seller', ar: 'اتصل بالبائع', ku: 'پەیوەندی بە فرۆشیار'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () async {
                final String raw = _sellerPhoneRawForContact() ?? '';
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
                bool launched = await launchUrl(callUri, mode: LaunchMode.externalApplication).catchError((_) => false);
                if (launched) {
                  await AnalyticsService.trackCall(widget.carId.toString());
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Unable to make call')),
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Listing phone for WhatsApp/call: `contact_phone` or nested `seller.*` (API shape varies).
  String? _sellerPhoneRawForContact() {
    if (car == null) return null;
    final direct = car!['contact_phone']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final seller = car!['seller'];
    if (seller is Map) {
      final m = Map<String, dynamic>.from(seller);
      for (final key in [
        'phone_number',
        'phone',
        'whatsapp',
        'mobile',
        'contact_phone',
      ]) {
        final v = m[key]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  bool get _hasDialableSellerPhone {
    final raw = _sellerPhoneRawForContact();
    if (raw == null || raw.isEmpty) return false;
    return raw.replaceAll(RegExp(r'[^0-9]'), '').isNotEmpty;
  }

  Future<void> _openWhatsAppToSeller() async {
    if (car == null) return;
    final String? raw = _sellerPhoneRawForContact();
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
        builder: (ctx) => AuthGuard(
          child: carzo_chat.ChatConversationPage(
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
      _debugLog('Failed to share car: $e');
    }
  }

  Future<void> _loadSimilarAndRelated() async {
    if (car == null) return;
    final String brand = (car!['brand'] ?? '').toString().trim();
    final String model = (car!['model'] ?? '').toString().trim();
    if (brand.isEmpty) return;
    if (!mounted) return;
    setState(() {
      loadingSimilar = true;
      loadingRelated = true;
    });
    try {
      final sp = await SharedPreferences.getInstance();
      final simKey = 'cache_similar_${widget.carId}';
      final relKey = 'cache_related_${widget.carId}';
      // Load cached similar/related first
      try {
        final simCached = sp.getString(simKey);
        if (simCached != null && simCached.isNotEmpty) {
          final simData = json.decode(simCached);
          if (simData is List && mounted) {
            setState(() {
              similarCars = simData.cast<Map<String, dynamic>>();
            });
          }
        }
        final relCached = sp.getString(relKey);
        if (relCached != null && relCached.isNotEmpty) {
          final relData = json.decode(relCached);
          if (relData is List && mounted) {
            setState(() {
              relatedCars = relData.cast<Map<String, dynamic>>();
            });
          }
        }
      } catch (e, st) { logNonFatal(e, st); }
      List<Map<String, dynamic>> toCarList(dynamic decoded) {
        final dynamic raw = (decoded is Map)
            ? (decoded['cars'] ?? decoded['data'] ?? decoded['list'] ?? decoded)
            : decoded;
        final List<dynamic> list = raw is List ? raw : const <dynamic>[];
        return list
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
            .toList();
      }

      final currentIds = <String>{
        widget.carId.toString(),
        (car!['id'] ?? '').toString(),
        (car!['public_id'] ?? '').toString(),
      }..removeWhere((e) => e.trim().isEmpty);

      // Similar: strictly same brand + model
      if (model.isNotEmpty) {
        final simData = await ApiService.getCars(
          page: 1,
          perPage: 20,
          brand: brand,
          model: model,
        );
        final list = toCarList(simData)
            .where((e) {
              final id = (e['public_id'] ?? e['id'] ?? '').toString();
              return id.isEmpty || !currentIds.contains(id);
            })
            .take(12)
            .toList();
        if (mounted) setState(() => similarCars = list);
        unawaited(sp.setString(simKey, json.encode(similarCars)));
      } else {
        if (mounted) setState(() => similarCars = []);
      }

      // Related: same brand and matching key attributes ("same filters")
      // Build a query around the viewed car's attributes: price/year ranges, transmission, fuel, condition, city
      // Price band: +/- 15%
      final num? priceNum = (car!['price'] is num)
          ? (car!['price'] as num)
          : num.tryParse((car!['price'] ?? '').toString());
      double? priceMin;
      double? priceMax;
      if (priceNum != null && priceNum > 0) {
        priceMin = (priceNum * 0.85).floorToDouble();
        priceMax = (priceNum * 1.15).ceilToDouble();
      }
      // Year band: +/- 2 years
      final int? yearNum = (car!['year'] is int)
          ? (car!['year'] as int)
          : int.tryParse((car!['year'] ?? '').toString());
      int? yearMin;
      int? yearMax;
      if (yearNum != null && yearNum > 0) {
        yearMin = yearNum - 2;
        yearMax = yearNum + 2;
      }
      final relData = await ApiService.getCars(
        page: 1,
        perPage: 20,
        brand: brand,
        yearMin: yearMin,
        yearMax: yearMax,
        priceMin: priceMin,
        priceMax: priceMax,
        location: (car!['city'] ?? car!['location'] ?? '').toString().trim().isEmpty
            ? null
            : (car!['city'] ?? car!['location']).toString().trim(),
        condition: (car!['condition'] ?? '').toString().trim().isEmpty
            ? null
            : (car!['condition'] ?? '').toString().trim(),
        bodyType: (car!['body_type'] ?? car!['bodyType'] ?? '').toString().trim().isEmpty
            ? null
            : (car!['body_type'] ?? car!['bodyType']).toString().trim(),
        transmission: (car!['transmission'] ?? '').toString().trim().isEmpty
            ? null
            : (car!['transmission'] ?? '').toString().trim(),
        driveType: (car!['drive_type'] ?? car!['driveType'] ?? '').toString().trim().isEmpty
            ? null
            : (car!['drive_type'] ?? car!['driveType']).toString().trim(),
        engineType: (car!['engine_type'] ?? car!['engineType'] ?? '').toString().trim().isEmpty
            ? null
            : (car!['engine_type'] ?? car!['engineType']).toString().trim(),
      );
      final list = toCarList(relData)
          .where((e) {
            final id = (e['public_id'] ?? e['id'] ?? '').toString();
            return id.isEmpty || !currentIds.contains(id);
          })
          .take(12)
          .toList();
      if (mounted) setState(() => relatedCars = list);
      unawaited(sp.setString(relKey, json.encode(relatedCars)));
    } catch (e) {
      _debugLog('Failed to load similar/related: $e');
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
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  actions: [
                    if (_isListingOwner) ...[
                      IconButton(
                        tooltip: _isListingSold
                            ? _trLegacyText(
                                context,
                                'Mark as available',
                                ar: 'متاح مجدداً',
                                ku: 'بەردەست بکەرەوە',
                              )
                            : _trLegacyText(
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
                      IconButton(
                        tooltip: AppLocalizations.of(context)!.editAction,
                        onPressed: _editOwnListing,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: AppLocalizations.of(context)!.deleteAction,
                        onPressed: _deleteOwnListing,
                        icon: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    IconButton(
                      tooltip: AppLocalizations.of(context)!.shareAction,
                      onPressed: _shareCar,
                      icon: const Icon(Icons.share_outlined),
                    ),
                    IconButton(
                      onPressed: _toggleFavoriteOnServer,
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
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
                              _trLegacyText(
                                ctx,
                                'Report listing',
                                ar: 'الإبلاغ عن الإعلان',
                                ku: 'ڕاپۆرتکردنی ڕیکلام',
                              ),
                            ),
                          ),
                          if ((_sellerMap()?['id'] ??
                                  _sellerMap()?['user_id'] ??
                                  '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            PopupMenuItem(
                              value: 'report_user',
                              child: Text(
                                _trLegacyText(
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
                                        return _listingNetworkImage(
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
                                        return AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 180),
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

                                  return AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, anim) {
                                      final offset = Tween<Offset>(
                                        begin: Offset(start == 0 ? 0.12 : -0.12, 0),
                                        end: Offset.zero,
                                      ).animate(anim);
                                      return FadeTransition(
                                        opacity: anim,
                                        child: SlideTransition(
                                          position: offset,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: buildDotRow(start),
                                  );
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
                                      _formatCurrencyGlobal(
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
                                        _formatCurrencyGlobal(
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
                                  (_getFirstNonEmpty(car!, [
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
                              final uploadedDetail = _listingUploadedAgo(
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
                                                      '${_translateValueGlobal(context, _getFirstNonEmpty(car!, ['city', 'location'])) ?? _getFirstNonEmpty(car!, ['city', 'location'])}',
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
                              _buildSellerProfileSection(),
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
                            _buildHorizontalList(
                              similarCars,
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
                            _buildHorizontalList(
                              relatedCars,
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

  // Safely get the first non-empty string value from several possible keys (handles snake_case and camelCase)
  String? _getFirstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      final String stringValue = value.toString().trim();
      if (stringValue.isNotEmpty) return stringValue;
    }
    return null;
  }

  Map<String, dynamic>? _sellerMap() {
    if (car == null) return null;
    final dynamic seller = car!['seller'];
    if (seller is Map) {
      return Map<String, dynamic>.from(seller);
    }
    return null;
  }

  Widget _buildSellerProfileSection() {
    final Map<String, dynamic> seller = _sellerMap() ?? <String, dynamic>{};
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    final String firstName = (seller['first_name'] ?? '').toString().trim();
    final String lastName = (seller['last_name'] ?? '').toString().trim();
    final String fullName = '$firstName $lastName'.trim();
    final String name =
        (_getFirstNonEmpty(seller, ['name', 'display_name']) ??
                _getFirstNonEmpty(car ?? <String, dynamic>{}, [
                  'seller_name',
                  'owner_name',
                  'posted_by',
                ]) ??
                '')
            .trim();
    final String phone =
        (_getFirstNonEmpty(seller, ['phone_number', 'phone', 'mobile']) ??
                _sellerPhoneRawForContact() ??
                '')
            .trim();
    final String email =
        ((_getFirstNonEmpty(seller, ['email']) ??
                    _getFirstNonEmpty(car ?? <String, dynamic>{}, [
                      'seller_email',
                    ])) ??
                '')
            .trim();
    final String city =
        ((_getFirstNonEmpty(seller, ['city', 'location']) ??
                    _getFirstNonEmpty(car ?? <String, dynamic>{}, [
                      'city',
                      'location',
                    ])) ??
                '')
            .trim();
    final String avatarRaw =
        ((_getFirstNonEmpty(seller, [
                      'profile_picture',
                      'avatar',
                      'avatar_url',
                      'image_url',
                      'photo_url',
                    ]) ??
                    _getFirstNonEmpty(car ?? <String, dynamic>{}, [
                      'seller_profile_picture',
                    ])) ??
                '')
            .trim();
    final String avatarUrl = avatarRaw.isEmpty
        ? ''
        : _buildFullImageUrl(avatarRaw);

    final bool isVerified =
        seller['is_verified'] == true || seller['verified'] == true;
    final String accountType = (seller['account_type'] ?? '').toString().trim();
    final String dealerStatus = (seller['dealer_status'] ?? '').toString().trim();
    final String dealershipName =
        (seller['dealership_name'] ?? '').toString().trim();
    final String dealershipLocation =
        (seller['dealership_location'] ?? '').toString().trim();
    final String dealershipDescription =
        (seller['dealership_description'] ?? seller['dealer_description'] ?? '')
            .toString()
            .trim();
    final bool isApprovedDealer =
        accountType == 'dealer' && dealerStatus == 'approved';
    final bool isDealerSeller = accountType == 'dealer';
    final String sellerTypeLabel = isDealerSeller
        ? _trLegacyText(context, 'Dealership', ar: 'معرض', ku: 'نمایشگا')
        : _trLegacyText(
            context,
            'Private seller',
            ar: 'بائع فردي',
            ku: 'فرۆشیاری تاک',
          );
    final String dealerPublicId =
        (seller['id'] ?? seller['user_id'] ?? '').toString().trim();
    final bool canOpenDealerPage =
        isApprovedDealer && dealerPublicId.isNotEmpty;

    final String displayName = isDealerSeller
        ? ((isApprovedDealer && dealershipName.isNotEmpty)
              ? dealershipName
              : (name.isNotEmpty
                    ? name
                    : (fullName.isNotEmpty
                          ? fullName
                          : _trLegacyText(
                              context,
                              'Dealer',
                              ar: 'وكيل',
                              ku: 'وەکیل',
                            ))))
        : sellerTypeLabel;

    final String locationShown =
        (isApprovedDealer && dealershipLocation.isNotEmpty)
            ? dealershipLocation
            : city;

    String initials = 'S';
    if (displayName.isNotEmpty) {
      final List<String> parts = displayName
          .split(RegExp(r'\s+'))
          .where((s) => s.trim().isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else {
        initials = parts.first[0].toUpperCase();
      }
    }

    Widget detailRow(IconData icon, String label, String value) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: const Color(0xFFFF6B00)),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    color: isLight
                        ? AppThemes.darkHomeShellBackground
                        : Colors.white70,
                  ),
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canOpenDealerPage
            ? () => Navigator.pushNamed(
                  context,
                  '/dealer/profile',
                  arguments: {'dealerPublicId': dealerPublicId},
                )
            : null,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xFF1A120E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isLight ? const Color(0x1A000000) : const Color(0x33FF6B00),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0x26FF6B00),
                    backgroundImage: isDealerSeller && avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: !isDealerSeller
                        ? const Icon(
                            Icons.person,
                            color: Color(0xFFFF6B00),
                            size: 26,
                          )
                        : avatarUrl.isEmpty
                        ? Text(
                            initials,
                            style: const TextStyle(
                              color: Color(0xFFFF6B00),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isDealerSeller) ...[
                          Text(
                            sellerTypeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black54 : Colors.white60,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isLight
                                ? AppThemes.darkHomeShellBackground
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDealerSeller && isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x1A4CAF50),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified,
                            color: Color(0xFF4CAF50),
                            size: 13,
                          ),
                          SizedBox(width: 4),
                          Text(
                            _trLegacyText(
                              context,
                              'Verified',
                              ar: 'موثّق',
                              ku: 'پشتڕاستکراوە',
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF4CAF50),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (isDealerSeller) ...[
                detailRow(
                  Icons.phone_outlined,
                  _trLegacyText(context, 'Phone', ar: 'الهاتف', ku: 'تەلەفۆن'),
                  phone,
                ),
                detailRow(
                  Icons.email_outlined,
                  _trLegacyText(context, 'Email', ar: 'البريد الإلكتروني', ku: 'ئیمەیل'),
                  email,
                ),
              ],
              if (isDealerSeller)
                detailRow(
                  Icons.location_on_outlined,
                  _trLegacyText(context, 'Location', ar: 'الموقع', ku: 'شوێن'),
                  locationShown,
                ),
              if (isDealerSeller)
                detailRow(
                  Icons.notes_outlined,
                  AppLocalizations.of(context)?.descriptionTitle ?? 'Description',
                  dealershipDescription,
                ),
              if (canOpenDealerPage)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _trLegacyText(
                      context,
                      'Tap to open dealership page',
                      ar: 'اضغط لفتح صفحة المعرض',
                      ku: 'کرتە بکە بۆ کردنەوەی پەڕەی نمایشگا',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: isLight ? Colors.black54 : Colors.white60,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpecsGrid() => buildCarListingSpecsGrid(context, car!);

  Widget _buildHorizontalList(
    List<Map<String, dynamic>> items, {
    required PageController snapController,
  }) {
    // When the user selects "one listing per row" (list layout),
    // render similar/related as a horizontal swipe list of full-width rows.
    if (_listingColumnsPref == 1) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final double viewportW = constraints.maxWidth;
          final double itemW = (viewportW.isFinite && viewportW > 0)
              ? viewportW
              : MediaQuery.of(context).size.width;
          final double h = (itemW.isFinite && itemW > 0) ? (itemW / 2.78) : 140;

          return SizedBox(
            height: h,
            child: PageView.builder(
              controller: snapController,
              physics: const PageScrollPhysics(),
              pageSnapping: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = Map<String, dynamic>.from(items[index]);
                final normalized = mapListingToGlobalCarCardData(context, item);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: SizedBox(
                    width: itemW,
                    height: h,
                    child: buildGlobalCarCard(
                      context,
                      normalized,
                      listLayout: true,
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    }

    // Default: keep the horizontal carousel in grid-card style.
    return SizedBox(
      height: 320,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = Map<String, dynamic>.from(items[index]);
          final normalized = mapListingToGlobalCarCardData(context, item);
          return SizedBox(
            width: 200,
            child: AspectRatio(
              // Match Home grid card aspect ratio so layout doesn't overflow.
              aspectRatio: 0.72,
              child: buildGlobalCarCard(context, normalized),
            ),
          );
        },
      ),
    );
  }
}

/// Full URLs for listing images tagged `kind: damage` (shared by detail + specs grid).
List<String> listingDamageImageFullUrls(Map<String, dynamic> car) {
  final List<String> urls = [];
  final List<dynamic> imgs =
      (car['images'] is List) ? (car['images'] as List) : const [];
  for (final dynamic it in imgs) {
    if (it is! Map) continue;
    if ((it['kind'] ?? '').toString().toLowerCase() != 'damage') continue;
    final s =
        (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '').toString();
    if (s.isNotEmpty) {
      final full = _buildFullImageUrl(s);
      if (!urls.contains(full)) urls.add(full);
    }
  }
  return urls;
}

/// Damage photos for preview / review: API `images` with `kind: damage`, else
/// sell-flow `damage_images` (XFile or path strings) before submit.
List<dynamic> listingDamagePreviewEntries(Map<String, dynamic> car) {
  final List<dynamic> out = [];
  for (final url in listingDamageImageFullUrls(car)) {
    if (url.trim().isNotEmpty) out.add(url);
  }
  if (out.isNotEmpty) return out;
  final raw = car['damage_images'];
  if (raw is! List) return out;
  for (final e in raw) {
    if (e is XFile) {
      if (e.path.trim().isNotEmpty) out.add(e);
    } else {
      final s = e?.toString().trim() ?? '';
      if (s.isNotEmpty) out.add(e);
    }
  }
  return out;
}

/// Specification grid matching [CarDetailsPage] (shared with sell-flow review).
Widget buildCarListingSpecsGrid(
  BuildContext context,
  Map<String, dynamic> car,
) {
  final List<dynamic> damagePreviewEntries = listingDamagePreviewEntries(car);
  String? pickNE(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      final String stringValue = value.toString().trim();
      if (stringValue.isNotEmpty) return stringValue;
    }
    return null;
  }

  String formatNumericLabel(String raw) {
    try {
      final num? value = num.tryParse(raw.replaceAll(RegExp(r'[^0-9\.-]'), ''));
      if (value == null) return raw;
      return _decimalFormatterGlobal(context).format(value);
    } catch (e, st) { logNonFatal(e, st); 
      return raw;
    }
  }

  String orDash(String? s) {
    final v = (s ?? '').toString().trim();
    return v.isEmpty ? '—' : v;
  }

  Widget detailRowSpec({
    required IconData icon,
    required String label,
    required String? value,
    Widget? valueWidget,
    VoidCallback? onTap,
  }) {
    if (valueWidget == null && (value == null || value.isEmpty)) {
      return SizedBox.shrink();
    }
    final isLight = Theme.of(context).brightness == Brightness.light;
    final content = Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: onTap != null
            ? (isLight ? const Color(0xFFFFF2E8) : Colors.white.withValues(alpha: 0.09))
            : (isLight ? const Color(0xFFF3F3F3) : Colors.white.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: onTap != null
              ? const Color(0xFFFF6B00).withValues(alpha: isLight ? 0.34 : 0.42)
              : (isLight ? const Color(0xFFE0E0E0) : Colors.white12),
          width: onTap != null ? 1.2 : 1,
        ),
        boxShadow: onTap != null
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: onTap != null
                  ? const Color(0xFFFF6B00)
                  : const Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.black),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isLight ? const Color(0xFF3A3A3A) : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (valueWidget != null)
            valueWidget
          else if (onTap != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    value!,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Color(0xFFFF6B00)),
              ],
            )
          else
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Color(0xFFFF6B00),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                value!,
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }

  Widget specCard(_SpecItem item) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double labelFontSize =
              (constraints.maxWidth * 0.13).clamp(9.0, 11.0);
          final double valueFontSize =
              (constraints.maxWidth * 0.16).clamp(10.0, 14.0);

          final labelStyle = TextStyle(
            fontSize: labelFontSize,
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            height: 1.05,
          );
          final valueStyle = TextStyle(
            fontSize: valueFontSize,
            height: 1.0,
            color: Colors.black,
            fontWeight: FontWeight.w800,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 6,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: constraints.maxWidth * 0.13,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              constraints.maxWidth - (constraints.maxWidth * 0.13) - 4,
                        ),
                        child: AutoSizeText(
                          item.label,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          softWrap: false,
                          textScaleFactor: 1.0,
                          style: labelStyle,
                          minFontSize: 7,
                          stepGranularity: 0.5,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  vertical: math.max(3.0, constraints.maxHeight * 0.02),
                  horizontal: 6,
                ),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.black.withValues(alpha: 0.22),
                ),
              ),
              Expanded(
                flex: 5,
                child: Center(
                  child: AutoSizeText(
                    item.value!,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    textScaleFactor: 1.0,
                    style: valueStyle,
                    minFontSize: 9,
                    stepGranularity: 0.5,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  final String mileageVal = car['mileage'] != null
      ? '${_localizeDigitsGlobal(context, formatNumericLabel(car['mileage'].toString()))} ${AppLocalizations.of(context)!.unit_km}'
      : '—';

  final String? transRaw = pickNE(car, ['transmission']);
  final String transmissionVal = orDash(
    _translateValueGlobal(context, transRaw) ?? transRaw,
  );

  final String? engineSizePrimary = pickNE(car, [
    'engine_size',
    'engine_size_liters',
    'engine_size_l',
    'engineSize',
    'engineSizeLiters',
    'engine',
  ]) ??
      () {
        final dynamic specsRaw = car['specs'] ?? car['spec'] ?? car['details'];
        if (specsRaw is Map) {
          final specs = Map<String, dynamic>.from(specsRaw);
          return pickNE(specs, [
            'engine_size',
            'engine_size_liters',
            'engine_size_l',
            'engineSize',
            'engineSizeLiters',
            'engine',
          ]);
        }
        return null;
      }();
  final String engineCardVal = () {
    final raw = engineSizePrimary?.toString().trim() ?? '';
    if (raw.isEmpty) return '—';
    final eng = OnlineSpecVariant.parseLeadingEngineLiters(raw) ??
        double.tryParse(raw);
    if (eng != null && eng > 0) {
      return '${_localizeDigitsGlobal(context, eng.toStringAsFixed(1))}${AppLocalizations.of(context)!.unit_liter_suffix}';
    }
    return _localizeDigitsGlobal(context, raw);
  }();

  final String? cylRawPrimary = pickNE(car, [
    'cylinder_count',
    'cylinders',
    'cylinderCount',
  ]);
  final String cylinderVal = cylRawPrimary != null
      ? _localizeDigitsGlobal(context, cylRawPrimary)
      : '—';

  final String titleStatusVal = orDash(
    car['title_status'] != null
        ? (car['title_status'].toString().toLowerCase() == 'damaged'
              ? (car['damaged_parts'] != null
                    ? AppLocalizations.of(context)!.titleStatusDamagedWithParts(
                        _localizeDigitsGlobal(
                          context,
                          car['damaged_parts'].toString(),
                        ),
                      )
                    : AppLocalizations.of(context)!.value_title_damaged)
              : AppLocalizations.of(context)!.value_title_clean)
        : null,
  );

  final String? fuelRaw = pickNE(car, ['fuel_type', 'fuelType', 'fuel']);
  final String fuelVal = orDash(
    _translateValueGlobal(context, fuelRaw) ?? fuelRaw,
  );

  final List<_SpecItem> primary = [
    _SpecItem(
      icon: Icons.speed,
      label: AppLocalizations.of(context)!.mileageLabel,
      value: mileageVal,
    ),
    _SpecItem(
      icon: Icons.settings_input_component,
      label: AppLocalizations.of(context)!.detail_cylinders,
      value: cylinderVal,
    ),
    _SpecItem(
      icon: Icons.straighten,
      label: AppLocalizations.of(context)!.detail_engine,
      value: engineCardVal,
    ),
    _SpecItem(
      icon: Icons.public,
      label: AppLocalizations.of(context)!.regionSpecsLabel,
      value: orDash(() {
        final raw = pickNE(car, ['region_specs', 'regionSpecs']) ?? '';
        final c = raw.toString().trim().toLowerCase();
        if (!isValidCarRegionSpecCode(c)) return '';
        return carRegionSpecDisplayLabel(c);
      }()),
    ),
    _SpecItem(
      icon: Icons.settings,
      label: AppLocalizations.of(context)!.transmissionLabel,
      value: transmissionVal,
    ),
    _SpecItem(
      icon: Icons.local_gas_station,
      label: AppLocalizations.of(context)!.detail_fuel,
      value: fuelVal,
    ),
  ];

  final List<Widget> details = [
    detailRowSpec(
      icon: Icons.layers,
      label: AppLocalizations.of(context)!.trimLabel,
      value: orDash(
        _translateValueGlobal(context, pickNE(car, ['trim'])) ??
            pickNE(car, ['trim']),
      ),
    ),
    detailRowSpec(
      icon: Icons.check_circle,
      label: AppLocalizations.of(context)!.detail_condition,
      value: orDash(
        _translateValueGlobal(context, pickNE(car, ['condition'])),
      ),
    ),
    detailRowSpec(
      icon: Icons.assignment_turned_in,
      label: AppLocalizations.of(context)!.titleStatus,
      value: titleStatusVal,
      onTap: damagePreviewEntries.isEmpty
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ListingPreviewMediaGridPage(
                    imageFilesOrUrls: List<dynamic>.from(damagePreviewEntries),
                    videoFilesOrUrls: const <dynamic>[],
                    initialIndex: 0,
                    appBarTitle: AppLocalizations.of(context)!.damageImagesTitle,
                  ),
                ),
              );
            },
    ),
    if ((car['vin'] ?? '').toString().trim().isNotEmpty)
      GestureDetector(
        onLongPress: () {
          final vin = car['vin'].toString().trim();
          services.Clipboard.setData(services.ClipboardData(text: vin));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _trLegacyText(context, 'VIN copied', ar: 'تم نسخ رقم الهيكل', ku: 'ژمارەی شاسی کۆپی کرا'),
              ),
            ),
          );
        },
        child: detailRowSpec(
          icon: Icons.pin_outlined,
          label: 'VIN',
          value: car['vin'].toString().trim(),
          onTap: () {
            final vin = car['vin'].toString().trim();
            openVinSearch(vin);
          },
        ),
      ),
    detailRowSpec(
      icon: Icons.drive_eta,
      label: AppLocalizations.of(context)!.detail_drive,
      value: orDash(
        _translateValueGlobal(
          context,
          pickNE(car, ['drive_type', 'driveType', 'drivetrain', 'drive']),
        ),
      ),
    ),
    detailRowSpec(
      icon: Icons.directions_car_filled,
      label: AppLocalizations.of(context)!.detail_body,
      value: orDash(
        _translateValueGlobal(
          context,
          pickNE(car, ['body_type', 'bodyType', 'body']),
        ),
      ),
    ),
    detailRowSpec(
      icon: Icons.color_lens,
      label: AppLocalizations.of(context)!.detail_color,
      value: orDash(_translateValueGlobal(context, pickNE(car, ['color']))),
    ),
    detailRowSpec(
      icon: Icons.airline_seat_recline_normal,
      label: AppLocalizations.of(context)!.detail_seating,
      value: orDash(
        _localizeDigitsGlobal(
          context,
          pickNE(car, ['seating', 'seats', 'seatCount']) ?? '',
        ),
      ),
    ),
    detailRowSpec(
      icon: Icons.confirmation_number_outlined,
      label: _trLegacyText(
        context,
        'Plate',
        ar: 'اللوحة',
        ku: 'پڵەیت',
      ),
      value: orDash(() {
        final rawCity = pickNE(car, ['plate_city', 'plateCity'])?.trim();
        final rawType = pickNE(car, ['plate_type', 'plateType'])?.trim();

        final String? city = (rawCity == null || rawCity.isEmpty)
            ? null
            : (_translateValueGlobal(context, rawCity) ?? rawCity);
        final String? type = (rawType == null || rawType.isEmpty)
            ? null
            : _translatePlateTypeLegacy(context, rawType);

        if (city == null && type == null) return null;
        if (city != null && type != null) return '$city/$type';
        return city ?? type;
      }()),
    ),
  ];
  final description = pickNE(car, ['description'])?.trim() ?? '';
  if (description.isNotEmpty) {
    details.add(
      detailRowSpec(
        icon: Icons.description_outlined,
        label: AppLocalizations.of(context)?.descriptionTitle ?? 'Description',
        value: _trLegacyText(
          context,
          'View description',
          ar: 'عرض الوصف',
          ku: 'پیشاندانی وەسف',
        ),
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                AppLocalizations.of(context)?.descriptionTitle ?? 'Description',
              ),
              content: SingleChildScrollView(child: Text(description)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    _trLegacyText(
                      context,
                      'Close',
                      ar: 'إغلاق',
                      ku: 'داخستن',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  final isLightSpecs = Theme.of(context).brightness == Brightness.light;
  // Width-based row height: tighter than childAspectRatio 1.5 so the outer
  // shell does not grow vertically on narrow phones (GridView + padding).
  final primGrid = LayoutBuilder(
    builder: (context, constraints) {
      const double crossGap = 12;
      const int crossCount = 3;
      final double maxW = constraints.maxWidth;
      final double tileW = (maxW - crossGap * (crossCount - 1)) / crossCount;
      // Was ~1.5 (height = tileW/1.5); 1.72 shortens each row ~13%.
      final double rowH = tileW / 1.72;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          crossAxisSpacing: crossGap,
          mainAxisSpacing: 12,
          mainAxisExtent: rowH,
        ),
        itemCount: primary.length,
        itemBuilder: (context, index) => specCard(primary[index]),
      );
    },
  );

  final topSpecs = Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: isLightSpecs
          ? const Color(0xFFEEEEEE)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isLightSpecs ? const Color(0xFFE0E0E0) : Colors.white24,
      ),
    ),
    child: primGrid,
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [topSpecs, SizedBox(height: 12), ...details],
  );
}

class _SpecItem {
  final IconData icon;
  final String label;
  final String? value;
  _SpecItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}
