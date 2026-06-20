part of '../chat_pages.dart';

class _ChatVoiceBubble extends StatefulWidget {
  final ChatMessage message;
  final Color iconColor;
  final Color textColor;
  final Color progressColor;

  const _ChatVoiceBubble({
    required this.message,
    required this.iconColor,
    required this.textColor,
    required this.progressColor,
  });

  @override
  State<_ChatVoiceBubble> createState() => _ChatVoiceBubbleState();
}

class _ChatVoiceBubbleState extends State<_ChatVoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _positionSub = _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
    });
  }

  String _audioSource() {
    if (widget.message.attachments.isNotEmpty) {
      final attachment = widget.message.attachments.first;
      if (attachment.isLocal) return attachment.url;
      return buildMediaUrl(attachment.url);
    }
    final url = (widget.message.attachmentUrl ?? '').trim();
    if (url.isEmpty) return '';
    if (url.startsWith('/') || !url.startsWith('http')) return url;
    return buildMediaUrl(url);
  }

  Future<void> _togglePlay() async {
    if (widget.message.isPending) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    final source = _audioSource();
    if (source.isEmpty) return;
    final attachment = widget.message.attachments.isNotEmpty
        ? widget.message.attachments.first
        : null;
    if (attachment != null && attachment.isLocal) {
      await _player.play(DeviceFileSource(source));
      return;
    }
    await _player.play(UrlSource(source));
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayDuration = _duration.inMilliseconds > 0
        ? _duration
        : (_position.inMilliseconds > 0 ? _position : Duration.zero);
    final progress = displayDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / displayDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          IconButton(
            onPressed: widget.message.isPending ? null : _togglePlay,
            icon: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
            ),
            color: widget.iconColor,
            iconSize: 36,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: widget.message.isPending ? null : progress,
                    color: widget.progressColor,
                    backgroundColor: widget.progressColor.withValues(alpha: 0.25),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.message.isPending
                      ? _chatText(
                          context,
                          'Sending...',
                          ar: 'جارٍ الإرسال...',
                          ku: 'لە ناردندایە...',
                        )
                      : _formatVoiceDuration(
                          _playing || _position.inMilliseconds > 0
                              ? _position
                              : displayDuration,
                        ),
                  style: TextStyle(color: widget.textColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chat list row inks when chat UI is light ([ChatUiThemeController]).
const Color _kChatListRowInkLight = Color(0xFF000000);
const Color _kChatListRowInkDarkPrimary = Color(0xFFF5F5F5);
const Color _kChatListRowInkDarkMuted = Color(0xFFCFCFCF);

bool _isIgnorableSocketError(String err) {
  final text = err.toLowerCase();
  return text.contains('was not upgraded to websocket') ||
      text.contains('transport=websocket');
}

String _formatSocketErrorForUser(BuildContext context, String err) {
  final lower = err.toLowerCase();
  if (lower.contains('verify your phone') ||
      lower.contains('phone_verification_required')) {
    return phoneVerificationRequiredMessage(AppLocalizations.of(context));
  }
  if (lower.contains('failed host lookup') ||
      lower.contains('no address associated with hostname') ||
      lower.contains('network is unreachable')) {
    return 'Cannot reach CarNet server. Check Wi‑Fi or mobile data, then open '
        'https://carr-5hrm.onrender.com in Safari.';
  }
  return err;
}

String _formatOutgoingChatError(BuildContext context, String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return AppLocalizations.of(context)?.errorTitle ?? 'Error';
  }
  if (_isPhoneVerificationSocketError(raw)) {
    return phoneVerificationRequiredMessage(AppLocalizations.of(context));
  }
  return raw.replaceFirst('Exception: ', '').trim();
}

bool _isPhoneVerificationSocketError(String err) {
  final lower = err.toLowerCase();
  return lower.startsWith('phone_verification_required|') ||
      lower.contains('verify your phone') ||
      lower.contains('phone_verification_required');
}

void _maybePromptPhoneVerification(BuildContext context, String err) {
  if (!_isPhoneVerificationSocketError(err)) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    ensurePhoneVerifiedForAction(context);
  });
}

String _resolveAttachmentUrl(ChatAttachment attachment) {
  if (attachment.isLocal) return attachment.url;
  return buildMediaUrl(attachment.url);
}

class _ChatMediaEntry {
  final ChatAttachment attachment;
  final String senderName;

  const _ChatMediaEntry({required this.attachment, required this.senderName});
}

void _showChatMediaDialog(
  BuildContext context,
  List<_ChatMediaEntry> entries, {
  int initialIndex = 0,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          _ChatMediaGroupViewer(entries: entries, initialIndex: initialIndex),
    ),
  );
}

class _ChatMediaGroupViewer extends StatefulWidget {
  final List<_ChatMediaEntry> entries;
  final int initialIndex;

  const _ChatMediaGroupViewer({required this.entries, this.initialIndex = 0});

  @override
  State<_ChatMediaGroupViewer> createState() => _ChatMediaGroupViewerState();
}

class _ChatMediaGroupViewerState extends State<_ChatMediaGroupViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.entries.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.entries.length,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: (context, index) {
                  final entry = widget.entries[index];
                  final attachment = entry.attachment;
                  if (attachment.type == 'video') {
                    return GalleryEmbeddedVideoPlayer(
                      videoUrl: _resolveAttachmentUrl(attachment),
                      isActive: index == _currentIndex,
                    );
                  }
                  return Center(
                    child: InteractiveViewer(
                      child: attachment.isLocal
                          ? Image.file(
                              File(attachment.url),
                              fit: BoxFit.contain,
                            )
                          : Image.network(
                              _resolveAttachmentUrl(attachment),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                    Icons.broken_image,
                                    color: Colors.white,
                                    size: 64,
                                  ),
                            ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 12,
              left: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    '${_currentIndex + 1}/${widget.entries.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 72,
              right: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    widget.entries[_currentIndex].senderName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

