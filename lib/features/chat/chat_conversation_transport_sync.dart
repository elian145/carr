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

  void _showSendFailedSnackBar(Object? errorCause, String? error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userErrorText(
            context,
            errorCause ?? Exception(error ?? 'Send failed'),
            fallback: chatText(
              context,
              'Send failed',
              ar: 'فشل الإرسال',
              ku: 'ناردن سەرکەوتوو نەبوو',
            ),
          ),
        ),
        backgroundColor: Colors.red,
      ),
    );
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
        } else if (!e.success &&
            e.tempMessageId != null &&
            e.pendingRetry) {
          // F-11: retryable failure — a durable pending record was already
          // persisted by OutgoingChatSendService. Keep the pending bubble
          // as-is (still shown as "sending") instead of restoring the
          // composer/draft attachments, since a background retry is
          // expected; do not spam a "Send failed" snackbar for what may
          // just be a brief connectivity blip.
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
          _showSendFailedSnackBar(e.errorCause, e.error);
        }
        finishSending();
        break;
      case OutgoingChatSendKind.textMessage:
        if (e.success && e.messageJson != null) {
          setState(() {
            if (e.tempMessageId != null &&
                _discardedOutgoingIds.remove(e.tempMessageId!)) {
              // User recalled the pending message before this resolved.
            } else if (e.tempMessageId != null) {
              _replaceMessage(
                e.tempMessageId!,
                ChatMessage.fromJson(e.messageJson!),
              );
            } else {
              _addMessageIfMissing(ChatMessage.fromJson(e.messageJson!));
            }
            _pendingInitialListingContext = false;
            _replyingToMessage = null;
          });
          _scrollToBottom();
        } else if (e.pendingRetry) {
          // F-11: retryable failure — keep the pending text bubble as-is;
          // a durable record was persisted and will be retried
          // automatically (connectivity return / chat reopen / app
          // restart), reusing the same idempotency key. Do not restore the
          // composer (that would let the user create a second, duplicate
          // logical send) and do not show a noisy error for a transient
          // blip.
        } else {
          if (e.tempMessageId != null) {
            setState(() => _removeMessage(e.tempMessageId!));
          }
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
          _showSendFailedSnackBar(e.errorCause, e.error);
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
        } else if (!e.success &&
            e.tempMessageId != null &&
            e.pendingRetry) {
          // F-11: retryable failure — keep the pending audio bubble; a
          // durable record was persisted for automatic background retry.
        } else if (!e.success && e.tempMessageId != null) {
          setState(() {
            _removeMessage(e.tempMessageId!);
          });
          _showSendFailedSnackBar(e.errorCause, e.error);
        }
        finishSending();
        break;
    }
  }
}
