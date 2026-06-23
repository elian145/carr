part of 'chat_pages.dart';

mixin _ChatConversationMessageActions on _ChatConversationMedia {
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
}
