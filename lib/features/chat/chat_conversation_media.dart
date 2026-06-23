part of 'chat_pages.dart';

mixin _ChatConversationMedia on _ChatConversationTransport {

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
        .where((file) => _chatIsImageFile(file) || _chatIsVideoFile(file))
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
}
