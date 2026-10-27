import 'dart:async';
import '../theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../shared/debug/app_log.dart';
import '../shared/net/transient_get_retry.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_events.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/prefs/sell_listing_draft_prefs.dart';
import '../shared/prefs/sell_draft_media_persistence.dart';
import '../shared/prefs/sell_submission_state_prefs.dart';
import '../shared/prefs/legacy_sell_draft_list.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../shared/listings/owner_media_overlay.dart';
import '../shared/listings/owner_pending_media_merge.dart';
import '../features/sell/pending_sell_submission_service.dart';
import '../features/sell/sell_draft_helpers.dart';
import '../features/sell/sell_pending_media_resume.dart';
import '../features/sell/sell_submission_visibility.dart';
import '../shared/ui/listing_feed_skeleton.dart';
import '../shared/ui/empty_state_panel.dart';
import '../features/listing/listing_mappers.dart';
import '../app/listing_shell.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;
import '../app/widgets/listing_network_image.dart';
import '../shared/listings/listing_image_media.dart';

part 'my_listings_page_widgets.dart';

/// Test-only hook for F-13 coverage: when non-null, the next
/// `_loadDrafts()` call throws this immediately after entering its try
/// block, then clears itself. This exercises `_loadDrafts()`'s outer
/// safety-net `catch` without fabricating fake prefs corruption — the three
/// known corrupt-prefs sources (`SellListingDraftPrefs.load`,
/// `LegacySellDraftList`'s snapshot/archive decoders, and
/// `SellPendingMediaResume.tryResume`) already catch and `logNonFatal` their
/// own decode failures internally and never reach this outer catch. Always
/// `null` in production.
@visibleForTesting
Object? debugMyListingsLoadDraftsError;

enum _MyListingsFilter { all, active, pending, hidden, sold, draft }

