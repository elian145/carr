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

  AuthService get _authForOwnership =>
      _ownerAuth ?? Provider.of<AuthService>(context, listen: false);

  /// Live (never cached) ownership of the CURRENTLY shown [car] by the
  /// CURRENTLY signed-in user. Safe to read from `build` because the page
  /// subscribes to [AuthService] (see `_CarDetailsPageInit
  /// .didChangeDependencies`) and rebuilds whenever the signed-in user
  /// changes.
  bool get _isListingOwner =>
      isListingOwner(car, _authForOwnership.userId);

  /// Owner-only actions (Edit / Delete / Analytics / Sold) are shown only
  /// when the entry point offers management AND the signed-in account is the
  /// listing's seller. The account id comes from the restored session
  /// ([AuthService.userId]) so it is known on the very first frame -- no
  /// placeholder, spinner or Retry is ever shown in its place. Presentation
  /// only: the backend authorizes every owner action itself.
  bool get _canManageOwnListing => canManageListing(
    allowOwnerManagement: widget.allowOwnerManagement,
    car: car,
    userId: _authForOwnership.userId,
  );

  /// Automatic (never user-driven) recovery when a stored session exists but
  /// the account id cannot be established from it -- e.g. a legacy token
  /// whose subject is not a public id -- so ownership has to wait for
  /// `/auth/me`. Asks [AuthService] to (re)attempt the profile through its
  /// single-flight path; the page re-evaluates when the user arrives.
  void _ensureOwnerIdentityResolves() {
    if (!widget.allowOwnerManagement) return;
    final auth = _authForOwnership;
    if ((auth.userId ?? '').isNotEmpty) return;
    if (!ApiService.isAuthenticated) return;
    if (auth.isProfileStranded) {
      unawaited(auth.recoverStrandedProfile());
    }
  }

  Future<void> _editOwnListing() async {
    final current = car;
    if (current == null) return;
    final updated = await openEditListingPage(
      context,
      Map<String, dynamic>.from(current),
    );
    if (!mounted || updated == null) return;
    setState(
      () => car = mergeListingKeepingOwner(
        current,
        updated,
        _authForOwnership.userId,
      ),
    );
  }

  Future<void> _deleteOwnListing() async {
    final id = listingPrimaryId(car ?? {});
    if (id.isEmpty) return;
    // A listing that is still Under Review can be deleted too (the dialog
    // says so); an Active listing keeps its existing wording.
    final deleted = await confirmAndDeleteListing(
      context,
      id,
      underReview: isListingPending(car),
    );
    if (!deleted || !mounted) return;
    Navigator.pop(context, {'deleted': true, 'carId': id});
  }

  /// Owner-only: the listing has a pending revision (edits under review,
  /// rejected, or saved but not submitted).
  bool get _hasOwnerPendingEdits =>
      _canManageOwnListing && listingHasPendingRevision(car);

  Future<void> _previewPendingEdits() async {
    final current = car;
    if (current == null) return;
    await showPendingChangesPreview(context, current);
  }

  Future<void> _discardPendingEdits() async {
    final id = listingPrimaryId(car ?? {});
    if (id.isEmpty) return;
    final fresh = await confirmAndDiscardPendingEdits(context, id);
    if (!mounted || fresh == null) return;
    setState(() {
      final merged = mergeListingKeepingOwner(
        car ?? const <String, dynamic>{},
        fresh,
        _authForOwnership.userId,
      );
      merged.remove('pending_revision');
      car = merged;
    });
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
      car = mergeListingKeepingOwner(
        car ?? const <String, dynamic>{},
        updated,
        _authForOwnership.userId,
      );
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
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.loginRequired),
            action: SnackBarAction(
              label: loc.loginAction,
              onPressed: () => Navigator.pushNamed(context, '/login'),
            ),
          ),
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
