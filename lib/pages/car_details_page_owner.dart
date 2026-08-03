part of 'car_details_page.dart';

mixin _CarDetailsPageOwner on _CarDetailsPageTitles {
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

  bool get _canManageOwnListing =>
      widget.allowOwnerManagement && _isListingOwner;

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
          nowSold
              ? AppLocalizations.of(context)!.listingMarkedAsSold
              : AppLocalizations.of(context)!.listingIsAvailableAgain,
        ),
      ),
    );
  }

  Future<ListingAnalytics> _fetchOwnListingAnalytics(String listingId) async {
    final current = car ?? <String, dynamic>{};
    try {
      final a = await AnalyticsService.getListingAnalytics(listingId);
      if (a.listingId.toString().isNotEmpty) return a;
    } catch (e, st) {
      logNonFatal(e, st);
    }

    try {
      final all = await AnalyticsService.getUserListingsAnalytics();
      for (final a in all) {
        if (a.listingId.toString() == listingId) return a;
      }
    } catch (_) {}

    int parseInt(dynamic v, {int fallback = 0}) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    double parseDouble(dynamic v, {double fallback = 0}) {
      if (v == null) return fallback;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }

    return ListingAnalytics(
      listingId: listingId,
      title: (current['title'] ?? '').toString(),
      brand: (current['brand'] ?? '').toString(),
      model: (current['model'] ?? '').toString(),
      year: parseInt(current['year']),
      price: parseDouble(current['price']),
      imageUrl: null,
      mileage: null,
      city: (current['city'] ?? current['location'])?.toString(),
      views: 0,
      messages: 0,
      calls: 0,
      shares: 0,
      favorites: 0,
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
  }

  void _showOwnListingAnalytics() {
    final loc = AppLocalizations.of(context);
    final listingId = listingPrimaryId(car ?? {'id': widget.carId});
    if (listingId.isEmpty) return;

    final future = _fetchOwnListingAnalytics(listingId);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(loc?.analyticsTitle ?? 'Analytics'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AppResponsive.dialogWidth(context, preferred: 360),
            ),
            child: FutureBuilder<ListingAnalytics>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    userErrorText(
                      context,
                      snapshot.error!,
                      fallback: loc?.errorTitle ?? 'Error',
                    ),
                  );
                }
                final a = snapshot.data;
                if (a == null) {
                  return Text(loc?.errorTitle ?? 'No analytics available.');
                }

                Widget metricRow(IconData icon, String label, String value) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: AppColors.brandOrange),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                }

                final title = (a.title).trim().isNotEmpty
                    ? prettyTitleCase(a.title)
                    : prettyTitleCase(a.carTitle);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    metricRow(Icons.visibility_outlined, 'Views', '${a.views}'),
                    metricRow(
                      Icons.message_outlined,
                      'Messages',
                      '${a.messages}',
                    ),
                    metricRow(Icons.phone_outlined, 'Calls', '${a.calls}'),
                    metricRow(Icons.share_outlined, 'Shares', '${a.shares}'),
                    metricRow(
                      Icons.favorite_outline,
                      'Favorites',
                      '${a.favorites}',
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc?.cancelAction ?? 'Close'),
            ),
          ],
        );
      },
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
      unawaited(AppHaptics.light());
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
}