class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage>
    with WidgetsBindingObserver {
  final ScrollController _controller = ScrollController();

  /// Returning from the background: the pending-submission entries may have
  /// changed while this page was frozen, and a list load that failed (dead
  /// socket after backgrounding, refresh not yet possible) must not stay on
  /// screen until the seller manually retries. Runs a microtask later so the
  /// app-level resume hook (which recycles the HTTP client) has already run.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    scheduleMicrotask(() {
      if (!mounted) return;
      unawaited(_loadDrafts());
      // Two cases need a fresh request, and both are handled by superseding
      // whatever is outstanding (the generation guard in `_fetch` then makes
      // the old request's eventual result -- typically a dead-socket failure
      // that only surfaces AFTER this resume -- harmless):
      //  * an error is already on screen;
      //  * a load is still in flight: it may be riding a socket the OS killed
      //    while the app was backgrounded (real-device bug: it failed seconds
      //    after the resume check had already run, leaving "Failed to load
      //    your listings" until the seller pressed Retry).
      // A healthy, idle page is left alone (no needless traffic).
      if (_error != null || _loading) {
        unawaited(_fetch(refresh: true));
      }
    });
  }

  bool _wasOnline = ConnectivityService.instance.isOnline.value;

  /// Network came back: recover a failed load without a manual Retry.
  void _onConnectivityChanged() {
    final online = ConnectivityService.instance.isOnline.value;
    final cameBack = online && !_wasOnline;
    _wasOnline = online;
    if (cameBack && mounted && _error != null && !_loading) {
      unawaited(_fetch(refresh: true));
    }
  }

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  int _fetchGeneration = 0;
  String? _error;
  bool _loadingDraft = true;
  List<Map<String, dynamic>> _drafts = <Map<String, dynamic>>[];

  /// Durable submission records (Submit pressed, not yet verified complete
  /// on the server) shown as pending entries. A listing that was submitted
  /// must ALWAYS have a visible representation here until the server has
  /// confirmed it -- see `sell_submission_visibility.dart`.
  List<SellSubmissionRecord> _pendingSubmissions = <SellSubmissionRecord>[];
  StreamSubscription<SellSubmissionEvent>? _submissionEvents;
  _MyListingsFilter _filter = _MyListingsFilter.all;
  bool _routeFilterApplied = false;

  final List<Map<String, dynamic>> _cars = <Map<String, dynamic>>[];

  /// Optimistic-submission fix: listing ids (this account's own, per
  /// `GET /api/my-listings`) that still have a durable pending-submission
  /// record on THIS device -- i.e. `mediaStatus == processing` (see
  /// `owner_pending_media_merge.dart`). Drives the subtle "Processing
  /// media" card badge below; never gates/blocks anything.
  Set<String> _processingCarIds = <String>{};

  String _text(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConnectivityService.instance.isOnline.addListener(_onConnectivityChanged);
    // Keep consistent layout (grid vs list) with the rest of the app.
    ListingLayoutPrefs.load();
    _loadDrafts();
    _controller.addListener(() {
      if (_loading || _loadingMore || !_hasNext) return;
      final pos = _controller.position;
      if (pos.pixels >= (pos.maxScrollExtent - 500)) {
        _loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch(refresh: true));
    ListingEvents.deletedListingId.addListener(_onListingDeletedElsewhere);
    // Keep the pending entries truthful as the background worker finishes,
    // fails or schedules a retry (terminal events only; cheap prefs read).
    _submissionEvents = PendingSellSubmissionService.instance.events.listen((
      event,
    ) {
      if (!mounted) return;
      unawaited(_loadDrafts());
      if (event.success) unawaited(_fetch(refresh: true));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeFilterApplied) return;
    _routeFilterApplied = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map) return;
    final raw = (args['filter'] ?? '').toString().trim().toLowerCase();
    final next = switch (raw) {
      'pending' => _MyListingsFilter.pending,
      'active' => _MyListingsFilter.active,
      'hidden' => _MyListingsFilter.hidden,
      'sold' => _MyListingsFilter.sold,
      'draft' => _MyListingsFilter.draft,
      _ => null,
    };
    if (next != null) {
      _filter = next;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ConnectivityService.instance.isOnline
        .removeListener(_onConnectivityChanged);
    ListingEvents.deletedListingId.removeListener(_onListingDeletedElsewhere);
    unawaited(_submissionEvents?.cancel());
    _controller.dispose();
    super.dispose();
  }

  void _onListingDeletedElsewhere() {
    final id = ListingEvents.deletedListingId.value;
    if (id == null || id.isEmpty || !mounted) return;
    setState(() {
      _cars.removeWhere((c) => listingMatchesId(c, id));
    });
  }

  /// Optimistic-submission fix: every listing in [_cars] came from
  /// `GET /api/my-listings`, so it is already known to be this account's
  /// own -- merge in local pending fallback media (and recompute which
  /// listings still have unfinished background media work) without any
  /// extra owner check. [requestGeneration] guards against a stale merge
  /// (from an OLDER `_fetch` call still finishing this async work)
  /// clobbering a newer refresh's `_cars`, mirroring `_fetch`'s own
  /// generation guard.
  Future<void> _applyOwnerPendingMediaMerge(int requestGeneration) async {
    try {
      final snapshot = List<Map<String, dynamic>>.from(_cars);
      // Real-device acceptance fix: the live-record-only
      // `OwnerPendingMediaMerge.mergeOwnedListings` becomes a permanent
      // no-op for a listing the instant its backend submission finishes
      // (well before this page ever gets to render it once) -- this
      // bulk helper ALSO falls back to the durable
      // `OwnerOptimisticMediaRecord` for that common case, so a
      // brand-new listing's card shows its just-picked photos/videos
      // immediately instead of needing the owner to open Car Details
      // first. See `OwnerMediaOverlay.mergeOwnedListingsForCardDisplay`'s
      // own doc comment.
      final merged =
          await OwnerMediaOverlay.mergeOwnedListingsForCardDisplay(snapshot);
      final processing = await OwnerPendingMediaMerge.processingCarIds(
        snapshot,
      );
      if (!mounted || requestGeneration != _fetchGeneration) return;
      setState(() {
        _cars
          ..clear()
          ..addAll(merged);
        _processingCarIds = processing;
      });
    } catch (e, st) {
      logNonFatal(e, st, 'MyListingsPage._applyOwnerPendingMediaMerge');
    }
  }

  Future<void> _fetch({required bool refresh}) async {
    final requestGeneration = refresh ? ++_fetchGeneration : _fetchGeneration;
    // Gate on the locally-stored token (`ApiService.isAuthenticated`), not
    // `AuthService.isAuthenticated` (which only flips true once `/auth/me`
    // confirms it). AuthGuard now mounts this page as soon as a stored
    // token exists, *before* that confirmation finishes, so this fetch
    // must be able to start immediately in parallel with `/auth/me`
    // instead of showing a spurious "Login required" until it resolves.
    // The backend still independently rejects the request below if the
    // token actually turns out to be invalid.
    if (!ApiService.isAuthenticated) {
      setState(() {
        _loading = false;
        _error =
            AppLocalizations.of(context)?.loginRequired ?? 'Login required';
      });
      return;
    }

    if (_filter == _MyListingsFilter.draft) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = null;
        _hasNext = false;
        _cars.clear();
      });
      return;
    }

    if (refresh) {
      // NOTE: `_cars` is deliberately NOT cleared here. Listings that are
      // already on screen stay visible while a refresh runs (and if it
      // ultimately fails); they are replaced atomically only when the new
      // page arrives. A filter change clears them explicitly in
      // `_selectFilter` because they belong to a different filter.
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasNext = true;
      });
    } else {
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }

    try {
      final status = switch (_filter) {
        _MyListingsFilter.active => 'active',
        _MyListingsFilter.pending => 'pending',
        _MyListingsFilter.hidden => 'hidden',
        _MyListingsFilter.sold => 'sold',
        _ => null,
      };
      final pageToLoad = _page;
      // A listings GET is safe to repeat. A transient failure (dead socket
      // after backgrounding, 5xx, timeout, a refresh blip surfaced as 503)
      // gets a short, bounded automatic retry instead of an error screen --
      // and stops as soon as a newer request supersedes this one.
      final data = await retryTransientGet<Map<String, dynamic>>(
        () => ApiService.getMyListings(
          page: pageToLoad,
          perPage: 20,
          status: status,
        ),
        isSuperseded: () => !mounted || requestGeneration != _fetchGeneration,
        onRetry: (error, attempt) {
          appLog(
            '[MY LISTINGS] transient load failure '
            '(${error.runtimeType}), retry ${attempt + 1}',
          );
          // Drop a connection the OS may have killed; in-flight requests
          // on the old client are left to finish (closeWhenIdle).
          ApiService.recycleProductionHttpClient();
        },
      );
      final items = listingMapsFromApiResponse(data);

      bool hasNext = false;
      final pagination = data['pagination'];
      if (pagination is Map && pagination['has_next'] is bool) {
        hasNext = pagination['has_next'] as bool;
      } else {
        hasNext = items.length >= 20;
      }

      // Stale-result guard: only the newest request may touch the screen.
      if (!mounted || requestGeneration != _fetchGeneration) return;
      setState(() {
        if (refresh) _cars.clear();
        _cars.addAll(items);
        _hasNext = hasNext;
        _loading = false;
        _loadingMore = false;
      });
      unawaited(_applyOwnerPendingMediaMerge(requestGeneration));
    } catch (e) {
      if (!mounted || requestGeneration != _fetchGeneration) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback:
              AppLocalizations.of(context)?.failedToLoadListings ??
              'Failed to load listings',
        );
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_filter == _MyListingsFilter.draft || _loadingMore || !_hasNext) return;
    _page += 1;
    await _fetch(refresh: false);
  }

  void _selectFilter(_MyListingsFilter filter) {
    if (_filter == filter) return;
    if (_controller.hasClients) _controller.jumpTo(0);
    setState(() {
      _filter = filter;
      _error = null;
      // Different filter => the visible listings no longer apply.
      _cars.clear();
    });
    unawaited(_fetch(refresh: true));
  }

  Future<void> _loadDrafts() async {
    try {
      final injectedError = debugMyListingsLoadDraftsError;
      if (injectedError != null) {
        debugMyListingsLoadDraftsError = null;
        throw injectedError;
      }
      // Finish interrupted submit media before showing drafts/listings.
      // This already covers the common case (resume finishes before the
      // list below is read, so a just-created listing's draft is already
      // discarded by the time `LegacySellDraftList.loadVisible()` runs) --
      // but resume can legitimately leave a record un-resumed for now
      // (e.g. `needsAttention`, or the owner/auth-timing guard in
      // `PendingSellSubmissionService._runSubmission`), so also explicitly
      // filter by an active pending-submission record below (see
      // `SellDraftGatePage._loadDrafts` for the full explanation) rather
      // than relying solely on resume timing to keep this list correct.
      final auth = Provider.of<AuthService>(context, listen: false);
      final currentOwner = (auth.currentUser?['id'] ?? '').toString().trim();
      await SellDraftMediaPersistence.ensureDocumentsPathCached();
      final resumed = await SellPendingMediaResume.tryResume();
      final drafts = <Map<String, dynamic>>[];
      final ownerKey = _buildDraftOwnerKey();
      // Hide the modern (owner-keyed) draft while ANY active submission
      // record exists for this account — same contract as the legacy
      // draftId peek filter below. Without this, Submit→kill→reopen
      // showed a freely editable "draft" even though a pending
      // SellSubmissionRecord was already durably recorded.
      final pendingRecords = await SellSubmissionStatePrefs.loadAll();
      final hasActiveSubmission = pendingRecords.any((r) {
        if (r.status == SellSubmissionStatus.completed ||
            r.status == SellSubmissionStatus.needsAttention) {
          return false;
        }
        final owner = (r.ownerUserId ?? '').trim();
        if (owner.isEmpty) return false; // quarantined: owner unknown (F-34)
        if (currentOwner.isEmpty) return true;
        return owner == currentOwner;
      });
      final modernDraft = await SellListingDraftPrefs.load(ownerKey);
      if (modernDraft != null &&
          _hasMeaningfulDraftData(modernDraft) &&
          !hasActiveSubmission) {
        drafts.add(<String, dynamic>{
          'draftId': 'modern_$ownerKey',
          'currentStep': modernDraft['complete'] == true ? 5 : 0,
          'carData': modernDraft,
          'isModern': true,
        });
      } else if (modernDraft != null && hasActiveSubmission) {
        appLog(
          '[SELL RESUME] my listings: hiding modern draft -- pending '
          'submission exists',
        );
      }
      for (final draft in await LegacySellDraftList.loadVisible()) {
        final id = (draft['draftId'] ?? '').toString();
        // A draft is hidden only when its superseding submission is shown
        // as a pending entry below (never hide without a replacement).
        final pending = id.isEmpty
            ? null
            : pendingRecords
                .where(
                  (r) =>
                      r.draftId == id &&
                      sellSubmissionHidesDraft(
                        r,
                        currentOwnerId: currentOwner,
                      ),
                )
                .firstOrNull;
        if (pending != null) {
          appLog(
            '[SELL RESUME] my listings: hiding draft id=$id -- pending '
            'submission exists (status=${pending.status.name})',
          );
          continue;
        }
        drafts.add(draft);
      }
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _pendingSubmissions = sellSubmissionPendingEntries(
          pendingRecords,
          currentOwnerId: currentOwner,
        );
        _loadingDraft = false;
      });
      if (resumed) {
        unawaited(_fetch(refresh: true));
      }
    } catch (e, st) {
      logNonFatal(e, st, 'MyListingsPage._loadDrafts');
      if (!mounted) return;
      setState(() {
        _drafts = <Map<String, dynamic>>[];
        _loadingDraft = false;
      });
    }
  }

  Future<void> _discardDraft(Map<String, dynamic> draft) async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _text(
            'Discard draft?',
            ar: 'حذف المسودة؟',
            ku: 'ڕەشنووس بسڕێتەوە؟',
          ),
        ),
        content: Text(
          _text(
            'This will permanently delete this draft listing. This cannot be undone.',
            ar: 'سيتم حذف مسودة الإعلان نهائياً. لا يمكن التراجع عن هذا الإجراء.',
            ku: 'ئەمە ڕەشنووسی ڕێکلامەکە بە هەمیشەیی دەسڕێتەوە. ناتوانرێت پاشگەز ببێتەوە.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc?.cancelAction ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _text('Discard', ar: 'حذف', ku: 'بسڕەوە'),
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final draftId = (draft['draftId'] ?? '').toString();
    if (draft['isModern'] == true) {
      await SellListingDraftPrefs.clear(_buildDraftOwnerKey());
    } else {
      await LegacySellDraftList.discard(draft);
    }
    if (!mounted) return;
    setState(() {
      _drafts.removeWhere((item) => item['draftId']?.toString() == draftId);
    });
  }

  Future<void> _resumeDraft(Map<String, dynamic> draft) async {
    if (draft['isModern'] == true) {
      final carData = draft['carData'] is Map
          ? Map<String, dynamic>.from(
              (draft['carData'] as Map).cast<String, dynamic>(),
            )
          : <String, dynamic>{};
      await Navigator.pushNamed(
        context,
        '/sell',
        arguments: <String, dynamic>{
          'draftSnapshot': <String, dynamic>{
            'currentStep': draft['currentStep'] ?? 0,
            'carData': carData,
          },
        },
      );
    } else {
      final prepared = await LegacySellDraftList.prepareForResume(draft);
      if (!mounted) return;
      await Navigator.pushNamed(
        context,
        '/sell',
        arguments: <String, dynamic>{'draftSnapshot': prepared},
      );
    }
    if (mounted) await _loadDrafts();
  }

  String _buildDraftOwnerKey() {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    final raw =
        (user?['public_id'] ??
                user?['id'] ??
                user?['username'] ??
                user?['email'] ??
                'guest')
            .toString()
            .trim();
    return raw.isEmpty ? 'guest' : raw;
  }

  bool _hasMeaningfulDraftData(Map<String, dynamic> data) {
    return data.values.any((value) {
      if (value == null) return false;
      if (value is String) return value.trim().isNotEmpty;
      if (value is num) return value != 0;
      if (value is bool) return value;
      if (value is Iterable) return value.isNotEmpty;
      if (value is Map) return value.isNotEmpty;
      return value.toString().trim().isNotEmpty;
    });
  }

  String _draftTitle(Map<String, dynamic> carData) =>
      localizedSellDraftTitle(context, carData);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    // Subscribe to AuthService so this page still rebuilds when `/auth/me`
    // resolves (or a definitive 401 clears the session) — see
    // `AuthService.onApiTokensCleared` — but gate the UI below on
    // `ApiService.isAuthenticated` (the locally-stored token), matching
    // AuthGuard's own optimistic-mount behavior and `_fetch` above. Gating
    // on `AuthService.isAuthenticated` here instead would show a spurious
    // "Login required" flash on every fresh app launch, since AuthGuard now
    // mounts this page as soon as a stored token exists, before `/auth/me`
    // has confirmed it.
    context.watch<AuthService>();
    final hasLocalSession = ApiService.isAuthenticated;

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final showDrafts =
        _filter == _MyListingsFilter.all || _filter == _MyListingsFilter.draft;
    final visibleDrafts = showDrafts ? _drafts : const <Map<String, dynamic>>[];
    // Local entries (drafts / pending submissions) are real content that
    // must stay visible even when the server list failed to load.
    final hasLocalEntries = (showDrafts && _drafts.isNotEmpty) ||
        ((showDrafts || _filter == _MyListingsFilter.pending) &&
            _pendingSubmissions.isNotEmpty);
    // The blocking full-screen error is only for a failure with NOTHING to
    // show. If listings (or local entries) are on screen they stay, and the
    // failure becomes an inline banner with Retry.
    final fullScreenError =
        _error != null && _cars.isEmpty && !hasLocalEntries;
    final authenticatedBody = Column(
      children: [
        _buildListingFilters(),
        if (_filter == _MyListingsFilter.pending) _buildPendingExplainer(),
        if (_filter == _MyListingsFilter.hidden) _buildHiddenExplainer(),
        if (_loading && (_cars.isNotEmpty || hasLocalEntries))
          const LinearProgressIndicator(minHeight: 2),
        if (_error != null && !fullScreenError)
          Material(
            key: const ValueKey<String>('my-listings-inline-error'),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _fetch(refresh: true),
                    child: Text(loc?.retryAction ?? 'Retry'),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([_fetch(refresh: true), _loadDrafts()]);
            },
            child: (_loading && _cars.isEmpty && !hasLocalEntries)
                ? Builder(
                    builder: (context) {
                      final w = MediaQuery.sizeOf(context).width;
                      final cols =
                          ListingLayoutPrefs.effectiveColumnsForWidth(
                            ListingLayoutPrefs.columns.value == 1 ? 1 : 2,
                            w,
                          );
                      return ListingFeedSkeleton(
                        columns: cols,
                        itemCount: cols == 1 ? 4 : cols * 3,
                      );
                    },
                  )
                : fullScreenError
                ? ListView(
                    children: [
                      const SizedBox(height: 40),
                      Center(child: Text(_error!)),
                      const SizedBox(height: 12),
                      Center(
                        child: OutlinedButton(
                          onPressed: () => _fetch(refresh: true),
                          child: Text(loc?.retryAction ?? 'Retry'),
                        ),
                      ),
                    ],
                  )
                : ValueListenableBuilder<int>(
                    valueListenable: ListingLayoutPrefs.columns,
                    builder: (context, cols, _) {
                      final screenWidth = MediaQuery.sizeOf(context).width;
                      final listingColumns =
                          ListingLayoutPrefs.effectiveColumnsForWidth(
                            cols == 1 ? 1 : 2,
                            screenWidth,
                          );
                      final draftCount = visibleDrafts.length;
                      final showPending = showDrafts ||
                          _filter == _MyListingsFilter.pending;
                      final visiblePending = showPending
                          ? sellSubmissionPendingEntries(
                              _pendingSubmissions,
                              currentOwnerId: (context
                                          .read<AuthService>()
                                          .currentUser?['id'] ??
                                      '')
                                  .toString()
                                  .trim(),
                              serverListingIds: {
                                for (final c in _cars) listingPrimaryId(c),
                              },
                            )
                          : const <SellSubmissionRecord>[];
                      final pendingCount = visiblePending.length;
                      final headCount = draftCount + pendingCount;
                      final totalCards = _cars.length + headCount;
                      return totalCards == 0
                          ? ListView(
                              controller: _controller,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                12,
                              ),
                              children: [
                                if (_loadingDraft && showDrafts)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else
                                  _buildEmptyState(filter: _filter),
                              ],
                            )
                          : GridView.builder(
                              controller: _controller,
                              padding: EdgeInsets.fromLTRB(
                                listingColumns == 1 ? 4 : 8,
                                8,
                                listingColumns == 1 ? 4 : 8,
                                8 + bottomInset,
                              ),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: listingColumns,
                                    childAspectRatio:
                                        ListingLayoutPrefs.gridChildAspectRatioForWidth(
                                          listingColumns,
                                          screenWidth,
                                        ),
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemCount: totalCards + (_hasNext ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= totalCards) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                if (index < draftCount) {
                                  return _buildDraftCard(
                                    visibleDrafts[index],
                                    listLayout: listingColumns == 1,
                                  );
                                }

                                if (index < headCount) {
                                  return _buildPendingSubmissionCard(
                                    visiblePending[index - draftCount],
                                    listLayout: listingColumns == 1,
                                  );
                                }

                                final car = _cars[index - headCount];

                                final mapped = mapListingToGlobalCarCardData(
                                  context,
                                  car,
                                );
                                final cardWidget = buildGlobalCarCard(
                                  context,
                                  mapped,
                                  listLayout: listingColumns == 1,
                                  allowOwnerManagementOnOpen: true,
                                );
                                final isProcessing = _processingCarIds
                                    .contains(listingPrimaryId(car));
                                if (!isProcessing) return cardWidget;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    cardWidget,
                                    Positioned(
                                      bottom: listingColumns == 1 ? 12 : 8,
                                      left: listingColumns == 1 ? 12 : 8,
                                      child: _buildProcessingMediaBadge(
                                        context,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                    },
                  ),
          ),
        ),
      ],
    );

    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final bodyChild = !hasLocalSession
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(loc?.loginRequired ?? 'Login required'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                    child: Text(loc?.loginAction ?? 'Login'),
                  ),
                ],
              ),
            ),
          )
        : authenticatedBody;

    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      appBar: AppBar(
        title: Text(loc?.myListingsTitle ?? 'My listings'),
        leading: Navigator.of(context).canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/',
                    (route) => false,
                  );
                },
              ),
      ),
      body: isLightShell
          ? bodyChild
          : Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
              child: bodyChild,
            ),
      floatingActionButton: hasLocalSession
          ? FloatingActionButton(
              onPressed: () => Navigator.pushNamed(context, '/sell'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
