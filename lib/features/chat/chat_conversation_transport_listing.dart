part of 'chat_pages.dart';

mixin _ChatConversationTransportListing on _ChatConversationTransportSync {
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
              type: _chatIsVideoFile(file) ? 'video' : 'image',
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
