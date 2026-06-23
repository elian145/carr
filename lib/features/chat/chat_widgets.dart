part of 'chat_pages.dart';

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

String _formatSocketErrorForUser(String err) {
  final text = err.toLowerCase();
  if (text.contains('failed host lookup') ||
      text.contains('no address associated with hostname') ||
      text.contains('network is unreachable')) {
    return 'Cannot reach CarNet server. Check Wi‑Fi or mobile data, then open '
        'https://carr-5hrm.onrender.com in Safari.';
  }
  return err;
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

Widget buildChatReplyPreviewCard(
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

Widget buildChatComposerActionBanner(
  BuildContext context, {
  required bool isEditMode,
  required ChatReplyPreview replyPreview,
  required VoidCallback onCancel,
}) {
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
              buildChatReplyPreviewCard(
                context,
                replyPreview,
                isMe: false,
                dense: true,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onCancel,
          icon: const Icon(Icons.close),
          tooltip: AppLocalizations.of(context)?.cancelAction ?? 'Cancel',
        ),
      ],
    ),
  );
}

Widget _buildChatComposerAttachmentTile({
  required BuildContext context,
  required Widget child,
  required VoidCallback onRemove,
}) {
  return Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 72,
          height: 72,
          color: Theme.of(context).cardColor,
          child: child,
        ),
      ),
      Positioned(
        top: 4,
        right: 4,
        child: InkWell(
          onTap: onRemove,
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

Widget _buildChatHorizontalAttachmentScroller({
  required int itemCount,
  required Widget Function(BuildContext context, int index) itemBuilder,
}) {
  if (itemCount == 0) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: itemBuilder,
      ),
    ),
  );
}

Widget buildChatDraftAttachmentsPreview(
  BuildContext context, {
  required List<XFile> files,
  required bool Function(XFile file) isVideoFile,
  required void Function(int index) onRemoveAt,
}) {
  return _buildChatHorizontalAttachmentScroller(
    itemCount: files.length,
    itemBuilder: (context, index) {
      final file = files[index];
      final isVideo = isVideoFile(file);
      final path = file.path;
      return _buildChatComposerAttachmentTile(
        context: context,
        onRemove: () => onRemoveAt(index),
        child: isVideo
            ? const Center(child: Icon(Icons.videocam, size: 28))
            : Image.file(
                File(path),
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
      );
    },
  );
}

Widget buildChatEditingAttachmentsPreview(
  BuildContext context, {
  required List<ChatAttachment> attachments,
  required void Function(int index) onRemoveAt,
}) {
  return _buildChatHorizontalAttachmentScroller(
    itemCount: attachments.length,
    itemBuilder: (context, index) {
      final attachment = attachments[index];
      final isVideo = attachment.type.toLowerCase() == 'video';
      final resolved = buildMediaUrl(attachment.url);
      return _buildChatComposerAttachmentTile(
        context: context,
        onRemove: () => onRemoveAt(index),
        child: isVideo
            ? const Center(child: Icon(Icons.videocam, size: 28))
            : Image.network(
                resolved,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
      );
    },
  );
}

