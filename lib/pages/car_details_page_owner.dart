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
}
