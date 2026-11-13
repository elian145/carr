part of 'chat_pages.dart';

mixin _ChatConversationTransportRealtime on _ChatConversationTransportPaging {
  void _setupWebSocketListeners() {
    _messageSub?.cancel();
    _messageUpdateSub?.cancel();
    _messageDeleteSub?.cancel();
    _messageReadSub?.cancel();
    _errorSub?.cancel();
    // Socket (re)connected: retry a read that could not be sent while offline,
    // and fetch whatever was sent while the socket was down (it never reached
    // this page). The reconnect `join_chat` reports the real visibility, so a
    // covered / backgrounded conversation is not marked read by it.
    // (Only a drop observed while this page is open counts: the first connect
    // of a freshly opened chat is covered by its own history load + join.)
    _socketWasDown = false;
    _readConnectionSub?.cancel();
    _readConnectionSub = WebSocketService.connectionState.listen((connected) {
      if (!mounted) return;
      if (!connected) {
        _socketWasDown = true;
        return;
      }
      if (_socketWasDown) {
        _socketWasDown = false;
        _catchUpNeeded = true;
        _catchUpFailures = 0;
        unawaited(_catchUpMissedMessages());
      }
      _scheduleMarkRead();
    });
    _messageSub = WebSocketService.messages.listen((message) {
      // Only THIS conversation's messages (same listing AND same
      // counterpart): a seller's other buyers' messages are not shown here.
      if (!_conversationScope.matchesMessage(message)) return;

      if (!mounted) return;
      final incoming = ChatMessage.fromJson(message);
      setState(() {
        _addMessageIfMissing(incoming);
        _refreshCarListingMeta();
      });
      _scrollToBottom();
      _noteInboundForRead(incoming);
    });
    _messageUpdateSub = WebSocketService.messageUpdates.listen((message) {
      if (!_conversationScope.matchesMessage(message)) return;

      if (!mounted) return;
      final updated = ChatMessage.fromJson(message);
      setState(() {
        _addMessageIfMissing(updated);
        if (_replyingToMessage?.id == updated.id) {
          _replyingToMessage = updated;
        }
      });
    });
    _messageDeleteSub = WebSocketService.messageDeletes.listen((message) {
      if (!_conversationScope.matchesMessage(message)) return;

      if (!mounted) return;
      final updated = ChatMessage.fromJson(message);
      setState(() {
        _addMessageIfMissing(updated);
        if (_replyingToMessage?.id == updated.id) {
          _replyingToMessage = updated;
        }
      });
    });
    _messageReadSub = WebSocketService.messageReads.listen((event) {
      if (!_conversationScope.matchesRead(event)) return;

      if (!mounted) return;
      final rawIds = event['message_ids'];
      final idSet = <String>{};
      if (rawIds is List) {
        for (final id in rawIds) {
          final s = id?.toString() ?? '';
          if (s.isNotEmpty) idSet.add(s);
        }
      }
      final auth = Provider.of<AuthService>(context, listen: false);
      final myId = auth.userId;
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final m = _messages[i];
          if (m.senderId != myId || m.isRead || m.isPending) continue;
          if (idSet.isEmpty || idSet.contains(m.id)) {
            _messages[i] = m.copyWith(isRead: true);
          }
        }
      });
    });
    _errorSub = WebSocketService.errors.listen((err) {
      if (!mounted) return;
      if (err.trim().isEmpty) return;
      if (_isIgnorableSocketError(err)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              Exception(err),
              fallback: _formatSocketErrorForUser(err),
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    });
  }

  // ---- Live read receipts ---------------------------------------------------

  /// A message just arrived in this conversation: if it came from the
  /// counterpart, remember it as unreported and try to report it.
  void _noteInboundForRead(ChatMessage message) {
    if (message.isPending || message.isRead) return;
    final me = (_ownerUserId ?? '').trim();
    if (me.isEmpty || message.senderId == me) return; // my own message
    _readPending = true;
    _scheduleMarkRead();
  }

  /// Report pending inbound messages as read, debounced. A no-op unless there is
  /// something pending AND the conversation is on screen; otherwise the read
  /// stays pending and is retried (immediately on app resume / socket
  /// reconnect, and by [_readRetryTimer] for everything else, e.g. a dialog or
  /// page being closed -- those have no reliable callback for a covered page).
  @override
  void _scheduleMarkRead() {
    if (!_readPending && !_catchUpNeeded) return;
    if (!_canMarkRead) {
      _armReadRetry();
      return;
    }
    if (_markReadDebounce?.isActive == true) return; // one emit per burst
    _markReadDebounce = Timer(kChatMarkReadDebounce, _flushMarkRead);
  }

  void _flushMarkRead() {
    _markReadDebounce = null;
    if (!_readPending && !_catchUpNeeded) return;
    if (!_canMarkRead) {
      _armReadRetry(); // covered/backgrounded meanwhile
      return;
    }
    if (_catchUpNeeded) {
      // The reconnect catch-up could not run yet (or failed) and the user is
      // looking now: fetch -- the server marks what it returns read -- instead
      // of reporting messages this page has not even loaded.
      _catchUpFailures = 0;
      unawaited(_catchUpMissedMessages());
      return;
    }
    // A deleted counterpart has no live socket conversation (REST history
    // already marks those read).
    if (_livePeerId == null && widget.peerKey != null) {
      _readPending = false;
      return;
    }
    // Not queued while offline (see WebSocketService.markRead): stays pending.
    if (WebSocketService.markRead(widget.carId, peerId: _livePeerId)) {
      _readPending = false;
    } else {
      _armReadRetry();
    }
  }

  /// Cheap poll that exists only while a read is pending and cannot be sent.
  void _armReadRetry() {
    if (_readRetryTimer?.isActive == true) return;
    _readRetryTimer = Timer.periodic(kChatMarkReadRetryInterval, (timer) {
      if (!mounted || (!_readPending && !_catchUpNeeded)) {
        timer.cancel();
        _readRetryTimer = null;
        return;
      }
      if (_canMarkRead && WebSocketService.isConnected) {
        timer.cancel();
        _readRetryTimer = null;
        _scheduleMarkRead();
      }
    });
  }

  /// After a socket reconnect: fetch the messages that were sent while the
  /// socket was down. Whether the fetch also reports them read is decided
  /// inside [_fetchLatestMessages] from the REAL visibility (covered or
  /// backgrounded -> left unread and remembered as pending). A failed fetch is
  /// retried a bounded number of times; if it still has not succeeded,
  /// `_catchUpNeeded` stays set and the next time the user is looking at the
  /// conversation the flush fetches again.
  Future<void> _catchUpMissedMessages() async {
    if (_catchUpInFlight || !_catchUpNeeded) return;
    _catchUpInFlight = true;
    var ok = false;
    try {
      ok = await _fetchLatestMessages();
    } finally {
      _catchUpInFlight = false;
    }
    if (!mounted) return;
    if (ok) {
      _catchUpNeeded = false;
      _catchUpFailures = 0;
      _scheduleMarkRead(); // a socket-reported read may still be pending
      return;
    }
    _catchUpFailures++;
    if (_catchUpFailures < kChatCatchUpMaxRetries) {
      _catchUpRetryTimer?.cancel();
      _catchUpRetryTimer = Timer(kChatCatchUpRetryDelay, () {
        _catchUpRetryTimer = null;
        if (mounted) unawaited(_catchUpMissedMessages());
      });
    } else {
      _scheduleMarkRead(); // wait for the user to be looking, then fetch again
    }
  }

  void _stopReadWatchers() {
    _readConnectionSub?.cancel();
    _readConnectionSub = null;
    _markReadDebounce?.cancel();
    _markReadDebounce = null;
    _readRetryTimer?.cancel();
    _readRetryTimer = null;
    _catchUpRetryTimer?.cancel();
    _catchUpRetryTimer = null;
    WebSocketService.unregisterConversationVisibility(_conversationOnScreen);
  }

  void _joinChat() {
    // A deleted counterpart has no live socket room to join.
    if (_livePeerId == null && widget.peerKey != null) return;
    // Lets a reconnect re-join report whether the conversation is really on
    // screen (see WebSocketService._rejoinPayload).
    WebSocketService.registerConversationVisibility(_conversationOnScreen);
    WebSocketService.joinChat(widget.carId, peerId: _livePeerId);
  }

  Future<void> _loadHistory() async {
    if (_loadingHistory) return;
    setState(() {
      _loadingHistory = true;
      _historyLoadError = false;
    });
    try {
      // No `before` cursor: fetches the NEWEST page of messages so the
      // conversation always opens at the latest message, not the oldest.
      final result = await ApiService.getChatMessagesByConversation(
        widget.carId,
        perPage: _ChatConversationFields._perPage,
        peerId: _historyPeerRef,
      );
      if (!mounted || !_pageOwnerIsCurrent) return;
      final rows = (result['messages'] as List<Map<String, dynamic>>?) ?? [];
      final loaded = rows.map(ChatMessage.fromJson).toList();
      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      setState(() {
        _messages
          ..clear()
          ..addAll(loaded);
        _mergeInFlightMediaPending();
        final stillSending = OutgoingChatSendService.instance
            .inFlightMediaForConversation(
                  widget.carId,
                  ownerUserId: _ownerUserId,
                  peerId: _historyPeerRef,
                )
            .isNotEmpty;
        if (stillSending) {
          _isSending = true;
        }
        _hasMoreMessages = result['has_more'] == true;
        _refreshCarListingMeta();
      });
      // F-11: rehydrate any durable pending sends for this conversation
      // (a REST send that failed with a retryable error before this page
      // was reopened — possibly after an app restart) and kick off a
      // bounded recovery attempt for them.
      final persistedPending =
          await ChatPendingSendPrefs.loadForConversation(
        widget.carId,
        ownerUserId: _ownerUserId,
        peerId: _historyPeerRef,
      );
      if (!mounted || !_pageOwnerIsCurrent) return;
      if (persistedPending.isNotEmpty) {
        setState(() {
          _mergePersistedPendingSends(persistedPending);
        });
      }
      unawaited(
        OutgoingChatSendService.instance
            .recoverPendingSends(conversationId: widget.carId),
      );
      await _ensureCarListingMeta();
      _scrollToBottom(jump: true);
    } catch (e, st) {
      logNonFatal(e, st);
      // Surface a retry affordance when there are no messages to show.
      _historyLoadError = true;
    } finally {
      if (mounted) {
        setState(() => _loadingHistory = false);
      } else {
        _loadingHistory = false;
      }
    }
  }
}
