part of 'chat_pages.dart';

mixin _ChatConversationTransportPaging on _ChatConversationTransportMedia {
  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels <=
            _scrollController.position.minScrollExtent + 80 &&
        _hasMoreMessages &&
        !_loadingOlderMessages) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlderMessages || !_hasMoreMessages) return;
    if (_messages.isEmpty) return;
    setState(() => _loadingOlderMessages = true);
    try {
      // Cursor into strictly-older history: the oldest message currently
      // loaded on screen. This is the only supported pagination contract
      // (no parallel offset/page scheme) -- see kk/routes/chat.py::get_messages.
      final oldestLoaded = _messages.first.createdAt;
      final result = await ApiService.getChatMessagesByConversation(
        widget.carId,
        perPage: _ChatConversationFields._perPage,
        before: oldestLoaded.toUtc().toIso8601String(),
      );
      if (!mounted) return;
      final rows = (result['messages'] as List<Map<String, dynamic>>?) ?? [];
      final loaded = rows.map(ChatMessage.fromJson).toList();
      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final prevOffset = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;

      setState(() {
        for (final m in loaded) {
          _addMessageIfMissing(m);
        }
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _hasMoreMessages = result['has_more'] == true;
        _refreshCarListingMeta();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final newOffset = _scrollController.position.maxScrollExtent;
        final diff = newOffset - prevOffset;
        if (diff > 0) {
          _scrollController.jumpTo(_scrollController.offset + diff);
        }
      });
    } catch (e, st) { logNonFatal(e, st); } finally {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  void _startPolling() {
    _socketConnectionSub?.cancel();
    _socketConnectionSub = WebSocketService.connectionState.listen((connected) {
      if (!mounted) return;
      _syncHttpFallbackPolling(socketConnected: connected);
    });
    _syncHttpFallbackPolling(socketConnected: WebSocketService.isConnected);
  }

  /// REST poll only while Socket.IO is down (P-10 single-transport strategy).
  void _syncHttpFallbackPolling({required bool socketConnected}) {
    if (!shouldHttpPollChatMessages(socketConnected: socketConnected)) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_pollTimer?.isActive == true) return;
    _pollTimer = Timer.periodic(kChatHttpFallbackPollInterval, (_) {
      if (!mounted) return;
      if (!shouldHttpPollChatMessages(
        socketConnected: WebSocketService.isConnected,
      )) {
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }
      unawaited(_pollNewMessages());
    });
  }

  Future<void> _pollNewMessages() async {
    if (!shouldHttpPollChatMessages(
      socketConnected: WebSocketService.isConnected,
    )) {
      return;
    }
    try {
      // No `before` cursor: REST fallback polling always wants the latest
      // page (new messages arrive at the end, not on some offset page).
      final result = await ApiService.getChatMessagesByConversation(
        widget.carId,
        perPage: _ChatConversationFields._perPage,
      );
      if (!mounted) return;
      final rows = (result['messages'] as List<Map<String, dynamic>>?) ?? [];
      final loaded = rows.map(ChatMessage.fromJson).toList();
      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final hadMessages = _messages.length;
      setState(() {
        for (final m in loaded) {
          _addMessageIfMissing(m);
        }
        _mergeInFlightMediaPending();
        if (OutgoingChatSendService.instance
            .inFlightMediaForConversation(widget.carId)
            .isNotEmpty) {
          _isSending = true;
        }
        _refreshCarListingMeta();
      });
      if (_messages.length > hadMessages) {
        _scrollToBottom();
      }
    } catch (e, st) { logNonFatal(e, st); }
  }
}
