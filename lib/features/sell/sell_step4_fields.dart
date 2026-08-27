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
  bool _isProcessingImages = false;
  bool _imagesProcessed = false;
  /// True while chosen photos/videos are being processed into the draft.
  bool _isImportingMedia = false;

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
