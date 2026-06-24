part of 'chat_pages.dart';

mixin _ChatConversationPageBuildBodyMessages on _ChatConversationPageLifecycle {
  Widget _buildChatMessageListArea(BuildContext context) {
    return Expanded(
                  child: _loadingHistory && _messages.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _messages.isEmpty
                      ? Center(child: Text(_noMessagesText(context)))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount:
                              _messages.length + (_hasMoreMessages ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_hasMoreMessages && index == 0) {
                              return _loadingOlderMessages
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink();
                            }
                            final msgIndex = _hasMoreMessages
                                ? index - 1
                                : index;
                            final message = _messages[msgIndex];
                            final authService = Provider.of<AuthService>(
                              context,
                              listen: false,
                            );
                            final isMe = message.senderId == authService.userId;
                            final colorScheme = Theme.of(context).colorScheme;
                            // Peer bubbles: same treatment as home [buildGlobalCarCard].
                            final peerBubbleFill =
                                _homeListingCardBackgroundFill(context);
                            final bubbleColor = isMe
                                ? colorScheme.primary
                                : peerBubbleFill;
                            final bubbleOnStrong = isMe
                                ? Colors.white
                                : Colors.white;
                            final bubbleOnMuted = isMe
                                ? Colors.white.withValues(alpha: 0.85)
                                : Colors.white70;
                            final bubbleMaxWidth =
                                message.attachments.isNotEmpty ||
                                    _isAudioMessage(message)
                                ? 240.0
                                : message.listingPreview != null
                                ? 280.0
                                : math.min(
                                    MediaQuery.of(context).size.width * 0.58,
                                    280.0,
                                  );
                            final shrinkWrapBubble =
                                message.attachments.isEmpty &&
                                message.listingPreview == null &&
                                !_isAudioMessage(message);
                            final maxInnerWidth =
                                bubbleMaxWidth - _kBubbleHorizontalPadding;
                            final isHighlighted =
                                message.id == _highlightMessageId;
                            final shrinkInnerWidth = shrinkWrapBubble
                                ? _shrinkWrapBubbleInnerWidth(
                                    context,
                                    message: message,
                                    maxInnerWidth: maxInnerWidth,
                                    isMe: isMe,
                                    isHighlighted: isHighlighted,
                                    bubbleOnStrong: bubbleOnStrong,
                                    bubbleOnMuted: bubbleOnMuted,
                                  )
                                : null;
                            // Ensure each message has a stable key so we can jump to it from reply previews.
                            _keyForMessageId(message.id);
                            final bubbleBody = Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.stretch
                                  : CrossAxisAlignment.start,
                              children: [
                                if (message.replyToMessage != null)
                                  _buildReplyPreviewCard(
                                    context,
                                    message.replyToMessage!,
                                    isMe: true,
                                    onTap: () => _jumpToMessageId(
                                      message.replyToMessage!.id,
                                    ),
                                  ),
                                if (_isAudioMessage(message)) ...[
                                  _buildVoiceMessageBubble(
                                    context,
                                    message,
                                    iconColor: bubbleOnStrong,
                                    textColor: bubbleOnStrong,
                                    progressColor: bubbleOnStrong,
                                  ),
                                ] else if (message.attachments.isNotEmpty) ...[
                                  _buildMediaGroupBubble(
                                    context,
                                    message,
                                  ),
                                  if (!_isAttachmentPlaceholder(
                                    message.content,
                                  ))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 6,
                                      ),
                                      child: Text(
                                        message.content,
                                        style: TextStyle(
                                          color: bubbleOnStrong,
                                        ),
                                      ),
                                    ),
                                ] else if (message.listingPreview != null) ...[
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 280,
                                    ),
                                    child: _buildListingCard(
                                      context,
                                      message.listingPreview!,
                                    ),
                                  ),
                                  if (message.content.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 8,
                                      ),
                                      child: Text(
                                        message.content,
                                        style: TextStyle(
                                          color: bubbleOnStrong,
                                        ),
                                      ),
                                    ),
                                ] else
                                  Text(
                                    _chatDisplayContent(context, message),
                                    style: TextStyle(
                                      color: bubbleOnStrong,
                                      fontStyle: message.isDeleted
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                if (isMe)
                                  Row(
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (message.editedAt != null &&
                                              !message.isDeleted)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              child: Text(
                                                _chatEditedLabel(context),
                                                style: TextStyle(
                                                  color: bubbleOnMuted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          Text(
                                            _relativeTime(
                                              context,
                                              message.createdAt,
                                            ),
                                            style: TextStyle(
                                              color: bubbleOnMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      _buildMessageStatusIndicator(
                                        context,
                                        message,
                                      ),
                                    ],
                                  )
                                else
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (message.editedAt != null &&
                                          !message.isDeleted)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: Text(
                                            _chatEditedLabel(context),
                                            style: TextStyle(
                                              color: bubbleOnMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        _relativeTime(
                                          context,
                                          message.createdAt,
                                        ),
                                        style: TextStyle(
                                          color: bubbleOnMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            );
                            final bubble = GestureDetector(
                              onLongPress: message.isDeleted
                                  ? null
                                  : () => _showMessageActions(message, isMe),
                              child: Container(
                                key: _messageKeys[message.id],
                                constraints: BoxConstraints(
                                  maxWidth: bubbleMaxWidth,
                                ),
                                margin: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: bubbleColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: isHighlighted
                                      ? Border.all(
                                          color: Colors.amberAccent,
                                          width: 2,
                                        )
                                      : !isMe
                                      ? Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.12,
                                          ),
                                          width: 1,
                                        )
                                      : null,
                                ),
                                child: shrinkInnerWidth != null
                                    ? SizedBox(
                                        width: shrinkInnerWidth,
                                        child: bubbleBody,
                                      )
                                    : bubbleBody,
                              ),
                            );
                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: bubble,
                            );
                          },
                        ),
                );
  }
}
