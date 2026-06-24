part of 'chat_pages.dart';

mixin _ChatConversationPageBuildBodyComposer on _ChatConversationPageBuildBodyMessages {
  List<Widget> _buildChatComposerSection(BuildContext context) {
    return [
                if (_otherUserTypingName != null &&
                    _otherUserTypingName!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_otherUserTypingName!} is typing...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(
                      top: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildComposerActionBanner(context),
                      if (_isRecordingVoice)
                        _buildVoiceRecordingBanner(context),
                      if (_editingMessageId != null &&
                          _editingKeepAttachments.isNotEmpty)
                        _buildEditingAttachmentsPreview(context)
                      else if (!_pendingInitialListingContext &&
                          _draftAttachments.isNotEmpty)
                        _buildDraftAttachmentsPreview(context),
                      Row(
                        children: [
                          IconButton(
                            onPressed: (_isSending ||
                                    _editingMessageId != null ||
                                    _isRecordingVoice)
                                ? null
                                : _pickAndSendMultipleMedia,
                            icon: const Icon(Icons.attach_file),
                            tooltip: _chatText(
                              context,
                              'Send attachment',
                              ar: 'إرسال مرفق',
                              ku: 'ناردنی پاشکۆ',
                            ),
                          ),
                          IconButton(
                            onPressed: (_isSending ||
                                    _editingMessageId != null ||
                                    _isRecordingVoice)
                                ? null
                                : _takePhotoAndSend,
                            icon: const Icon(Icons.camera_alt_outlined),
                            tooltip: _chatText(
                              context,
                              'Take photo',
                              ar: 'التقاط صورة',
                              ku: 'وێنە بگرە',
                            ),
                          ),
                          IconButton(
                            onPressed: (_isSending || _editingMessageId != null)
                                ? null
                                : _toggleVoiceRecording,
                            icon: Icon(
                              _isRecordingVoice ? Icons.stop_circle : Icons.mic,
                              color: _isRecordingVoice ? Colors.red : null,
                            ),
                            tooltip: _chatText(
                              context,
                              _isRecordingVoice
                                  ? 'Stop and send voice message'
                                  : 'Record voice message',
                              ar: _isRecordingVoice
                                  ? 'إيقاف وإرسال الرسالة الصوتية'
                                  : 'تسجيل رسالة صوتية',
                              ku: _isRecordingVoice
                                  ? 'وەستان و ناردنی پەیامی دەنگی'
                                  : 'تۆمارکردنی پەیامی دەنگی',
                            ),
                          ),
                          Expanded(
                            child:
                                _pendingInitialListingContext &&
                                    _listingPreview != null
                                ? Container(
                                    constraints: const BoxConstraints(
                                      maxHeight: 240,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      color: Theme.of(
                                        context,
                                      ).scaffoldBackgroundColor,
                                    ),
                                    child: Scrollbar(
                                      controller: _composerScrollController,
                                      child: SingleChildScrollView(
                                        controller: _composerScrollController,
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildListingCard(
                                              context,
                                              _listingPreview!,
                                            ),
                                            if (_draftAttachments
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 10),
                                              _buildDraftAttachmentsPreview(
                                                context,
                                              ),
                                            ],
                                            const SizedBox(height: 10),
                                            TextField(
                                              controller: _messageController,
                                              focusNode: _messageFocusNode,
                                              decoration: InputDecoration(
                                                hintText: AppLocalizations.of(
                                                  context,
                                                )!.typeMessage,
                                                isDense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                    color:
                                                        _kComposerOutlineOrange,
                                                    width: 2,
                                                  ),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                    color:
                                                        _kComposerOutlineOrange,
                                                    width: 2,
                                                  ),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                    color:
                                                        _kComposerOutlineOrange,
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                              keyboardType:
                                                  TextInputType.multiline,
                                              textInputAction:
                                                  TextInputAction.newline,
                                              maxLines: null,
                                              onChanged: _onTextChanged,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                : TextField(
                                    controller: _messageController,
                                    focusNode: _messageFocusNode,
                                    decoration: InputDecoration(
                                      hintText: AppLocalizations.of(
                                        context,
                                      )!.typeMessage,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: _kComposerOutlineOrange,
                                          width: 2,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: _kComposerOutlineOrange,
                                          width: 2,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: _kComposerOutlineOrange,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    maxLines: null,
                                    onChanged: _onTextChanged,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Semantics(
                            button: true,
                            label: trLegacyText(
                              context,
                              'Send message',
                              ar: 'إرسال رسالة',
                              ku: 'ناردنی پەیام',
                            ),
                            child: IconButton(
                              onPressed: (_isSending || _isRecordingVoice)
                                  ? null
                                  : _sendMessage,
                              icon: const Icon(Icons.send),
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    ];
  }
}
