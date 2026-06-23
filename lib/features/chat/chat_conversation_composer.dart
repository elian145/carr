part of 'chat_pages.dart';

mixin _ChatConversationComposer on _ChatConversationMedia {
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
      final isVideo = _chatIsVideoFile(file);
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
