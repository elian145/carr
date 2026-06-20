part of '../chat_pages.dart';

// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

extension ChatConversationHistory on _ChatConversationPageState {
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
          if (e.error != null) {
            _maybePromptPhoneVerification(context, e.error!);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_formatOutgoingChatError(context, e.error)),
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
          if (e.error != null) {
            _maybePromptPhoneVerification(context, e.error!);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_formatOutgoingChatError(context, e.error)),
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
          if (e.error != null) {
            _maybePromptPhoneVerification(context, e.error!);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_formatOutgoingChatError(context, e.error)),
              backgroundColor: Colors.red,
            ),
          );
        }
        finishSending();
        break;
    }
  }

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
    setState(() => _loadingOlderMessages = true);
    try {
      final nextPage = _currentPage + 1;
      final result = await ApiService.getChatMessagesByConversation(
        widget.carId,
        page: nextPage,
        perPage: _ChatConversationPageState._perPage,
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
        _currentPage = nextPage;
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
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (mounted) _pollNewMessages();
    });
  }

  Future<void> _pollNewMessages() async {
    try {
      final result = await ApiService.getChatMessagesByConversation(
        widget.carId,
        page: 1,
        perPage: _ChatConversationPageState._perPage,
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
    } catch (_) {}
  }

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
        .where((f) => _isImageFile(f) || _isVideoFile(f))
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

  Map<String, dynamic> _mergedListingMeta() {
    final out = <String, dynamic>{};
    void merge(Map<String, dynamic>? source) {
      if (source == null || source.isEmpty) return;
      for (final entry in source.entries) {
        final value = entry.value;
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isEmpty) continue;
        out[entry.key] = value;
      }
    }

    merge(_fetchedCarMeta);
    merge(_listingPreview);
    if (out.isEmpty && (widget.carTitle ?? '').trim().isNotEmpty) {
      out['title'] = widget.carTitle!.trim();
    }
    return out;
  }

  bool _listingMetaHasTranslatableIdentity(Map<String, dynamic> car) {
    return (car['brand'] ?? '').toString().trim().isNotEmpty &&
        (car['model'] ?? '').toString().trim().isNotEmpty;
  }

  void _refreshCarListingMeta() {
    if (_listingPreview != null) {
      final fromPreview =
          localizedListingTitle(context, _listingPreview!).trim();
      if (fromPreview.isNotEmpty) {
        _carDisplayTitle = fromPreview;
      }
      if ((_carImageUrl ?? '').isEmpty) {
        final image = listingImageUrlFromMap(_listingPreview!);
        if (image.isNotEmpty) _carImageUrl = image;
      }
    }
    for (final message in _messages.reversed) {
      final preview = message.listingPreview;
      if (preview == null || preview.isEmpty) continue;
      if ((_carDisplayTitle ?? '').trim().isEmpty) {
        final candidate = localizedListingTitle(context, preview).trim();
        if (candidate.isNotEmpty) {
          _carDisplayTitle = candidate;
        }
      }
      if ((_carImageUrl ?? '').isEmpty) {
        final image = listingImageUrlFromMap(preview);
        if (image.isNotEmpty) {
          _carImageUrl = image;
          return;
        }
      }
      if ((_carDisplayTitle ?? '').trim().isNotEmpty &&
          (_carImageUrl ?? '').trim().isNotEmpty) {
        return;
      }
    }
  }

  Future<void> _ensureCarListingMeta() async {
    _refreshCarListingMeta();
    final merged = _mergedListingMeta();
    final hasTranslatable = _listingMetaHasTranslatableIdentity(merged);
    if (hasTranslatable && (_carImageUrl ?? '').trim().isNotEmpty) {
      if (mounted) setState(() {});
      return;
    }
    try {
      final car = await ApiService.getCar(widget.carId);
      if (!mounted) return;
      final title = localizedListingTitle(context, car).trim();
      final image = listingImageUrlFromMap(car);
      if (title.isEmpty && image.isEmpty) return;
      setState(() {
        _fetchedCarMeta = Map<String, dynamic>.from(car);
        if (title.isNotEmpty) _carDisplayTitle = title;
        if (image.isNotEmpty) _carImageUrl = image;
      });
    } catch (_) {}
  }

  ChatMessage _buildPendingMediaGroupMessage(
    List<XFile> files, {
    Map<String, dynamic>? listingPreview,
    String? tempId,
    DateTime? createdAt,
    ChatReplyPreview? replyPreview,
    String? replyToMessageId,
    String? receiverIdOverride,
    String? carIdOverride,
  }) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final replyTo = _replyingToMessage;
    final effectiveReplyId = replyToMessageId ?? replyTo?.id;
    final effectiveReply =
        replyPreview ??
        (replyTo == null
            ? null
            : ChatReplyPreview(
                id: replyTo.id,
                senderId: replyTo.senderId,
                senderName: replyTo.senderName,
                content: _replyPreviewLabel(replyTo),
                messageType: replyTo.messageType,
                isDeleted: replyTo.isDeleted,
              ));
    final at = createdAt ?? DateTime.now();
    return ChatMessage(
      id: tempId ?? _temporaryMessageId(),
      senderId: authService.userId ?? '',
      receiverId: receiverIdOverride ?? widget.receiverId ?? '',
      carId: carIdOverride ?? widget.carId,
      replyToMessageId: effectiveReplyId,
      replyToMessage: effectiveReply,
      content: _mediaGroupPlaceholder(files.length),
      messageType: 'media_group',
      attachments: files
          .map(
            (file) => ChatAttachment(
              type: _isVideoFile(file) ? 'video' : 'image',
              url: file.path,
              isLocal: true,
            ),
          )
          .toList(),
      listingPreview: listingPreview,
      isRead: true,
      createdAt: at,
      isPending: true,
    );
  }

  ChatMessage _buildPendingAudioMessage(
    XFile file, {
    String? tempId,
    DateTime? createdAt,
  }) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final replyTo = _replyingToMessage;
    final effectiveReply = replyTo == null
        ? null
        : ChatReplyPreview(
            id: replyTo.id,
            senderId: replyTo.senderId,
            senderName: replyTo.senderName,
            content: _replyPreviewLabel(replyTo),
            messageType: replyTo.messageType,
            isDeleted: replyTo.isDeleted,
          );
    final at = createdAt ?? DateTime.now();
    return ChatMessage(
      id: tempId ?? _temporaryMessageId(),
      senderId: authService.userId ?? '',
      receiverId: widget.receiverId ?? '',
      carId: widget.carId,
      replyToMessageId: replyTo?.id,
      replyToMessage: effectiveReply,
      content: _chatText(
        context,
        '[Voice message]',
        ar: '[رسالة صوتية]',
        ku: '[پەیامی دەنگی]',
      ),
      messageType: 'audio',
      attachmentUrl: file.path,
      attachments: [
        ChatAttachment(type: 'audio', url: file.path, isLocal: true),
      ],
      isRead: true,
      createdAt: at,
      isPending: true,
    );
  }

  Map<String, dynamic>? _replyToPreviewJson(ChatMessage? message) {
    if (message == null) return null;
    return ChatReplyPreview(
      id: message.id,
      senderId: message.senderId,
      senderName: message.senderName,
      content: _replyPreviewLabel(message),
      messageType: message.messageType,
      isDeleted: message.isDeleted,
    ).toJson();
  }

  ChatMessage _pendingMessageFromInFlight(InFlightMediaSend r) {
    ChatReplyPreview? replyToMessage;
    final json = r.replyToPreviewJson;
    if (json != null && json.isNotEmpty) {
      replyToMessage = ChatReplyPreview.fromJson(json);
    }
    return _buildPendingMediaGroupMessage(
      r.files,
      listingPreview: r.listingPreview,
      tempId: r.tempMessageId,
      createdAt: r.startedAt,
      replyPreview: replyToMessage,
      replyToMessageId: r.replyToMessageId,
      receiverIdOverride: r.receiverId,
      carIdOverride: r.carId,
    );
  }

}
