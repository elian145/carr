part of 'chat_pages.dart';

mixin _ChatConversationActions on _ChatConversationFields {
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
        perPage: _ChatConversationFields._perPage,
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
    } catch (e, st) { logNonFatal(e, st); } finally {
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
    } catch (e, st) { logNonFatal(e, st); }
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

  void _mergeInFlightMediaPending() {
    final inFlight = OutgoingChatSendService.instance
        .inFlightMediaForConversation(widget.carId);
    if (inFlight.isEmpty) return;
    var added = false;
    for (final r in inFlight) {
      if (_messages.any((m) => m.id == r.tempMessageId)) continue;
      _messages.add(_pendingMessageFromInFlight(r));
      added = true;
    }
    if (added) {
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
  }

  List<_ChatMediaEntry> _chatMediaEntries() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final myId = authService.userId ?? '';
    final myName = authService.userName.trim().isNotEmpty
        ? authService.userName.trim()
        : 'You';

    final entries = <_ChatMediaEntry>[];
    for (final message in _messages) {
      if (message.attachments.isEmpty) continue;
      final senderName = message.senderId == myId
          ? myName
          : ((message.senderName ?? '').trim().isNotEmpty
                ? message.senderName!.trim()
                : (AppLocalizations.of(context)?.unknownSender ?? 'Unknown'));
      for (final attachment in message.attachments) {
        entries.add(
          _ChatMediaEntry(attachment: attachment, senderName: senderName),
        );
      }
    }
    return entries;
  }

  void _openChatMediaViewer(
    ChatMessage message, {
    int initialAttachmentIndex = 0,
  }) {
    final entries = _chatMediaEntries();
    if (entries.isEmpty) return;

    var offset = 0;
    for (final item in _messages) {
      if (item.id == message.id) {
        final safeIndex = initialAttachmentIndex.clamp(
          0,
          item.attachments.isEmpty ? 0 : item.attachments.length - 1,
        );
        _showChatMediaDialog(
          context,
          entries,
          initialIndex: offset + safeIndex,
        );
        return;
      }
      offset += item.attachments.length;
    }

    _showChatMediaDialog(context, entries, initialIndex: 0);
  }

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

  bool _isImageFile(XFile file) {
    final mime = lookupMimeType(file.path) ?? '';
    if (mime.startsWith('image/')) return true;
    final path = file.path.toLowerCase();
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp');
  }

  bool _isVideoFile(XFile file) {
    final mime = lookupMimeType(file.path) ?? '';
    if (mime.startsWith('video/')) return true;
    final path = file.path.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.avi') ||
        path.endsWith('.mkv') ||
        path.endsWith('.webm');
  }

  Future<void> _pickAndSendMultipleMedia() async {
    if (_isSending || _editingMessageId != null) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultipleMedia(
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
        limit: 10,
      );
      if (picked.isEmpty || !mounted) return;
      _addDraftAttachments(picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _ensureMicPermission() async {
    // Use the record plugin's native iOS permission (AVCaptureDevice audio).
    // permission_handler's microphone API is disabled unless PERMISSION_MICROPHONE
    // is set in ios/Podfile — using it alone never shows the system dialog.
    if (await _voiceRecorder.hasPermission(request: true)) {
      return true;
    }
    return false;
  }

  void _showMicPermissionDenied() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _chatText(
            context,
            'Allow microphone access in Settings to send voice messages.',
            ar: 'اسمح بالوصول إلى الميكروفون من الإعدادات لإرسال الرسائل الصوتية.',
            ku: 'لە ڕێکخستنەکان مۆڵەتی مایکرۆفۆن بدە بۆ ناردنی پەیامی دەنگی.',
          ),
        ),
        action: SnackBarAction(
          label: _chatText(
            context,
            'Settings',
            ar: 'الإعدادات',
            ku: 'ڕێکخستنەکان',
          ),
          onPressed: () {
            openAppSettings();
          },
        ),
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _takePhotoAndSend() async {
    if (_isSending || _editingMessageId != null || _isRecordingVoice) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      setState(() => _isSending = true);
      final ok = await _sendMediaGroup([picked]);
      if (!ok && mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _chatText(
                context,
                'Could not send photo.',
                ar: 'تعذر إرسال الصورة.',
                ku: 'نەتوانرا وێنە بنێردرێت.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isRecordingVoice) {
      await _stopAndSendVoiceRecording();
      return;
    }
    await _startVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    if (_isSending || _editingMessageId != null || _isRecordingVoice) return;
    if (!await _ensureMicPermission()) {
      _showMicPermissionDenied();
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = true;
        _voiceRecordPath = path;
        _voiceRecordDuration = Duration.zero;
      });
      _voiceRecordTimer?.cancel();
      _voiceRecordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecordingVoice) return;
        setState(() {
          _voiceRecordDuration += const Duration(seconds: 1);
        });
        if (_voiceRecordDuration.inSeconds >= 300) {
          unawaited(_stopAndSendVoiceRecording());
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _voiceRecordTimer?.cancel();
    try {
      await _voiceRecorder.stop();
    } catch (e, st) { logNonFatal(e, st); }
    final path = _voiceRecordPath;
    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _voiceRecordPath = null;
      _voiceRecordDuration = Duration.zero;
    });
    if (path != null) {
      try {
        await File(path).delete();
      } catch (e, st) { logNonFatal(e, st); }
    }
  }

  Future<void> _stopAndSendVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _voiceRecordTimer?.cancel();
    String? effectivePath;
    try {
      effectivePath = await _voiceRecorder.stop();
    } catch (e, st) { logNonFatal(e, st); }
    effectivePath ??= _voiceRecordPath;
    final recordedFor = _voiceRecordDuration;
    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _voiceRecordPath = null;
      _voiceRecordDuration = Duration.zero;
    });
    if (effectivePath == null || effectivePath.isEmpty) return;
    if (recordedFor.inSeconds < 1) {
      try {
        await File(effectivePath).delete();
      } catch (e, st) { logNonFatal(e, st); }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _chatText(
              context,
              'Hold to record at least 1 second.',
              ar: 'سجّل لمدة ثانية واحدة على الأقل.',
              ku: 'لانیکەم ١ چرکە تۆمار بکە.',
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    await _sendVoiceMessage(XFile(effectivePath));
  }

  Future<void> _sendVoiceMessage(XFile file) async {
    if (_isSending) return;
    if (!await ensurePhoneVerifiedForAction(context)) return;
    setState(() => _isSending = true);
    final replyToMessageId = _replyingToMessage?.id;
    final startedAt = DateTime.now();
    final pendingMessage = _buildPendingAudioMessage(file, createdAt: startedAt);
    final restoreFile = XFile(file.path);
    setState(() {
      _messages.add(pendingMessage);
    });
    _scrollToBottom();
    OutgoingChatSendService.instance.startAudioSend(
      conversationId: widget.carId,
      audioFile: file,
      tempMessageId: pendingMessage.id,
      startedAt: startedAt,
      receiverId: widget.receiverId,
      replyToMessageId: replyToMessageId,
      restoreFile: restoreFile,
    );
  }

  Future<bool> _sendMediaGroup(List<XFile> files, {String? caption}) async {
    final validFiles = files
        .where((file) => _isImageFile(file) || _isVideoFile(file))
        .toList();
    if (validFiles.isEmpty) return false;

    final listingPreviewForMessage = _pendingInitialListingContext
        ? _listingPreview
        : null;
    final startedAt = DateTime.now();
    final replyToMessageId = _replyingToMessage?.id;
    final replyJson = _replyToPreviewJson(_replyingToMessage);
    final pendingMessage = _buildPendingMediaGroupMessage(
      validFiles,
      listingPreview: listingPreviewForMessage,
      createdAt: startedAt,
    );
    final restoreFiles = List<XFile>.from(validFiles);
    setState(() {
      _messages.add(pendingMessage);
    });
    _scrollToBottom();

    OutgoingChatSendService.instance.startMediaGroupSend(
      conversationId: widget.carId,
      files: validFiles,
      tempMessageId: pendingMessage.id,
      startedAt: startedAt,
      receiverId: widget.receiverId,
      carId: widget.carId,
      caption: caption,
      replyToMessageId: replyToMessageId,
      replyToPreviewJson: replyJson,
      listingPreview: listingPreviewForMessage,
      restoreFiles: restoreFiles,
      restoreCaption: caption,
    );
    return true;
  }

  bool _canEditMessage(ChatMessage message, bool isMe) {
    return isMe && !message.isDeleted;
  }

  bool _canDeleteMessage(ChatMessage message, bool isMe) {
    return isMe && !message.isDeleted;
  }

  void _recallPendingMessageToComposer(ChatMessage message) {
    if (!message.isPending || !mounted) return;
    OutgoingChatSendService.instance.discardInFlightMedia(message.id);
    _discardedOutgoingIds.add(message.id);
    final caption = _isAttachmentPlaceholder(message.content)
        ? ''
        : message.content.trim();
    final files = <XFile>[];
    const maxCount = 10;
    for (final a in message.attachments) {
      if (!a.isLocal || a.url.isEmpty || files.length >= maxCount) continue;
      files.add(XFile(a.url));
    }
    ChatMessage? replyTarget;
    final replyId = message.replyToMessageId;
    if (replyId != null && replyId.isNotEmpty) {
      replyTarget = _messageById(replyId);
    }
    setState(() {
      _removeMessage(message.id);
      _editingMessageId = null;
      _editingKeepAttachments.clear();
      _replyingToMessage = replyTarget;
      if (message.listingPreview != null &&
          message.listingPreview!.isNotEmpty) {
        _listingPreview = Map<String, dynamic>.from(message.listingPreview!);
        _pendingInitialListingContext = true;
      } else {
        _pendingInitialListingContext = false;
      }
      _draftAttachments
        ..clear()
        ..addAll(files);
      _isSending = false;
    });
    _messageController.text = caption;
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: _messageController.text.length),
    );
    _focusComposer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollComposerToTop();
    });
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    if (message.isPending) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            _chatText(
              context,
              'Discard message?',
              ar: 'تجاهل الرسالة؟',
              ku: 'پەیامەکە لاببرێت؟',
            ),
          ),
          content: Text(
            _chatText(
              context,
              'This message has not finished sending yet. Remove it from the chat?',
              ar: 'لم تنتهِ هذه الرسالة من الإرسال بعد. هل تريد إزالتها من الدردشة؟',
              ku: 'ئەم پەیامە هێشتا تەواو نەبووە لە ناردن. دەتەوێت لە چاتەکە لاببریت؟',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context)?.cancelAction ?? 'Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                _chatText(context, 'Remove', ar: 'إزالة', ku: 'لابردن'),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      OutgoingChatSendService.instance.discardInFlightMedia(message.id);
      setState(() {
        _discardedOutgoingIds.add(message.id);
        _removeMessage(message.id);
        if (_editingMessageId == message.id) {
          _editingMessageId = null;
          _editingKeepAttachments.clear();
        }
        if (_replyingToMessage?.id == message.id) {
          _replyingToMessage = null;
        }
        _isSending = false;
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _chatText(
            context,
            'Delete message?',
            ar: 'حذف الرسالة؟',
            ku: 'پەیامەکە بسڕدرێتەوە؟',
          ),
        ),
        content: Text(
          _chatText(
            context,
            'This message will be removed from the conversation.',
            ar: 'سيتم حذف هذه الرسالة من المحادثة.',
            ku: 'ئەم پەیامە لە گفتوگۆکە دەسڕدرێتەوە.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)?.cancelAction ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)?.deleteAction ?? 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final response = await ApiService.deleteChatMessage(
        messageId: message.id,
      );
      final msg = response['message'];
      if (msg is Map<String, dynamic>) {
        setState(() {
          final deleted = ChatMessage.fromJson(msg);
          _addMessageIfMissing(deleted);
          if (_replyingToMessage?.id == deleted.id) {
            _replyingToMessage = deleted;
          }
          if (_editingMessageId == deleted.id) {
            _editingMessageId = null;
            _messageController.clear();
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showMessageActions(ChatMessage message, bool isMe) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!message.isDeleted)
              ListTile(
                leading: const Icon(Icons.reply),
                title: Text(
                  _chatText(context, 'Reply', ar: 'رد', ku: 'وەڵام'),
                ),
                onTap: () => Navigator.pop(context, 'reply'),
              ),
            if (_canEditMessage(message, isMe))
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(
                  AppLocalizations.of(context)?.editAction ?? 'Edit',
                ),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (_canDeleteMessage(message, isMe))
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(
                  AppLocalizations.of(context)?.deleteAction ?? 'Delete',
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'reply') {
      _startReplyToMessage(message);
    } else if (action == 'edit') {
      if (message.isPending) {
        _recallPendingMessageToComposer(message);
      } else {
        _startEditingMessage(message);
      }
    } else if (action == 'delete') {
      await _deleteMessage(message);
    }
  }

  Widget _buildReplyPreviewCard(
    BuildContext context,
    ChatReplyPreview reply, {
    required bool isMe,
    bool dense = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final baseColor = isMe
        ? Colors.white.withValues(alpha: 0.14)
        : _homeListingCardBackgroundFill(context);
    final borderColor = isMe
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.12);
    final inner = Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: dense ? 6 : 8),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: borderColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            (reply.senderName ?? 'Message').trim().isNotEmpty
                ? reply.senderName!.trim()
                : 'Message',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            reply.content.trim().isEmpty ? 'Message' : reply.content.trim(),
            maxLines: dense ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return inner;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: inner,
      ),
    );
  }

  Widget _buildComposerActionBanner(BuildContext context) {
    final editingMessage = _editingMessageId == null
        ? null
        : _messageById(_editingMessageId!);
    if (_replyingToMessage == null && editingMessage == null) {
      return const SizedBox.shrink();
    }

    final isEditMode = editingMessage != null;
    final previewMessage = editingMessage ?? _replyingToMessage!;
    final replyPreview = ChatReplyPreview(
      id: previewMessage.id,
      senderId: previewMessage.senderId,
      senderName: previewMessage.senderName,
      content: _replyPreviewLabel(previewMessage),
      messageType: previewMessage.messageType,
      isDeleted: previewMessage.isDeleted,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditMode
                      ? _chatText(
                          context,
                          'Editing message',
                          ar: 'تعديل الرسالة',
                          ku: 'دەستکاریکردنی پەیام',
                        )
                      : _chatText(
                          context,
                          'Replying to message',
                          ar: 'الرد على الرسالة',
                          ku: 'وەڵامدانەوەی پەیام',
                        ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                _buildReplyPreviewCard(
                  context,
                  replyPreview,
                  isMe: false,
                  dense: true,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _cancelComposerAction,
            icon: const Icon(Icons.close),
            tooltip: AppLocalizations.of(context)?.cancelAction ?? 'Cancel',
          ),
        ],
      ),
    );
  }

  Widget _buildDraftAttachmentsPreview(BuildContext context) {
    if (_draftAttachments.isEmpty) return const SizedBox.shrink();

    Widget tileFor(XFile file, int index) {
      final isVideo = _isVideoFile(file);
      final path = file.path;
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 72,
              height: 72,
              color: Theme.of(context).cardColor,
              child: isVideo
                  ? const Center(child: Icon(Icons.videocam, size: 28))
                  : Image.file(
                      File(path),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                    ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: InkWell(
              onTap: () => _removeDraftAttachmentAt(index),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _draftAttachments.length,
          separatorBuilder: (context, index) => const SizedBox(width: 10),
          itemBuilder: (context, index) =>
              tileFor(_draftAttachments[index], index),
        ),
      ),
    );
  }

  Widget _buildEditingAttachmentsPreview(BuildContext context) {
    if (_editingMessageId == null || _editingKeepAttachments.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget tileFor(ChatAttachment attachment, int index) {
      final isVideo = attachment.type.toLowerCase() == 'video';
      final resolved = buildMediaUrl(attachment.url);
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 72,
              height: 72,
              color: Theme.of(context).cardColor,
              child: isVideo
                  ? const Center(child: Icon(Icons.videocam, size: 28))
                  : Image.network(
                      resolved,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                    ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (index >= 0 && index < _editingKeepAttachments.length) {
                    _editingKeepAttachments.removeAt(index);
                  }
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _editingKeepAttachments.length,
          separatorBuilder: (context, index) => const SizedBox(width: 10),
          itemBuilder: (context, index) =>
              tileFor(_editingKeepAttachments[index], index),
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    final content = _messageController.text.trim();
    final editingMessageId = _editingMessageId;
    final replyingToMessageId = _replyingToMessage?.id;
    if (editingMessageId == null && content.isEmpty && !_hasDraftAttachments) {
      return;
    }
    if (!await ensurePhoneVerifiedForAction(context)) return;
    setState(() => _isSending = true);
    _messageController.clear();

    var deferIsSendingReset = false;
    try {
      if (editingMessageId != null) {
        if (content.isEmpty && _editingKeepAttachments.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message cannot be empty.'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _isSending = false);
          _messageController.text = content;
          return;
        }
        final response = await ApiService.editChatMessage(
          messageId: editingMessageId,
          content: content,
          attachments: _editingKeepAttachments
              .map((a) => <String, dynamic>{'type': a.type, 'url': a.url})
              .toList(),
        );
        final msg = response['message'];
        if (msg is Map<String, dynamic> && mounted) {
          setState(() {
            _addMessageIfMissing(ChatMessage.fromJson(msg));
            _editingMessageId = null;
            _editingKeepAttachments.clear();
          });
        }
        return;
      }

      if (_hasDraftAttachments) {
        final files = List<XFile>.from(_draftAttachments);
        final caption = content.isEmpty ? null : content;
        setState(() {
          _draftAttachments.clear();
        });
        final ok = await _sendMediaGroup(files, caption: caption);
        if (!ok) {
          if (!mounted) return;
          setState(() {
            _draftAttachments.addAll(files);
          });
          if (caption != null && caption.isNotEmpty) {
            _messageController.text = caption;
            _messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: _messageController.text.length),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollComposerToTop();
            });
          }
          return;
        }
        deferIsSendingReset = true;
        return;
      }

      final listingPreviewForMessage = _pendingInitialListingContext
          ? _listingPreview
          : null;
      if (WebSocketService.isConnected) {
        WebSocketService.sendChatMessage(
          widget.carId,
          content,
          receiverId: widget.receiverId,
          listingPreview: listingPreviewForMessage,
          replyToMessageId: replyingToMessageId,
        );
        if (mounted) {
          setState(() {
            _pendingInitialListingContext = false;
            _replyingToMessage = null;
          });
        } else {
          _pendingInitialListingContext = false;
          _replyingToMessage = null;
        }
        return;
      }

      OutgoingChatSendService.instance.startTextMessageSend(
        conversationId: widget.carId,
        content: content,
        receiverId: widget.receiverId,
        listingPreview: listingPreviewForMessage,
        replyToMessageId: replyingToMessageId,
      );
      deferIsSendingReset = true;
      return;
    } catch (e) {
      if (!mounted) return;
      _messageController.text = content;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollComposerToTop();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!deferIsSendingReset) {
        if (mounted) {
          setState(() => _isSending = false);
        } else {
          _isSending = false;
        }
      }
    }
  }

}
