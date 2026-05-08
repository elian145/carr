import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../l10n/app_localizations.dart';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/outgoing_chat_send_service.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/media/media_url.dart';
import '../theme_provider.dart';
import '../widgets/theme_toggle_widget.dart';

const Color _kComposerOutlineOrange = Color(0xFFFF7A00);

/// Brand orange (matches home [buildGlobalCarCard]); explicit color avoids
/// [Theme.primaryColor] matching surfaces inside chat bubbles in dark mode.
const Color _kChatListingCardAccentOrange = Color(0xFFFF6B00);

/// Peer bubble / preview fill: same look as dark mode (frosted on dark shell; solid blend on light shell).
Color _homeListingCardBackgroundFill(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return Colors.white.withValues(alpha: 0.10);
  }
  return AppThemes.listingCardFillGridOnLightShell();
}

String _digitsLocalized(BuildContext context, String input) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar' || code == 'ku') {
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var out = input;
    for (int i = 0; i < western.length; i++) {
      out = out.replaceAll(western[i], eastern[i]);
    }
    return out;
  }
  return input;
}

String _relativeTime(BuildContext context, DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime.toLocal());
  final loc = AppLocalizations.of(context)!;
  String formatNum(int n) => _digitsLocalized(context, n.toString());
  if (diff.isNegative) {
    return loc.justNow;
  }
  if (diff.inDays > 0) {
    return loc.timeDaysAgo(formatNum(diff.inDays));
  } else if (diff.inHours > 0) {
    return loc.timeHoursAgo(formatNum(diff.inHours));
  } else if (diff.inMinutes > 0) {
    return loc.timeMinutesAgo(formatNum(diff.inMinutes));
  }
  return loc.justNow;
}

/// Best-effort timestamp string from API (snake_case / camelCase / conversation fallbacks).
String _rawChatListTimestamp(
  Map<String, dynamic> last,
  Map<String, dynamic> conversation,
) {
  String pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }

  var s = pick(last, [
    'created_at',
    'createdAt',
    'updated_at',
    'updatedAt',
    'timestamp',
    'time',
    'sent_at',
    'sentAt',
  ]);
  if (s.isNotEmpty) return s;
  s = pick(conversation, [
    'updated_at',
    'updatedAt',
    'last_activity_at',
    'lastActivityAt',
  ]);
  return s;
}

String _noMessagesText(BuildContext context) {
  return AppLocalizations.of(context)!.noMessagesYet;
}

/// Chat list row inks when chat UI is light ([ChatUiThemeController]).
const Color _kChatListRowInkLight = Color(0xFF000000);
const Color _kChatListRowInkDarkPrimary = Color(0xFFF5F5F5);
const Color _kChatListRowInkDarkMuted = Color(0xFFCFCFCF);

void _showFullImage(BuildContext context, String url) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.broken_image,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _showVideoPlayerDialog(BuildContext context, String url) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: _ChatVideoPlayer(source: url, autoplay: true),
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
      ),
    ),
  );
}

bool _isIgnorableSocketError(String err) {
  final text = err.toLowerCase();
  return text.contains('was not upgraded to websocket') ||
      text.contains('transport=websocket');
}

class _ChatVideoPlayer extends StatefulWidget {
  final String source;
  final bool autoplay;
  final bool isLocal;

  const _ChatVideoPlayer({
    required this.source,
    this.autoplay = false,
    this.isLocal = false,
  });

  @override
  State<_ChatVideoPlayer> createState() => _ChatVideoPlayerState();
}

