part of 'chat_pages.dart';

mixin _ChatConversationTransportRealtime on _ChatConversationTransportPaging {
  void _setupWebSocketListeners() {
    _messageSub?.cancel();
    _messageUpdateSub?.cancel();
    _messageDeleteSub?.cancel();
    _errorSub?.cancel();
    _messageSub = WebSocketService.messages.listen((message) {
      // Optional: filter by carId when payload includes it
      final payloadCarId = message['car_id']?.toString();
      if (payloadCarId != null &&
          payloadCarId.isNotEmpty &&
          payloadCarId != widget.carId) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _addMessageIfMissing(ChatMessage.fromJson(message));
        _refreshCarListingMeta();
      });
      _scrollToBottom();
    });
    _messageUpdateSub = WebSocketService.messageUpdates.listen((message) {
      final payloadCarId = message['car_id']?.toString();
      if (payloadCarId != null &&
          payloadCarId.isNotEmpty &&
          payloadCarId != widget.carId) {
        return;
      }
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
      final payloadCarId = message['car_id']?.toString();
      if (payloadCarId != null &&
          payloadCarId.isNotEmpty &&
          payloadCarId != widget.carId) {
        return;
      }
      if (!mounted) return;
      final updated = ChatMessage.fromJson(message);
      setState(() {
        _addMessageIfMissing(updated);
        if (_replyingToMessage?.id == updated.id) {
          _replyingToMessage = updated;
        }
      });
    });
    _errorSub = WebSocketService.errors.listen((err) {
      if (!mounted) return;
      if (err.trim().isEmpty) return;
      if (_isIgnorableSocketError(err)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_formatSocketErrorForUser(err)),
          backgroundColor: Colors.red,
        ),
      );
    });
  }

  void _joinChat() {
    WebSocketService.joinChat(widget.carId);
  }

  Future<void> _loadHistory() async {
    if (_loadingHistory) return;
    setState(() => _loadingHistory = true);
    try {
      final result = await ApiService.getChatMessagesByConversation(
        widget.carId,
        page: 1,
        perPage: _ChatConversationFields._perPage,
      );
      if (!mounted) return;
      final rows = (result['messages'] as List<Map<String, dynamic>>?) ?? [];
      final loaded = rows.map(ChatMessage.fromJson).toList();
      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      setState(() {
        _messages
          ..clear()
          ..addAll(loaded);
        _mergeInFlightMediaPending();
        final stillSending = OutgoingChatSendService.instance
            .inFlightMediaForConversation(widget.carId)
            .isNotEmpty;
        if (stillSending) {
          _isSending = true;
        }
        _currentPage = 1;
        _hasMoreMessages = result['has_more'] == true;
        _refreshCarListingMeta();
      });
      await _ensureCarListingMeta();
      _scrollToBottom(jump: true);
    } catch (e, st) { logNonFatal(e, st); 
      // Keep the page usable even if history fetch fails.
    } finally {
      if (mounted) {
        setState(() => _loadingHistory = false);
      } else {
        _loadingHistory = false;
      }
    }
  }
}
