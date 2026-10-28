part of 'chat_pages.dart';

mixin _ChatConversationPageLifecycle on _ChatConversationMessageUi, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    _ownerUserId = ApiService.currentAccountId;
    _carDisplayTitle = widget.carTitle?.trim();
    _carImageUrl = resolveListingImageUrl(widget.carImageUrl);
    _listingPreview = widget.initialListingPreview == null
        ? null
        : Map<String, dynamic>.from(widget.initialListingPreview!);
    // The localized listing title depends on the ambient `Localizations`, which
    // may not be read until initState() has completed -- see
    // [didChangeDependencies].
    if ((_carImageUrl ?? '').isEmpty && _listingPreview != null) {
      final fromPreview = listingImageUrlFromMap(_listingPreview!);
      if (fromPreview.isNotEmpty) {
        _carImageUrl = fromPreview;
      }
    }
    // Only prefill the composer with a ready-to-send listing card when the
    // caller explicitly opted in (the contact-seller/interested-in-listing
    // flow). `initialListingPreview` alone is not sufficient: it is also
    // supplied purely for display metadata (e.g. ChatListPage's cached car
    // title/image), which must NOT prefill the composer.
    _pendingInitialListingContext =
        widget.prefillComposerWithListing && _listingPreview != null;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Localized listing title for a caller that supplied only a listing
    // preview (the chat list does). Runs right after initState() and again
    // whenever `Localizations` changes, so the title follows a locale switch.
    // A caller-supplied `carTitle` is authoritative and is left alone.
    final preview = _listingPreview;
    if ((widget.carTitle ?? '').trim().isEmpty && preview != null) {
      final fromPreview = localizedListingTitle(context, preview).trim();
      if (fromPreview.isNotEmpty) {
        _carDisplayTitle = fromPreview;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // One-shot HTTP sync only when the socket is down; otherwise realtime owns updates.
      if (shouldHttpPollChatMessages(
        socketConnected: WebSocketService.isConnected,
      )) {
        unawaited(_pollNewMessages());
      }
      _syncHttpFallbackPolling(socketConnected: WebSocketService.isConnected);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _socketConnectionSub?.cancel();
    _typingDebounce?.cancel();
    _scrollRetryTimer?.cancel();
    _highlightTimer?.cancel();
    _voiceRecordTimer?.cancel();
    if (_isRecordingVoice) {
      unawaited(_voiceRecorder.stop());
    }
    unawaited(_voiceRecorder.dispose());
    if (_isTyping) {
      WebSocketService.sendTypingStop(widget.carId, peerId: _livePeerId);
    }
    _messageSub?.cancel();
    _messageUpdateSub?.cancel();
    _messageDeleteSub?.cancel();
    _messageReadSub?.cancel();
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
