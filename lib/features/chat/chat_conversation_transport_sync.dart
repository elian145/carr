part of 'chat_pages.dart';

mixin _ChatConversationTransportSync on _ChatConversationTransportStore {
  void _setupTypingListener() {
    _typingSub?.cancel();
    _typingSub = WebSocketService.typingEvents.listen((data) {
      if (!mounted) return;
      final isTyping = data['typing'] == true;
      final userName = (data['user_name'] ?? '').toString().trim();
      setState(() => _otherUserTypingName = isTyping ? userName : null);
    });
  }

  void _onTextChanged(String _) {
    if (!_isTyping) {
      _isTyping = true;
      WebSocketService.sendTypingStart(widget.carId);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _isTyping = false;
      WebSocketService.sendTypingStop(widget.carId);
    });
  }

  void _scrollComposerToTop() {
    if (!_composerScrollController.hasClients) return;
    _composerScrollController.jumpTo(0);
  }

  void _onOutgoingChatSendEvent(OutgoingChatSendEvent e) {
    if (e.conversationId != widget.carId || !mounted) return;

    void finishSending() {
      setState(() => _isSending = false);
    }

    switch (e.kind) {
      case OutgoingChatSendKind.mediaGroup:
        if (e.success && e.tempMessageId != null && e.messageJson != null) {
          setState(() {
            if (_discardedOutgoingIds.remove(e.tempMessageId!)) {
              // User removed or recalled before the upload finished.
            } else {
              _replaceMessage(
                e.tempMessageId!,
                ChatMessage.fromJson(e.messageJson!),
              );
            }
            _replyingToMessage = null;
            _pendingInitialListingContext = false;
          });
          _scrollToBottom();
        } else if (!e.success && e.tempMessageId != null) {
          setState(() {
            _removeMessage(e.tempMessageId!);
            final files = e.restoreFiles;
            if (files != null && files.isNotEmpty) {
              _draftAttachments.addAll(files);
            }
          });
          final cap = e.restoreCaption;
          if (cap != null && cap.isNotEmpty) {
            _messageController.text = cap;
            _messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: _messageController.text.length),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollComposerToTop();
            });
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.error ?? 'Send failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
        finishSending();
        break;
      case OutgoingChatSendKind.textMessage:
        if (e.success && e.messageJson != null) {
          setState(() {
            _addMessageIfMissing(ChatMessage.fromJson(e.messageJson!));
            _pendingInitialListingContext = false;
            _replyingToMessage = null;
          });
          _scrollToBottom();
        } else {
          final t = e.restoredPlainText ?? '';
          if (t.isNotEmpty) {
            _messageController.text = t;
            _messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: _messageController.text.length),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollComposerToTop();
            });
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.error ?? 'Send failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
        finishSending();
        break;
      case OutgoingChatSendKind.audio:
        if (e.success && e.tempMessageId != null && e.messageJson != null) {
          setState(() {
            if (_discardedOutgoingIds.remove(e.tempMessageId!)) {
              // User removed before upload finished.
            } else {
              _replaceMessage(
                e.tempMessageId!,
                ChatMessage.fromJson(e.messageJson!),
              );
            }
            _replyingToMessage = null;
            _pendingInitialListingContext = false;
          });
          _scrollToBottom();
        } else if (!e.success && e.tempMessageId != null) {
          setState(() {
            _removeMessage(e.tempMessageId!);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.error ?? 'Send failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
        finishSending();
        break;
    }
  }
}
