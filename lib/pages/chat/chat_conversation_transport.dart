part of '../chat_pages.dart';

// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

extension ChatConversationTransport on _ChatConversationPageState {
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
      _maybePromptPhoneVerification(context, err);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_formatSocketErrorForUser(context, err)),
          backgroundColor: Colors.red,
        ),
      );
    });
  }

  Future<bool> _ensureVerifiedBeforeChatSend() async {
    return ensurePhoneVerifiedForAction(context);
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
        perPage: _ChatConversationPageState._perPage,
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
    } catch (_) {
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
    } catch (_) {}
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
      } catch (_) {}
    }
  }

  Future<void> _stopAndSendVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _voiceRecordTimer?.cancel();
    String? effectivePath;
    try {
      effectivePath = await _voiceRecorder.stop();
    } catch (_) {}
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
      } catch (_) {}
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
    if (!await _ensureVerifiedBeforeChatSend()) return;
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

}
