part of 'chat_pages.dart';

abstract class _ChatConversationFields extends State<ChatConversationPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _composerScrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _messageUpdateSub;
  StreamSubscription<Map<String, dynamic>>? _messageDeleteSub;
  StreamSubscription<Map<String, dynamic>>? _messageReadSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  StreamSubscription<OutgoingChatSendEvent>? _outgoingSendSub;
  StreamSubscription<bool>? _socketConnectionSub;
  bool _isSending = false;
  bool _loadingHistory = false;
  bool _historyLoadError = false;
  bool _loadingOlderMessages = false;
  bool _hasMoreMessages = false;
  static const int _perPage = 50;
  Timer? _pollTimer;
  Timer? _typingDebounce;
  Timer? _scrollRetryTimer;
  bool _isTyping = false;
  String? _otherUserTypingName;
  String? _carDisplayTitle;
  String? _carImageUrl;
  Map<String, dynamic>? _listingPreview;
  Map<String, dynamic>? _fetchedCarMeta;
  bool _pendingInitialListingContext = false;

  /// Temp ids of outgoing messages the user removed or recalled before the send finished.
  final Set<String> _discardedOutgoingIds = <String>{};
  final List<XFile> _draftAttachments = <XFile>[];
  final List<ChatAttachment> _editingKeepAttachments = <ChatAttachment>[];
  ChatMessage? _replyingToMessage;
  String? _editingMessageId;
  String? _highlightMessageId;
  Timer? _highlightTimer;
  final AudioRecorder _voiceRecorder = AudioRecorder();
  bool _isRecordingVoice = false;
  Duration _voiceRecordDuration = Duration.zero;
  Timer? _voiceRecordTimer;
  String? _voiceRecordPath;

  /// Verified account this conversation screen was opened for (F-34/F-35).
  /// Captured once; every send, pending-record lookup and send event is checked
  /// against it so a screen can never act for -- or show data of -- a
  /// different account than the one it belongs to.
  String? _ownerUserId;

  bool get _pageOwnerIsCurrent => ApiService.currentAccountId == _ownerUserId;

  /// The live counterpart (public id), or `null` when there is none (a buyer
  /// opening a listing: the counterpart is the seller; or a deleted account).
  String? get _livePeerId {
    final r = widget.receiverId?.trim();
    return (r == null || r.isEmpty) ? null : r;
  }

  /// What history requests send as `peer_id` (F-05): the live counterpart, or
  /// the `deleted-user:<n>` key of a deleted one.
  String? get _historyPeerRef {
    final live = _livePeerId;
    if (live != null) return live;
    final k = widget.peerKey?.trim();
    return (k == null || k.isEmpty) ? null : k;
  }

  /// Which realtime events belong to THIS conversation (listing + counterpart).
  ChatConversationScope get _conversationScope => ChatConversationScope(
        carId: widget.carId,
        myId: _ownerUserId ?? ApiService.currentAccountId,
        peerId: _livePeerId,
      );

  /// Immediately-before-send ownership check. Returns false (and tells the
  /// user) when the signed-in account is no longer the one this screen was
  /// opened for; the composer content is left untouched.
  bool _ensurePageOwnerStillSignedIn() {
    if (_ownerUserId != null && _pageOwnerIsCurrent) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              ApiSessionChangedException(),
              fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
    return false;
  }
}
