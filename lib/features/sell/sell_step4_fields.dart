part of 'sell_flow.dart';

mixin _SellStep4Fields on State<SellStep4Page> {
  static const String _draftKey = 'legacy_sell_draft_step4_v1';
  final ImagePicker _imagePicker = ImagePicker();
  _SellCarPageState? _parentState;
  /// Original unblurred picks (and/or restored originals).
  List<dynamic> _selectedImages = [];
  /// Parallel blurred versions produced by auto plate blur.
  List<dynamic> _blurredImages = [];
  /// Original (picker) paths of HEIC/HEIF photos whose JPEG preview
  /// generation (`HeicPreviewConverter.ensureJpegPreview`, via
  /// `_backfillImageDimensions`) is currently in flight -- lets the grid
  /// tile (`sell_step4_build_photos.dart`) show a loading spinner instead
  /// of the raw, Skia-undecodable HEIC file (which would otherwise render
  /// as a "broken image" icon for the few seconds conversion takes).
  /// A path is removed once that item's backfill attempt finishes,
  /// regardless of success or failure -- so a path absent from this set
  /// with no `preview_source` set means "already tried and gave up"
  /// (falls through to the pre-existing broken-image fallback), never
  /// "still pending" forever.
  final Set<String> _heicPreviewPending = {};
  /// Monotonic counter folded into every freshly-picked item's
  /// `_ui_media_id` seed (see `ListingImageMedia.map`'s doc comment) so
  /// re-picking the exact same file path after deleting it is always
  /// treated as a brand-new identity, never the deleted one's -- per-path
  /// seeding alone would otherwise produce the SAME id both times.
  int _uiMediaSeq = 0;
  /// Generation token for `_syncMediaDraftToParent` (stale-media-after-
  /// delete fix): that method is fire-and-forget (`unawaited`) from
  /// several call sites (every pick's background chain, plus every
  /// delete handler) and durable-copies files over real, multi-second
  /// I/O -- two overlapping calls are a realistic scenario (e.g. delete
  /// one of several just-picked photos before their OWN pick's sync has
  /// finished), and whichever one's `setState` happens to land LAST would
  /// otherwise silently overwrite `_selectedImages`/`_blurredImages`/
  /// `_damageImages` with its own (possibly older/stale) resolved
  /// snapshot -- resurrecting an item deleted in the meantime. Only the
  /// MOST RECENTLY STARTED call's result is ever applied; every earlier,
  /// now-superseded call's result is silently discarded once it finishes.
  int _mediaSyncGeneration = 0;
  /// Cover photo index into [_selectedImages] (grid order is not changed).
  int _primaryImageIndex = 0;
  /// Local picks and/or server-relative paths for damage / crash disclosure.
  List<dynamic> _damageImages = [];
  final List<XFile> _selectedVideos = [];
  /// CarNet V1 batch-3: already-uploaded videos on the listing being
  /// edited (each a `{id, video_url, thumbnail_url, ...}` map from the
  /// server). Kept separate from [_selectedVideos] (newly-picked local
  /// files awaiting upload) so the existing pick/persist/upload pipeline
  /// for new videos is untouched -- this list exists purely so an owner
  /// editing a listing can see and delete videos that are already live on
  /// the server (backend `DELETE /api/cars/<id>/videos/<video_id>`).
  List<Map<String, dynamic>> _existingServerVideos = [];
  /// Preview-decoupling fix: pending server-transcode video specs whose
  /// ORIGINAL local source (`ServerTranscodeVideoSpec.localSourcePath`)
  /// is still previewable/playable, mirrored from
  /// `parentState.carData['server_transcode_videos']` purely so the video
  /// grid can render/play them immediately -- see
  /// `sell_step4_build_videos.dart` -- well BEFORE the actual server
  /// sign/upload/finalize/poll/attach pipeline
  /// (`sell_listing_media_upload.dart`) ever runs, exactly like
  /// [_existingServerVideos] mirrors already-uploaded server videos for
  /// display. NEVER used as an upload/submission source itself --
  /// `carData['server_transcode_videos']` (kept in sync alongside this
  /// field) remains the single source of truth the actual upload
  /// pipeline reads; this field exists ONLY so the Sell UI has something
  /// local to render from without re-deriving it from `carData` on every
  /// build.
  List<ServerTranscodeVideoSpec> _pendingServerTranscodeVideos = [];
  bool _isProcessingImages = false;
  bool _imagesProcessed = false;
  /// True while chosen photos/videos are being processed into the draft.
  bool _isImportingMedia = false;
  /// Non-null while a just-picked video is being probed/compressed (see
  /// `SellVideoCompression.prepare`) -- drives the "Preparing video…"
  /// overlay text so compression looks distinct from a plain photo import
  /// (task requirement: a user-visible "Preparing video…" state, and
  /// compression must never read as upload progress). Value itself
  /// ('probing'/'compressing') is not shown verbatim; only its
  /// null-ness matters to the UI.
  String? _videoPrepPhase;

  void _clampPrimaryImageIndex() {
    if (_selectedImages.isEmpty) {
      _primaryImageIndex = 0;
      return;
    }
    if (_primaryImageIndex < 0 ||
        _primaryImageIndex >= _selectedImages.length) {
      _primaryImageIndex = 0;
    }
  }

  void _onImageRemovedAt(int index) {
    // Call after removing the image at [index] from [_selectedImages].
    if (index == _primaryImageIndex) {
      _primaryImageIndex = 0;
    } else if (index < _primaryImageIndex) {
      _primaryImageIndex -= 1;
    }
    _clampPrimaryImageIndex();
  }
}
