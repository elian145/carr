part of 'chat_pages.dart';

mixin _ChatConversationTransportStore on _ChatConversationFields {
  void _addMessageIfMissing(ChatMessage message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      _messages[index] = message;
      return;
    }
    _messages.add(message);
  }

  void _replaceMessage(String oldId, ChatMessage message) {
    final index = _messages.indexWhere((m) => m.id == oldId);
    if (index == -1) {
      _addMessageIfMissing(message);
      return;
    }
    _messages[index] = message;
  }

  void _removeMessage(String id) {
    _messages.removeWhere((m) => m.id == id);
  }

  bool get _hasDraftAttachments => _draftAttachments.isNotEmpty;

  void _addDraftAttachments(List<XFile> files) {
    final valid = files
        .where((f) => _chatIsImageFile(f) || _chatIsVideoFile(f))
        .toList();
    if (valid.isEmpty) return;
    const maxCount = 10;
    final remaining = maxCount - _draftAttachments.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _chatText(
              context,
              'You can attach up to 10 files.',
              ar: 'دەتوانیت تەنها تا 10 فایل زیاد بکەیت.',
              ku: 'دەتوانیت تەنها تا 10 فایل زیاد بکەیت.',
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final toAdd = valid.take(remaining).toList();
    setState(() {
      _draftAttachments.addAll(toAdd);
      _pendingInitialListingContext = _pendingInitialListingContext;
    });
    if (valid.length > toAdd.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _chatText(
              context,
              'Only the first 10 attachments were added.',
              ar: 'تەنها یەکەم 10 پاشکۆ زیاد کران.',
              ku: 'تەنها یەکەم 10 پاشکۆ زیاد کران.',
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
    _focusComposer();
  }

  void _removeDraftAttachmentAt(int index) {
    if (index < 0 || index >= _draftAttachments.length) return;
    setState(() {
      _draftAttachments.removeAt(index);
    });
  }

  void _clearDraftAttachments() {
    if (_draftAttachments.isEmpty) return;
    setState(() {
      _draftAttachments.clear();
    });
  }

  ChatMessage? _messageById(String id) {
    for (final message in _messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _startReplyToMessage(ChatMessage message) {
    setState(() {
      _replyingToMessage = message;
      _editingMessageId = null;
    });
    _focusComposer();
  }

  void _startEditingMessage(ChatMessage message) {
    final isPlaceholder = _isAttachmentPlaceholder(message.content);
    _editingKeepAttachments
      ..clear()
      ..addAll(_attachmentsForEdit(message));
    _clearDraftAttachments();
    setState(() {
      _editingMessageId = message.id;
      _replyingToMessage = null;
      _messageController.text = isPlaceholder ? '' : message.content;
      _pendingInitialListingContext = false;
    });
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: _messageController.text.length),
    );
    _focusComposer();
  }

  void _cancelComposerAction() {
    if (_replyingToMessage == null && _editingMessageId == null) return;
    setState(() {
      _replyingToMessage = null;
      _editingMessageId = null;
    });
    _editingKeepAttachments.clear();
  }

  List<ChatAttachment> _attachmentsForEdit(ChatMessage message) {
    if (message.attachments.isNotEmpty) return message.attachments;
    final url = (message.attachmentUrl ?? '').trim();
    final typ = message.messageType.trim().toLowerCase();
    if (url.isNotEmpty && (typ == 'image' || typ == 'video' || typ == 'audio')) {
      return [ChatAttachment(type: typ, url: url)];
    }
    return const <ChatAttachment>[];
  }

  void _focusComposer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageFocusNode.requestFocus();
    });
  }

  String _replyPreviewLabel(ChatMessage message) {
    if (message.isDeleted) return _chatMessageDeletedText(context);
    if (message.listingPreview != null) {
      return AppLocalizations.of(context)?.listingTitle ?? 'Listing';
    }
    if (_isAudioMessage(message)) {
      return _chatText(
        context,
        'Voice message',
        ar: 'رسالة صوتية',
        ku: 'پەیامی دەنگی',
      );
    }
    if (message.attachments.isNotEmpty) {
      final hasVideo = message.attachments.any((item) => item.type == 'video');
      if (message.attachments.length > 1) {
        return hasVideo
            ? _chatText(context, 'Media', ar: 'وسائط', ku: 'میدیا')
            : _chatText(context, 'Photos', ar: 'صور', ku: 'وێنەکان');
      }
      return hasVideo
          ? _chatText(context, 'Video', ar: 'فيديو', ku: 'ڤیدیۆ')
          : _chatText(context, 'Photo', ar: 'صورة', ku: 'وێنە');
    }
    return message.content.trim().isEmpty
        ? _chatText(context, 'Message', ar: 'رسالة', ku: 'پەیام')
        : message.content.trim();
  }

  String _temporaryMessageId() {
    return 'temp-${DateTime.now().microsecondsSinceEpoch}';
  }

  String _mediaGroupPlaceholder(int count) {
    return '[$count attachments]';
  }

  bool _isAttachmentPlaceholder(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    if (normalized == '[image]' ||
        normalized == '[video]' ||
        normalized == '[voice message]') {
      return true;
    }
    return RegExp(r'^\[\d+\s+attachments?\]$').hasMatch(normalized);
  }


  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      // Retry once shortly after layout updates (useful for long messages/images).
      _scrollRetryTimer?.cancel();
      _scrollRetryTimer = Timer(const Duration(milliseconds: 120), () {
        if (!mounted || !_scrollController.hasClients) return;
        final retryTarget = _scrollController.position.maxScrollExtent;
        if (jump) {
          _scrollController.jumpTo(retryTarget);
        } else {
          _scrollController.animateTo(
            retryTarget,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }
}
