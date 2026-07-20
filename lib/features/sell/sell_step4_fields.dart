part of 'sell_flow.dart';

mixin _SellStep4Fields on State<SellStep4Page> {
  static const String _draftKey = 'legacy_sell_draft_step4_v1';
  final ImagePicker _imagePicker = ImagePicker();
  _SellCarPageState? _parentState;
  /// Original unblurred picks (and/or restored originals).
  List<dynamic> _selectedImages = [];
  /// Parallel blurred versions produced by auto plate blur.
  List<dynamic> _blurredImages = [];
  /// Local picks and/or server-relative paths for damage / crash disclosure.
  List<dynamic> _damageImages = [];
  final List<XFile> _selectedVideos = [];
  bool _isProcessingImages = false;
  bool _imagesProcessed = false;
}
