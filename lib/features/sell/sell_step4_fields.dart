part of 'sell_flow.dart';

mixin _SellStep4Fields on State<SellStep4Page> {
  static const String _draftKey = 'legacy_sell_draft_step4_v1';
  final ImagePicker _imagePicker = ImagePicker();
  _SellCarPageState? _parentState;
  /// Original unblurred picks (and/or restored originals).
  List<dynamic> _selectedImages = [];
  /// Parallel blurred versions produced by auto plate blur.
  List<dynamic> _blurredImages = [];
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
