part of 'sell_flow.dart';

mixin _SellStep4Fields on State<SellStep4Page> {
  static const String _draftKey = 'legacy_sell_draft_step4_v1';
  final ImagePicker _imagePicker = ImagePicker();
  _SellCarPageState? _parentState;
  // Can contain either local XFile (original picks) or server-relative paths (after "Blur Plates").
  List<dynamic> _selectedImages = [];
  /// Local picks and/or server-relative paths for damage / crash disclosure.
  List<dynamic> _damageImages = [];
  final List<XFile> _selectedVideos = [];
  bool _isProcessingImages = false;
  bool _imagesProcessed = false;
}
