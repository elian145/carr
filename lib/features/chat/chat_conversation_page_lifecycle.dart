part of 'chat_pages.dart';

mixin _ChatConversationPageLifecycle on _ChatConversationMessageUi, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    _carDisplayTitle = widget.carTitle?.trim();
    _carImageUrl = resolveListingImageUrl(widget.carImageUrl);
    _listingPreview = widget.initialListingPreview == null
        ? null
        : Map<String, dynamic>.from(widget.initialListingPreview!);
    if ((_carDisplayTitle ?? '').isEmpty && _listingPreview != null) {
      final fromPreview =
          localizedListingTitle(context, _listingPreview!).trim();
      if (fromPreview.isNotEmpty) {
        _carDisplayTitle = fromPreview;
      }
    }
    if ((_carImageUrl ?? '').isEmpty && _listingPreview != null) {
      final fromPreview = listingImageUrlFromMap(_listingPreview!);
      if (fromPreview.isNotEmpty) {
        _carImageUrl = fromPreview;
      }
    }
    _pendingInitialListingContext = _listingPreview != null;
    final initialDraft = widget.initialDraft?.trim() ?? '';
    if (initialDraft.isNotEmpty) {
      _messageController.text = initialDraft;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    }
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _setupWebSocketListeners();
    _setupTypingListener();
    _outgoingSendSub = OutgoingChatSendService.instance.events.listen(
      _onOutgoingChatSendEvent,
    );
    _loadHistory();
    _joinChat();
    _startPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollComposerToTop();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _pollNewMessages();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _typingDebounce?.cancel();
    _scrollRetryTimer?.cancel();
    _highlightTimer?.cancel();
    _voiceRecordTimer?.cancel();
    if (_isRecordingVoice) {
      unawaited(_voiceRecorder.stop());
    }
    unawaited(_voiceRecorder.dispose());
    if (_isTyping) {
      WebSocketService.sendTypingStop(widget.carId);
    }
    _messageSub?.cancel();
    _messageUpdateSub?.cancel();
    _messageDeleteSub?.cancel();
    _errorSub?.cancel();
    _typingSub?.cancel();
    _outgoingSendSub?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _composerScrollController.dispose();
    WebSocketService.leaveChat();
    super.dispose();
  }

  GlobalKey _keyForMessageId(String id) {
    return _messageKeys.putIfAbsent(id, () => GlobalKey());
  }
}