class _ChatVideoPlayerState extends State<_ChatVideoPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    final controller = widget.isLocal
        ? VideoPlayerController.file(File(widget.source))
        : VideoPlayerController.networkUrl(Uri.parse(widget.source));
    _controller = controller;
    _initFuture = controller.initialize().then((_) {
      controller.setLooping(false);
      if (widget.autoplay) {
        controller.play();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!controller.value.isInitialized) {
          return const SizedBox(
            height: 180,
            child: Center(child: Icon(Icons.broken_image)),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio == 0
                  ? 16 / 9
                  : controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(controller),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        if (controller.value.isPlaying) {
                          controller.pause();
                        } else {
                          controller.play();
                        }
                      });
                    },
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      size: 54,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ],
        );
      },
    );
  }
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
                    return Center(
                      child: _ChatVideoPlayer(
                        source: _resolveAttachmentUrl(attachment),
                        isLocal: attachment.isLocal,
                        autoplay: true,
                      ),
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
              left: 16,
              right: 16,
              bottom: 16,
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

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage>
    with WidgetsBindingObserver {
  final List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChats();
    _setupWebSocketListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadChats();
    }
  }

  void _setupWebSocketListeners() {
    _notificationSub?.cancel();
    _errorSub?.cancel();

    _notificationSub = WebSocketService.notifications.listen((notification) {
      if (!mounted) return;
      final type = (notification['notification_type'] ?? '').toString();
      if (type == 'message') {
        _loadChats();
      }
    });

    _errorSub = WebSocketService.errors.listen((err) {
      if (!mounted) return;
      if (err.trim().isEmpty) return;
      if (_isIgnorableSocketError(err)) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
    });
  }

  Future<void> _loadChats() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getChats();
      data.sort((a, b) {
        final aTime =
            (a['last_message'] is Map ? a['last_message']['created_at'] : null)
                ?.toString() ??
            '';
        final bTime =
            (b['last_message'] is Map ? b['last_message']['created_at'] : null)
                ?.toString() ??
            '';
        return bTime.compareTo(aTime);
      });
      if (!mounted) return;
      setState(() {
        _chats
          ..clear()
          ..addAll(data);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.failedToLoadListings ??
                'Failed to load chats',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      } else {
        _loading = false;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useLightInk = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.chatTitle),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.pushNamed(context, '/notifications'),
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
            body: RefreshIndicator(
              onRefresh: _loadChats,
              child: _loading && _chats.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _chats.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(child: Text(_noMessagesText(context))),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _chats.length,
                      itemBuilder: (context, index) {
                        final c = _chats[index];
                        final other = c['other_user'] is Map
                            ? Map<String, dynamic>.from(
                                (c['other_user'] as Map)
                                    .cast<String, dynamic>(),
                              )
                            : <String, dynamic>{};
                        final last = c['last_message'] is Map
                            ? Map<String, dynamic>.from(
                                (c['last_message'] as Map)
                                    .cast<String, dynamic>(),
                              )
                            : <String, dynamic>{};
                        final carId =
                            (c['car_id'] ??
                                    c['conversation_id'] ??
                                    last['car_id'] ??
                                    '')
                                .toString();
                        final receiverId = (other['id'] ?? '').toString();
                        final name = (other['name'] ?? '').toString().trim();
                        final carTitle = (c['car_title'] ?? '')
                            .toString()
                            .trim();
                        final preview = (last['content'] ?? '')
                            .toString()
                            .trim();
                        final ts = _rawChatListTimestamp(last, c);
                        DateTime? dt;
                        try {
                          if (ts.isNotEmpty) dt = parseApiDateTime(ts);
                        } catch (_) {}
                        final unread = (c['unread_count'] is num)
                            ? (c['unread_count'] as num).toInt()
                            : 0;
                        final theme = Theme.of(context);
                        final cs = theme.colorScheme;
                        final nameStyle = TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: useLightInk
                              ? _kChatListRowInkLight
                              : _kChatListRowInkDarkPrimary,
                        );
                        final previewStyle = TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          color: useLightInk
                              ? _kChatListRowInkLight
                              : _kChatListRowInkDarkMuted,
                        );
                        final timeStyle = TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          color: useLightInk
                              ? _kChatListRowInkLight
                              : _kChatListRowInkDarkMuted,
                        );
                        final trailingTime = dt == null
                            ? null
                            : Text(
                                _relativeTime(context, dt),
                                textAlign: TextAlign.right,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: timeStyle,
                              );
                        final trailingBadge = unread > 0
                            ? CircleAvatar(
                                radius: 11,
                                backgroundColor: cs.primary,
                                child: Text(
                                  unread.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              )
                            : null;
                        final hasTrailing =
                            trailingTime != null || trailingBadge != null;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: carId.isEmpty
                                ? null
                                : () async {
                                    await Navigator.pushNamed(
                                      context,
                                      '/chat/conversation',
                                      arguments: {
                                        'carId': carId,
                                        if (receiverId.isNotEmpty)
                                          'receiverId': receiverId,
                                        if (name.isNotEmpty)
                                          'receiverName': name,
                                      },
                                    );
                                    if (mounted) _loadChats();
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: cs.primary.withAlpha(30),
                                    child: Icon(
                                      Icons.directions_car,
                                      color: cs.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name.isEmpty
                                              ? AppLocalizations.of(
                                                  context,
                                                )!.unknownSender
                                              : name,
                                          style: nameStyle,
                                        ),
                                        if (carTitle.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            carTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: cs.primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 2),
                                        Text(
                                          preview.isEmpty ? '...' : preview,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: previewStyle,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (hasTrailing) ...[
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 78,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (trailingBadge != null)
                                            trailingBadge,
                                          if (trailingBadge != null &&
                                              trailingTime != null)
                                            const SizedBox(height: 6),
                                          if (trailingTime != null)
                                            trailingTime,
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class ChatConversationPage extends StatefulWidget {
  final String carId;
  final String? receiverId;
  final String? receiverName;
  final String? initialDraft;
  final Map<String, dynamic>? initialListingPreview;

  const ChatConversationPage({
    super.key,
    required this.carId,
    this.receiverId,
    this.receiverName,
    this.initialDraft,
    this.initialListingPreview,
  });

  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage>
    with WidgetsBindingObserver {
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _composerScrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _messageUpdateSub;
  StreamSubscription<Map<String, dynamic>>? _messageDeleteSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  StreamSubscription<OutgoingChatSendEvent>? _outgoingSendSub;
  bool _isSending = false;
  bool _loadingHistory = false;
  bool _loadingOlderMessages = false;
  bool _hasMoreMessages = false;
  int _currentPage = 1;
  static const int _perPage = 50;
  Timer? _pollTimer;
  Timer? _typingDebounce;
  Timer? _scrollRetryTimer;
  bool _isTyping = false;
  String? _otherUserTypingName;
  String? _receiverName;
  Map<String, dynamic>? _listingPreview;
  bool _pendingInitialListingContext = false;

  /// Temp ids of outgoing messages the user removed or recalled before the send finished.
  final Set<String> _discardedOutgoingIds = <String>{};
  final List<XFile> _draftAttachments = <XFile>[];
  final List<ChatAttachment> _editingKeepAttachments = <ChatAttachment>[];
  ChatMessage? _replyingToMessage;
  String? _editingMessageId;
  String? _highlightMessageId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _receiverName = widget.receiverName?.trim();
    _listingPreview = widget.initialListingPreview == null
        ? null
        : Map<String, dynamic>.from(widget.initialListingPreview!);
    _pendingInitialListingContext = _listingPreview != null;
    final initialDraft = widget.initialDraft?.trim() ?? '';
    if (initialDraft.isNotEmpty) {
      _messageController.text = initialDraft;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    }
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _setupWebSocketListeners();
    _setupTypingListener();
    _outgoingSendSub = OutgoingChatSendService.instance.events.listen(
      _onOutgoingChatSendEvent,
    );
    _loadHistory();
    _joinChat();
    _startPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollComposerToTop();
    });
  }

  void _setupTypingListener() {
    _typingSub?.cancel();
    _typingSub = WebSocketService.typingEvents.listen((data) {
      if (!mounted) return;
      final isTyping = data['typing'] == true;
      final userName = (data['user_name'] ?? '').toString().trim();
      setState(() => _otherUserTypingName = isTyping ? userName : null);
    });
  }

  void _onTextChanged(String _) {
    if (!_isTyping) {
      _isTyping = true;
      WebSocketService.sendTypingStart(widget.carId);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _isTyping = false;
      WebSocketService.sendTypingStop(widget.carId);
    });
  }

  void _scrollComposerToTop() {
    if (!_composerScrollController.hasClients) return;
    _composerScrollController.jumpTo(0);
  }

  void _onOutgoingChatSendEvent(OutgoingChatSendEvent e) {
    if (e.conversationId != widget.carId || !mounted) return;

    void finishSending() {
      setState(() => _isSending = false);
    }

    switch (e.kind) {
      case OutgoingChatSendKind.mediaGroup:
        if (e.success && e.tempMessageId != null && e.messageJson != null) {
          setState(() {
            if (_discardedOutgoingIds.remove(e.tempMessageId!)) {
              // User removed or recalled before the upload finished.
            } else {
              _replaceMessage(
                e.tempMessageId!,
                ChatMessage.fromJson(e.messageJson!),
              );
            }
            _replyingToMessage = null;
            _pendingInitialListingContext = false;
          });
          _scrollToBottom();
        } else if (!e.success && e.tempMessageId != null) {
          setState(() {
            _removeMessage(e.tempMessageId!);
            final files = e.restoreFiles;
            if (files != null && files.isNotEmpty) {
              _draftAttachments.addAll(files);
            }
          });
          final cap = e.restoreCaption;
          if (cap != null && cap.isNotEmpty) {
            _messageController.text = cap;
            _messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: _messageController.text.length),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollComposerToTop();
            });
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.error ?? 'Send failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
        finishSending();
        break;
      case OutgoingChatSendKind.textMessage:
        if (e.success && e.messageJson != null) {
          setState(() {
            _addMessageIfMissing(ChatMessage.fromJson(e.messageJson!));
            _pendingInitialListingContext = false;
            _replyingToMessage = null;
          });
          _scrollToBottom();
        } else {
          final t = e.restoredPlainText ?? '';
          if (t.isNotEmpty) {
            _messageController.text = t;
            _messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: _messageController.text.length),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollComposerToTop();
            });
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.error ?? 'Send failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
        finishSending();
        break;
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels <=
            _scrollController.position.minScrollExtent + 80 &&
        _hasMoreMessages &&
        !_loadingOlderMessages) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlderMessages || !_hasMoreMessages) return;
    setState(() => _loadingOlderMessages = true);
    try {
      final nextPage = _currentPage + 1;
      final result = await ApiService.getChatMessagesByConversation(
        widget.carId,
        page: nextPage,
        perPage: _perPage,
      );
      if (!mounted) return;
      final rows = (result['messages'] as List<Map<String, dynamic>>?) ?? [];
      final loaded = rows.map(ChatMessage.fromJson).toList();
      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final prevOffset = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;

      setState(() {
        for (final m in loaded) {
          _addMessageIfMissing(m);
        }
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _currentPage = nextPage;
        _hasMoreMessages = result['has_more'] == true;
        _refreshReceiverNameFromMessages();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final newOffset = _scrollController.position.maxScrollExtent;
        final diff = newOffset - prevOffset;
        if (diff > 0) {
          _scrollController.jumpTo(_scrollController.offset + diff);
        }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (mounted) _pollNewMessages();
    });
  }

  Future<void> _pollNewMessages() async {
    try {
      final result = await ApiService.getChatMessagesByConversation(
        widget.carId,
        page: 1,
        perPage: _perPage,
      );
      if (!mounted) return;
      final rows = (result['messages'] as List<Map<String, dynamic>>?) ?? [];
      final loaded = rows.map(ChatMessage.fromJson).toList();
      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final hadMessages = _messages.length;
      setState(() {
        for (final m in loaded) {
          _addMessageIfMissing(m);
        }
        _mergeInFlightMediaPending();
        if (OutgoingChatSendService.instance
            .inFlightMediaForConversation(widget.carId)
            .isNotEmpty) {
          _isSending = true;
        }
        _refreshReceiverNameFromMessages();
      });
      if (_messages.length > hadMessages) {
        _scrollToBottom();
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _pollNewMessages();
    }
  }

  void _addMessageIfMissing(ChatMessage message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      _messages[index] = message;
      return;
    }
    _messages.add(message);
  }

  void _replaceMessage(String oldId, ChatMessage message) {
    final index = _messages.indexWhere((m) => m.id == oldId);
    if (index == -1) {
      _addMessageIfMissing(message);
      return;
    }
    _messages[index] = message;
  }

  void _removeMessage(String id) {
    _messages.removeWhere((m) => m.id == id);
  }

  bool get _hasDraftAttachments => _draftAttachments.isNotEmpty;

  void _addDraftAttachments(List<XFile> files) {
    final valid = files
        .where((f) => _isImageFile(f) || _isVideoFile(f))
        .toList();
    if (valid.isEmpty) return;
    const maxCount = 10;
    final remaining = maxCount - _draftAttachments.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can attach up to 10 files.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final toAdd = valid.take(remaining).toList();
    setState(() {
      _draftAttachments.addAll(toAdd);
      _pendingInitialListingContext = _pendingInitialListingContext;
    });
    if (valid.length > toAdd.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the first 10 attachments were added.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    _focusComposer();
  }

  void _removeDraftAttachmentAt(int index) {
    if (index < 0 || index >= _draftAttachments.length) return;
    setState(() {
      _draftAttachments.removeAt(index);
    });
  }

  void _clearDraftAttachments() {
    if (_draftAttachments.isEmpty) return;
    setState(() {
      _draftAttachments.clear();
    });
  }

  ChatMessage? _messageById(String id) {
    for (final message in _messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _startReplyToMessage(ChatMessage message) {
    setState(() {
      _replyingToMessage = message;
      _editingMessageId = null;
    });
    _focusComposer();
  }

  void _startEditingMessage(ChatMessage message) {
    final isPlaceholder = _isAttachmentPlaceholder(message.content);
    _editingKeepAttachments
      ..clear()
      ..addAll(_attachmentsForEdit(message));
    _clearDraftAttachments();
    setState(() {
      _editingMessageId = message.id;
      _replyingToMessage = null;
      _messageController.text = isPlaceholder ? '' : message.content;
      _pendingInitialListingContext = false;
    });
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: _messageController.text.length),
    );
    _focusComposer();
  }

  void _cancelComposerAction() {
    if (_replyingToMessage == null && _editingMessageId == null) return;
    setState(() {
      _replyingToMessage = null;
      _editingMessageId = null;
    });
    _editingKeepAttachments.clear();
  }

  List<ChatAttachment> _attachmentsForEdit(ChatMessage message) {
    if (message.attachments.isNotEmpty) return message.attachments;
    final url = (message.attachmentUrl ?? '').trim();
    final typ = message.messageType.trim().toLowerCase();
    if (url.isNotEmpty && (typ == 'image' || typ == 'video')) {
      return [ChatAttachment(type: typ, url: url)];
    }
    return const <ChatAttachment>[];
  }

  void _focusComposer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageFocusNode.requestFocus();
    });
  }

  String _replyPreviewLabel(ChatMessage message) {
    if (message.isDeleted) return 'This message was deleted';
    if (message.listingPreview != null) return 'Listing';
    if (message.attachments.isNotEmpty) {
      final hasVideo = message.attachments.any((item) => item.type == 'video');
      if (message.attachments.length > 1) {
        return hasVideo ? 'Media group' : 'Photos';
      }
      return hasVideo ? 'Video' : 'Photo';
    }
    return message.content.trim().isEmpty ? 'Message' : message.content.trim();
  }

  String _temporaryMessageId() {
    return 'temp-${DateTime.now().microsecondsSinceEpoch}';
  }

  String _mediaGroupPlaceholder(int count) {
    return '[$count attachments]';
  }

  bool _isAttachmentPlaceholder(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    if (normalized == '[image]' || normalized == '[video]') return true;
    return RegExp(r'^\[\d+\s+attachments?\]$').hasMatch(normalized);
  }

  void _refreshReceiverNameFromMessages() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final myId = authService.userId ?? '';
    for (final message in _messages.reversed) {
      if (message.senderId == myId) continue;
      final candidate = (message.senderName ?? '').trim();
      if (candidate.isNotEmpty) {
        _receiverName = candidate;
        return;
      }
    }
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
              type: _isVideoFile(file) ? 'video' : 'image',
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
        _refreshReceiverNameFromMessages();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
    });
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
        perPage: _perPage,
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
        _refreshReceiverNameFromMessages();
      });
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

  Future<void> _pickAndSendImages() async {
    if (_isSending || _editingMessageId != null) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
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

  Future<void> _pickAndSendVideos() async {
    if (_isSending || _editingMessageId != null) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultipleMedia(limit: 10);
      if (picked.isEmpty || !mounted) return;
      final videos = picked.where(_isVideoFile).toList();
      if (videos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select one or more videos.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (videos.length != picked.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only video files were added to this group.'),
          ),
        );
      }
      _addDraftAttachments(videos);
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

  Future<bool> _sendMediaGroup(List<XFile> files, {String? caption}) async {
    final validFiles = files
        .where((file) => _isImageFile(file) || _isVideoFile(file))
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
          title: const Text('Discard message?'),
          content: const Text(
            'This message has not finished sending yet. Remove it from the chat?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
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
        title: const Text('Delete message?'),
        content: const Text(
          'This message will be removed from the conversation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
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
                title: const Text('Reply'),
                onTap: () => Navigator.pop(context, 'reply'),
              ),
            if (_canEditMessage(message, isMe))
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (_canDeleteMessage(message, isMe))
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
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
        ? Colors.white.withOpacity(0.14)
        : _homeListingCardBackgroundFill(context);
    final borderColor = isMe
        ? Colors.white.withOpacity(0.5)
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
                  isEditMode ? 'Editing message' : 'Replying to message',
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
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  Widget _buildDraftAttachmentsPreview(BuildContext context) {
    if (_draftAttachments.isEmpty) return const SizedBox.shrink();

    Widget tileFor(XFile file, int index) {
      final isVideo = _isVideoFile(file);
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

  Future<void> _showAttachmentPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Send photos/videos'),
              subtitle: const Text('Select multiple images and videos'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendMultipleMedia();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Send image'),
              subtitle: const Text('Select multiple images'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Send video'),
              subtitle: const Text('Select multiple videos'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendVideos();
              },
            ),
          ],
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _typingDebounce?.cancel();
    _scrollRetryTimer?.cancel();
    _highlightTimer?.cancel();
    if (_isTyping) {
      WebSocketService.sendTypingStop(widget.carId);
    }
    _messageSub?.cancel();
    _messageUpdateSub?.cancel();
    _messageDeleteSub?.cancel();
    _errorSub?.cancel();
    _typingSub?.cancel();
    _outgoingSendSub?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _composerScrollController.dispose();
    WebSocketService.leaveChat();
    super.dispose();
  }

  GlobalKey _keyForMessageId(String id) {
    return _messageKeys.putIfAbsent(id, () => GlobalKey());
  }

  void _flashHighlight(String messageId) {
    _highlightTimer?.cancel();
    if (!mounted) return;
    setState(() => _highlightMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _highlightMessageId = null);
    });
  }

  Future<void> _jumpToMessageId(String messageId) async {
    final targetId = messageId.trim();
    if (targetId.isEmpty) return;

    // If the message is older than what we’ve loaded, keep paginating up until we find it.
    var attempts = 0;
    while (_messages.indexWhere((m) => m.id == targetId) == -1 &&
        _hasMoreMessages &&
        !_loadingOlderMessages &&
        attempts < 8) {
      attempts += 1;
      await _loadOlderMessages();
    }

    final index = _messages.indexWhere((m) => m.id == targetId);
    if (index == -1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Original message is not loaded.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted || !_scrollController.hasClients) return;

    // Try to scroll precisely if the target is currently built.
    Future<bool> ensureVisibleIfBuilt() async {
      final key = _messageKeys[targetId];
      final ctx = key?.currentContext;
      if (ctx == null) return false;
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0.25,
      );
      _flashHighlight(targetId);
      return true;
    }

    if (await ensureVisibleIfBuilt()) return;

    // Otherwise, scroll close to the item using an estimate, then retry ensureVisible a few times.
    final maxScroll = _scrollController.position.maxScrollExtent;
    final denom = math.max(1, _messages.length - 1);
    final fraction = index / denom;
    final estimatedOffset = (maxScroll * fraction).clamp(0.0, maxScroll);
    await _scrollController.animateTo(
      estimatedOffset,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );

    for (var i = 0; i < 10; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted || !_scrollController.hasClients) return;
      if (await ensureVisibleIfBuilt()) return;
    }

    // Fallback: at least show a highlight state when the user scrolls manually.
    _flashHighlight(targetId);
  }

  void _showBlockDialog() {
    final receiverId = widget.receiverId;
    if (receiverId == null || receiverId.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block User'),
        content: const Text(
          'Blocked users cannot send you messages and their conversations will be hidden. You can unblock them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiService.blockUser(receiverId);
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('User blocked')));
                Navigator.pop(context);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      userErrorText(
                        context,
                        e,
                        fallback:
                            AppLocalizations.of(context)?.errorTitle ?? 'Error',
                      ),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    final receiverId = widget.receiverId;
    if (receiverId == null || receiverId.isEmpty) return;
    final reasonController = TextEditingController();
    final detailsController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report User'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'e.g. spam, harassment, scam',
                  border: OutlineInputBorder(),
                ),
                maxLength: 200,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: detailsController,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                  hintText: 'Provide additional details...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                maxLength: 2000,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a reason'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await ApiService.reportUser(
                  receiverId,
                  reason: reason,
                  details: detailsController.text.trim(),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report submitted. Thank you.')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      userErrorText(
                        context,
                        e,
                        fallback:
                            AppLocalizations.of(context)?.errorTitle ?? 'Error',
                      ),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text(
              'Submit Report',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  String _listingTitle(Map<String, dynamic> car) {
    final title = (car['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    final details = [
      (car['brand'] ?? '').toString().trim(),
      (car['model'] ?? '').toString().trim(),
      (car['trim'] ?? '').toString().trim(),
    ].where((value) => value.isNotEmpty).join(' ');
    if (details.isNotEmpty) return details;
    return '${car['brand'] ?? ''} ${car['model'] ?? ''} ${car['year'] ?? ''}'
        .trim();
  }

  String _listingPrice(Map<String, dynamic> car) {
    dynamic raw = car['price'];
    if (raw == null || raw.toString().trim().isEmpty) {
      raw = car['selling_price'] ?? car['amount'] ?? car['formatted_price'];
    }
    final price = (raw ?? '').toString().trim();
    final currency = (car['currency'] ?? car['currency_code'] ?? '')
        .toString()
        .trim();
    if (price.isEmpty) return '';
    return currency.isEmpty ? price : '$price $currency';
  }

  String _listingImageUrl(Map<String, dynamic> car) {
    final images = car['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first?.toString() ?? '';
      if (first.trim().isNotEmpty) return buildMediaUrl(first);
    }
    final primary = (car['image_url'] ?? '').toString().trim();
    if (primary.isNotEmpty) return buildMediaUrl(primary);
    return '';
  }

  Widget _buildListingCard(BuildContext context, Map<String, dynamic> car) {
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = _listingImageUrl(car);
    final title = _listingTitle(car);
    final price = _listingPrice(car);
    final location = (car['location'] ?? car['city'] ?? '').toString().trim();

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.pushNamed(
          context,
          '/car_detail',
            arguments: {'carId': listingPrimaryId(car)},
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).dividerColor
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.55),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imageUrl.isEmpty
                  ? Container(
                      width: double.infinity,
                      height: 140,
                      color: Colors.black12,
                      child: const Icon(Icons.directions_car),
                    )
                  : Image.network(
                      imageUrl,
                      width: double.infinity,
                      height: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: double.infinity,
                        height: 140,
                        color: Colors.black12,
                        child: const Icon(Icons.directions_car),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              title.isEmpty
                  ? (AppLocalizations.of(context)?.listingTitle ?? 'Listing')
                  : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            if (price.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                price,
                style: const TextStyle(
                  color: _kChatListingCardAccentOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (location.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMediaAttachmentThumbnail(
    BuildContext context,
    ChatAttachment attachment, {
    required double width,
    required double height,
    int? remainingCount,
    VoidCallback? onTap,
  }) {
    Widget child;
    if (attachment.type == 'video') {
      child = Container(
        width: width,
        height: height,
        color: Colors.black87,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.videocam, size: 42, color: Colors.white54),
            Container(
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 26,
              ),
            ),
          ],
        ),
      );
    } else if (attachment.isLocal) {
      child = Image.file(
        File(attachment.url),
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    } else {
      child = Image.network(
        _resolveAttachmentUrl(attachment),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: width,
          height: height,
          color: Colors.black12,
          child: const Icon(Icons.broken_image, size: 36),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (remainingCount != null && remainingCount > 0)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Text(
                  '+$remainingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGroupBubble(BuildContext context, ChatMessage message) {
    final attachments = message.attachments;
    final previewCount = attachments.length > 4 ? 4 : attachments.length;

    return GestureDetector(
      onTap: message.isPending ? null : () => _openChatMediaViewer(message),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: previewCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: previewCount == 1 ? 1 : 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: previewCount == 1 ? 1.15 : 1,
              ),
              itemBuilder: (context, index) {
                final remaining =
                    index == previewCount - 1 && attachments.length > 4
                    ? attachments.length - 4
                    : null;
                return _buildMediaAttachmentThumbnail(
                  context,
                  attachments[index],
                  width: double.infinity,
                  height: double.infinity,
                  remainingCount: remaining,
                  onTap: message.isPending
                      ? null
                      : () => _openChatMediaViewer(
                          message,
                          initialAttachmentIndex: index,
                        ),
                );
              },
            ),
          ),
          if (message.isPending)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(strokeWidth: 2),
                      SizedBox(height: 10),
                      Text(
                        'Sending...',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageStatusIndicator(
    BuildContext context,
    ChatMessage message,
  ) {
    final color = message.isRead ? Colors.lightBlueAccent : Colors.white70;
    if (message.isPending) {
      return const Icon(Icons.schedule, size: 14, color: Colors.white70);
    }
    return Icon(
      message.isRead ? Icons.done_all : Icons.check,
      size: 16,
      color: color,
    );
  }

  double _measureSingleLineTextWidth(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    final normalized = text.trim();
    if (normalized.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: normalized, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width;
  }

  double _estimateTextBubbleWidth(
    BuildContext context,
    ChatMessage message, {
    required bool isMe,
  }) {
    final maxBubbleWidth = math.min(
      MediaQuery.of(context).size.width * 0.58,
      280.0,
    );
    // Me: white on primary; peer: white on home listing-card style bubble.
    final bodyStyle = DefaultTextStyle.of(
      context,
    ).style.copyWith(color: Colors.white);
    const timeStyle = TextStyle(color: Colors.white70, fontSize: 12);
    final senderStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ) ??
        const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        );
    final reply = message.replyToMessage;

    final bodyWidth = message.content
        .split('\n')
        .map((line) => _measureSingleLineTextWidth(context, line, bodyStyle))
        .fold<double>(0, math.max);
    final timeWidth = _measureSingleLineTextWidth(
      context,
      _relativeTime(context, message.createdAt),
      timeStyle,
    );
    final senderWidth = !isMe
        ? _measureSingleLineTextWidth(
            context,
            message.senderName ?? AppLocalizations.of(context)!.unknownSender,
            senderStyle,
          )
        : 0.0;

    double replyBlockWidth = 0.0;
    if (reply != null) {
      final replyNameStyle =
          (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          );
      final replyBodyStyle =
          (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
            color: Colors.white70,
          );

      final replySenderText = (reply.senderName ?? 'Message').trim().isNotEmpty
          ? reply.senderName!.trim()
          : 'Message';
      final replyContentText = reply.content.trim().isEmpty
          ? 'Message'
          : reply.content.trim();

      final replySenderWidth = _measureSingleLineTextWidth(
        context,
        replySenderText,
        replyNameStyle,
      );
      final replyContentWidth = _measureSingleLineTextWidth(
        context,
        replyContentText,
        replyBodyStyle,
      );

      // Reply preview card adds padding + a left border inside the bubble.
      // (This is in addition to the bubble's own padding, which we add below.)
      const replyInnerPadding = 20.0; // horizontal 10 * 2
      const replyLeftBorder = 3.0;
      replyBlockWidth =
          math.max(replySenderWidth, replyContentWidth) +
          replyInnerPadding +
          replyLeftBorder;
    }

    final editedLabelWidth = (message.editedAt != null && !message.isDeleted)
        ? _measureSingleLineTextWidth(context, 'Edited', timeStyle) + 6
        : 0.0;
    final footerWidth = editedLabelWidth + timeWidth + (isMe ? 24 : 0);
    final contentWidth = math.max(
      math.max(bodyWidth, math.max(senderWidth, footerWidth)),
      replyBlockWidth,
    );
    return math.min(maxBubbleWidth, contentWidth + 32);
  }

  @override
  Widget build(BuildContext context) {
    final conversationTitle = (_receiverName ?? '').trim().isNotEmpty
        ? _receiverName!.trim()
        : AppLocalizations.of(context)!.chatTitle;
    return Scaffold(
            appBar: AppBar(
              title: Text(conversationTitle),
              actions: [
                if (widget.receiverId != null && widget.receiverId!.isNotEmpty)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'block') _showBlockDialog();
                      if (value == 'report') _showReportDialog();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'block',
                        child: Text('Block User'),
                      ),
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('Report User'),
                      ),
                    ],
                  ),
              ],
            ),
            body: Column(
              children: [
                // Chat messages
                Expanded(
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
                            final isTextOnlyMessage =
                                message.attachments.isEmpty &&
                                message.listingPreview == null;
                            final bubbleMaxWidth =
                                message.attachments.isNotEmpty
                                ? 240.0
                                : message.listingPreview != null
                                ? 280.0
                                : math.min(
                                    MediaQuery.of(context).size.width * 0.58,
                                    280.0,
                                  );
                            final textBubbleWidth = isTextOnlyMessage
                                ? _estimateTextBubbleWidth(
                                    context,
                                    message,
                                    isMe: isMe,
                                  )
                                : null;

                            // Ensure each message has a stable key so we can jump to it from reply previews.
                            _keyForMessageId(message.id);
                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: GestureDetector(
                                onLongPress: message.isDeleted
                                    ? null
                                    : () => _showMessageActions(message, isMe),
                                child: Container(
                                  key: _messageKeys[message.id],
                                  constraints: BoxConstraints(
                                    minWidth: textBubbleWidth ?? 0,
                                    maxWidth: textBubbleWidth ?? bubbleMaxWidth,
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
                                    border: message.id == _highlightMessageId
                                        ? Border.all(
                                            color: Colors.amberAccent,
                                            width: 2,
                                          )
                                        : !isMe
                                        ? Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.12,
                                            ),
                                          )
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (!isMe)
                                        Text(
                                          message.senderName ??
                                              AppLocalizations.of(
                                                context,
                                              )!.unknownSender,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: bubbleOnStrong,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      if (message.replyToMessage != null)
                                        _buildReplyPreviewCard(
                                          context,
                                          message.replyToMessage!,
                                          isMe: true,
                                          onTap: () => _jumpToMessageId(
                                            message.replyToMessage!.id,
                                          ),
                                        ),
                                      if (message.attachments.isNotEmpty) ...[
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
                                      ] else if (message.listingPreview !=
                                          null) ...[
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
                                          message.content,
                                          style: TextStyle(
                                            color: bubbleOnStrong,
                                            fontStyle: message.isDeleted
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          if (message.editedAt != null &&
                                              !message.isDeleted)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              child: Text(
                                                'Edited',
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
                                          if (isMe) ...[
                                            const Spacer(),
                                            _buildMessageStatusIndicator(
                                              context,
                                              message,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
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
                      if (_editingMessageId != null &&
                          _editingKeepAttachments.isNotEmpty)
                        _buildEditingAttachmentsPreview(context)
                      else if (!_pendingInitialListingContext &&
                          _draftAttachments.isNotEmpty)
                        _buildDraftAttachmentsPreview(context),
                      Row(
                        children: [
                          IconButton(
                            onPressed: (_isSending || _editingMessageId != null)
                                ? null
                                : _showAttachmentPicker,
                            icon: const Icon(Icons.attach_file),
                            tooltip: 'Send attachment',
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
                          IconButton(
                            onPressed: _isSending ? null : _sendMessage,
                            icon: const Icon(Icons.send),
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final List<AppNotification> _notifications = [];
  StreamSubscription<Map<String, dynamic>>? _notificationSub;

  String _tr(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
  }

  void _setupWebSocketListeners() {
    _notificationSub?.cancel();
    _notificationSub = WebSocketService.notifications.listen((notification) {
      if (!mounted) return;
      setState(() {
        _notifications.insert(0, AppNotification.fromJson(notification));
      });
    });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr('Notifications', ar: 'الإشعارات', ku: 'ئاگادارکردنەوەکان'),
        ),
        actions: const [ThemeToggleWidget()],
      ),
      body: _notifications.isEmpty
          ? Center(
              child: Text(
                _tr(
                  'No notifications yet',
                  ar: 'لا توجد إشعارات بعد',
                  ku: 'هێشتا هیچ ئاگادارکردنەوەیەک نییە',
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notification = _notifications[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      _getNotificationIcon(notification.notificationType),
                      color: notification.isRead
                          ? Colors.grey
                          : Theme.of(context).primaryColor,
                    ),
                    title: Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: notification.isRead
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(notification.message),
                    trailing: Text(
                      _relativeTime(context, notification.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () {
                      // Mark as read could be handled server-side; avoid mutating final field
                    },
                  ),
                );
              },
            ),
    );
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'message':
        return Icons.message;
      case 'listing':
        return Icons.directions_car;
      case 'favorite':
        return Icons.favorite;
      default:
        return Icons.notifications;
    }
  }
}
