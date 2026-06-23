part of 'chat_pages.dart';

mixin _ChatConversationComposer on _ChatConversationMessageActions {
  Widget _buildReplyPreviewCard(
    BuildContext context,
    ChatReplyPreview reply, {
    required bool isMe,
    bool dense = false,
    VoidCallback? onTap,
  }) {
    return buildChatReplyPreviewCard(
      context,
      reply,
      isMe: isMe,
      dense: dense,
      onTap: onTap,
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

    return buildChatComposerActionBanner(
      context,
      isEditMode: isEditMode,
      replyPreview: replyPreview,
      onCancel: _cancelComposerAction,
    );
  }

  Widget _buildDraftAttachmentsPreview(BuildContext context) {
    return buildChatDraftAttachmentsPreview(
      context,
      files: _draftAttachments,
      isVideoFile: _chatIsVideoFile,
      onRemoveAt: _removeDraftAttachmentAt,
    );
  }

  Widget _buildEditingAttachmentsPreview(BuildContext context) {
    if (_editingMessageId == null) return const SizedBox.shrink();

    return buildChatEditingAttachmentsPreview(
      context,
      attachments: _editingKeepAttachments,
      onRemoveAt: (index) {
        setState(() {
          if (index >= 0 && index < _editingKeepAttachments.length) {
            _editingKeepAttachments.removeAt(index);
          }
        });
      },
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
