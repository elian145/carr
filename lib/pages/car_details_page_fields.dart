part of 'car_details_page.dart';

abstract class _CarDetailsPageFields extends State<CarDetailsPage> {
  Map<String, dynamic>? car;
  bool loading = true;

  /// Set when a load attempt leaves [car] null for a reason other than the
  /// initial spinner (F-01/B-02): selects which failure UI
  /// `_CarDetailsPageBuild` renders instead of always showing the generic
  /// "Car not found" text. Null while loading or once [car] is populated.
  _CarDetailLoadError? loadError;

  /// Cancels the in-flight `ApiService.getCarDetail` call started by the
  /// most recent [_CarDetailsPageLoad._loadCar] (F-06). Cancelled from
  /// `dispose()` and re-created at the start of each `_loadCar()` call
  /// (including retries), so at most one load is ever "live" at a time.
  ApiCancelToken? _loadCarCancelToken;

  /// Exposed only so widget tests can assert that disposing this page
  /// cancels its in-flight car-detail load (F-06). Not read by production
  /// code — mirrors the existing `@visibleForTesting` debug-hook convention
  /// (e.g. `AuthGuard.debugTerminalTimeoutOverride`).
  @visibleForTesting
  ApiCancelToken? get debugLoadCarCancelToken => _loadCarCancelToken;

  /// Optimistic-local-media fix: per-item local<->remote reconciliation
  /// for the owner's own in-flight submission (see
  /// `owner_media_overlay.dart`) -- null/empty for a non-owner, a listing
  /// with no active durable record, or an edit-mode submission (see that
  /// file's own scope doc comment). Rebuilt every time [car] is
  /// (re)loaded -- see `_CarDetailsPageLoad._mergeOwnerPendingMedia`.
  OwnerMediaOverlayResult? _ownerMediaOverlay;

  /// Which of [_ownerMediaOverlay]'s slots (by `clientMediaId`) have
  /// actually finished loading/rendering their REMOTE counterpart on this
  /// device -- fed by `OwnerFallbackHeroImage`/`OwnerFallbackVideoThumbnail`
  /// `onRemoteDisplayReady` callbacks. Cleared on every fresh [car] load.
  final Map<String, bool> _remoteDisplayReady = <String, bool>{};

  /// Real-device acceptance fix: [_ownerMediaOverlay]'s own
  /// `serverStillProcessing` flag is a one-time snapshot of "does the
  /// durable record still exist" taken when [_ownerMediaOverlay] was
  /// (re)built -- it is never updated again afterwards even though
  /// `OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup` can
  /// (and, once every expected item is remote-display-ready, will)
  /// delete that very record a little while later, asynchronously, for
  /// the rest of THIS page instance's lifetime. Without this flag the
  /// "Processing media" badge could stay visible forever even once every
  /// item has genuinely finished, because nothing else ever re-reads the
  /// record again until the next full page (re)load. Set `true` the
  /// moment a `markRemoteDisplayReadyAndCleanup` call confirms the record
  /// is actually gone; reset to `false` every time [_ownerMediaOverlay]
  /// itself is freshly rebuilt (a new snapshot deserves to be trusted
  /// again until proven stale the same way).
  bool _ownerMediaRecordConfirmedGone = false;

  /// Legacy whole-listing "processing" signal
  /// (`OwnerPendingMediaMerge.isMediaProcessing`) -- used as the
  /// "Processing media" badge's condition when [_ownerMediaOverlay] is
  /// empty (non-owner, edit-mode, or no active record), so the badge's
  /// pre-existing behavior (as already shown on My Listings) is preserved
  /// unchanged for those cases.
  bool _legacyMediaProcessing = false;

  /// Auto-reconciliation fix ("Listing Details must auto-update without
  /// refresh"): while [_CarDetailsPageMedia._showProcessingMedia] is
  /// true, periodically re-fetches this listing so newly-landed remote
  /// URLs are picked up WITHOUT the owner needing to pull-to-refresh or
  /// leave and reopen the page. Null whenever no poll is currently
  /// scheduled (not an owner, nothing pending, or disposed/backgrounded)
  /// -- see `_CarDetailsPageLoad._maybeScheduleOwnerMediaPoll`/
  /// `_cancelOwnerMediaPoll` for the single place that starts/stops it,
  /// which guarantees at most one timer ever exists for this page
  /// instance (no duplicate timers).
  Timer? _ownerMediaPollTimer;

  /// Exposed only so widget tests can assert that disposing this page (or
  /// reconciliation genuinely finishing) stops the poll timer -- mirrors
  /// the existing `debugLoadCarCancelToken` convention. Not read by
  /// production code.
  @visibleForTesting
  Timer? get debugOwnerMediaPollTimer => _ownerMediaPollTimer;

  /// Guards against two overlapping poll-triggered car-detail fetches
  /// (e.g. a slow network response still in flight when the next tick
  /// fires) -- see `_pollOwnerMediaOnce`.
  bool _ownerMediaPollInFlight = false;

  bool isFavorite = false;
  List<Map<String, dynamic>> similarCars = [];
  bool loadingSimilar = false;
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;
  int _listingColumnsPref = 2;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _contactButtonsKey = GlobalKey();
  bool _showStickyButtons = true;
}
