part of 'car_details_page.dart';

mixin _CarDetailsPageInit on _CarDetailsPageLoad {
  @override
  void initState() {
    super.initState();
    // Auto-reconciliation fix: observe app foreground/background so the
    // owner-media poll timer (see `_CarDetailsPageLoad
    // ._maybeScheduleOwnerMediaPoll`) pauses while backgrounded and
    // resumes on return, instead of silently polling (or silently never
    // resuming) regardless of visibility.
    WidgetsBinding.instance.addObserver(this);
    _listingColumnsPref = ListingLayoutPrefs.columns.value;
    ListingLayoutPrefs.load();
    ListingLayoutPrefs.columns.addListener(_onListingLayoutChanged);
    _scrollController.addListener(_onScroll);
    unawaited(
      AnalyticsService.trackView(widget.carId.toString()),
    );
    _loadCar();
  }

  /// Owner-controls fix: subscribe to [AuthService] so ownership (and with
  /// it the Edit/Delete/Analytics buttons) is re-evaluated whenever the
  /// signed-in user becomes known or changes -- see [_ownerAuth]. Done here
  /// rather than via `context.watch` so the reaction can also refresh the
  /// loaded listing (`_syncCarViewer`), and so it follows a replaced
  /// provider instance the same way `AppWithDeepLinks` does.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthService>(context, listen: false);
    if (identical(auth, _ownerAuth)) return;
    _ownerAuth?.removeListener(_onOwnerAuthChanged);
    _ownerAuth = auth;
    auth.addListener(_onOwnerAuthChanged);
  }

  void _onOwnerAuthChanged() {
    if (!mounted) return;
    // Rebuild so `_ownerControlsAccess` is re-read from the live auth state
    // (also covers loading -> failed transitions of the profile request).
    setState(() {});
    _syncCarViewer();
  }

  @override
  void dispose() {
    _ownerAuth?.removeListener(_onOwnerAuthChanged);
    _ownerAuth = null;
    // F-06: genuinely abort a still-in-flight car-detail load instead of
    // leaving it running in the background after this screen is gone.
    _loadCarCancelToken?.cancel();
    _cancelOwnerMediaPoll();
    WidgetsBinding.instance.removeObserver(this);
    try {
      ListingLayoutPrefs.columns.removeListener(_onListingLayoutChanged);
    } catch (e, st) { logNonFatal(e, st); }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _imagePageController.dispose();
    super.dispose();
  }
}
