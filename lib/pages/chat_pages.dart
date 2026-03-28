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
import '../shared/media/media_url.dart';
import '../theme_provider.dart';

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

String _noMessagesText(BuildContext context) {
  return AppLocalizations.of(context)!.noMessagesYet;
}

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

class _ThemeToggleAction extends StatelessWidget {
  const _ThemeToggleAction({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return IconButton(
          icon: Icon(
            themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () {
            themeProvider.toggleTheme();
          },
          tooltip: themeProvider.isDarkMode
              ? loc.switchToLightMode
              : loc.switchToDarkMode,
        );
      },
    );
  }
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
      return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
    }
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
        }
        if (!controller.value.isInitialized) {
          return const SizedBox(height: 180, child: Center(child: Icon(Icons.broken_image)));
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

  const _ChatMediaEntry({
    required this.attachment,
    required this.senderName,
  });
}

void _showChatMediaDialog(
  BuildContext context,
  List<_ChatMediaEntry> entries, {
  int initialIndex = 0,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _ChatMediaGroupViewer(
        entries: entries,
        initialIndex: initialIndex,
      ),
    ),
  );
}

class _ChatMediaGroupViewer extends StatefulWidget {
  final List<_ChatMediaEntry> entries;
  final int initialIndex;

  const _ChatMediaGroupViewer({
    required this.entries,
    this.initialIndex = 0,
  });

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

class _ChatListPageState extends State<ChatListPage> with WidgetsBindingObserver {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Colors.red,
        ),
      );
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
          content: const Text('Failed to load chats'),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.chatTitle),
        actions: [const _ThemeToggleAction()],
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
                          (c['other_user'] as Map).cast<String, dynamic>(),
                        )
                      : <String, dynamic>{};
                  final last = c['last_message'] is Map
                      ? Map<String, dynamic>.from(
                          (c['last_message'] as Map).cast<String, dynamic>(),
                        )
                      : <String, dynamic>{};
                  final carId = (c['car_id'] ??
                          c['conversation_id'] ??
                          last['car_id'] ??
                          '')
                      .toString();
                  final receiverId = (other['id'] ?? '').toString();
                  final name = (other['name'] ?? '').toString().trim();
                  final carTitle = (c['car_title'] ?? '').toString().trim();
                  final preview = (last['content'] ?? '').toString().trim();
                  final ts = (last['created_at'] ?? '').toString().trim();
                  DateTime? dt;
                  try {
                    if (ts.isNotEmpty) dt = parseApiDateTime(ts);
                  } catch (_) {}
                  final unread = (c['unread_count'] is num)
                      ? (c['unread_count'] as num).toInt()
                      : 0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor.withAlpha(30),
                        child: Icon(
                          Icons.directions_car,
                          color: Theme.of(context).primaryColor,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        name.isEmpty
                            ? AppLocalizations.of(context)!.unknownSender
                            : name,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (carTitle.isNotEmpty)
                            Text(
                              carTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          Text(
                            preview.isEmpty ? '...' : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      trailing: unread > 0
                          ? CircleAvatar(
                              radius: 11,
                              backgroundColor: Theme.of(context).primaryColor,
                              child: Text(
                                unread.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          : (dt == null
                              ? null
                              : Text(
                                  _relativeTime(context, dt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                )),
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
                                  if (name.isNotEmpty) 'receiverName': name,
                                },
                              );
                              if (mounted) _loadChats();
                            },
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
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _messageUpdateSub;
  StreamSubscription<Map<String, dynamic>>? _messageDeleteSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
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
  ChatMessage? _replyingToMessage;
  String? _editingMessageId;

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
    setState(() {
      _editingMessageId = message.id;
      _replyingToMessage = null;
      _messageController.text = message.content;
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

  ChatMessage _buildPendingMediaGroupMessage(List<XFile> files) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final replyTo = _replyingToMessage;
    return ChatMessage(
      id: _temporaryMessageId(),
      senderId: authService.userId ?? '',
      receiverId: widget.receiverId ?? '',
      carId: widget.carId,
      replyToMessageId: replyTo?.id,
      replyToMessage: replyTo == null
          ? null
          : ChatReplyPreview(
              id: replyTo.id,
              senderId: replyTo.senderId,
              senderName: replyTo.senderName,
              content: _replyPreviewLabel(replyTo),
              messageType: replyTo.messageType,
              isDeleted: replyTo.isDeleted,
            ),
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
      isRead: true,
      createdAt: DateTime.now(),
      isPending: true,
    );
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
          _ChatMediaEntry(
            attachment: attachment,
            senderName: senderName,
          ),
        );
      }
    }
    return entries;
  }

  void _openChatMediaViewer(ChatMessage message, {int initialAttachmentIndex = 0}) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Colors.red,
        ),
      );
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
    if (_isSending) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (picked.isEmpty || !mounted) return;
      await _sendMediaGroup(picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
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
    if (_isSending) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultipleMedia(
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
        limit: 10,
      );
      if (picked.isEmpty || !mounted) return;
      await _sendMediaGroup(
        picked.where((file) => _isImageFile(file) || _isVideoFile(file)).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickAndSendVideos() async {
    if (_isSending) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultipleMedia(
        limit: 10,
      );
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
      await _sendMediaGroup(videos);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _sendMediaGroup(List<XFile> files) async {
    final validFiles = files
        .where((file) => _isImageFile(file) || _isVideoFile(file))
        .toList();
    if (validFiles.isEmpty || _isSending) return;

    final pendingMessage = _buildPendingMediaGroupMessage(validFiles);
    setState(() {
      _isSending = true;
      _messages.add(pendingMessage);
    });
    _scrollToBottom();

    try {
      final replyToMessageId = _replyingToMessage?.id;
      final response = await ApiService.sendChatMediaGroup(
        conversationId: widget.carId,
        files: validFiles,
        receiverId: widget.receiverId,
        replyToMessageId: replyToMessageId,
      );
      final msg = response['message'];
      if (msg is Map<String, dynamic> && mounted) {
        setState(() {
          _replaceMessage(pendingMessage.id, ChatMessage.fromJson(msg));
          _replyingToMessage = null;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _removeMessage(pendingMessage.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      } else {
        _isSending = false;
      }
    }
  }

  bool _canEditMessage(ChatMessage message, bool isMe) {
    return isMe &&
        !message.isDeleted &&
        message.messageType == 'text' &&
        message.attachments.isEmpty &&
        message.listingPreview == null;
  }

  bool _canDeleteMessage(ChatMessage message, bool isMe) {
    return isMe && !message.isDeleted;
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be removed from the conversation.'),
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
      final response = await ApiService.deleteChatMessage(messageId: message.id);
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
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
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
      _startEditingMessage(message);
    } else if (action == 'delete') {
      await _deleteMessage(message);
    }
  }

  Widget _buildReplyPreviewCard(
    BuildContext context,
    ChatReplyPreview reply, {
    required bool isMe,
    bool dense = false,
  }) {
    final theme = Theme.of(context);
    final baseColor = isMe
        ? Colors.white.withOpacity(0.14)
        : theme.dividerColor.withOpacity(0.25);
    final borderColor = isMe
        ? Colors.white.withOpacity(0.5)
        : theme.primaryColor.withOpacity(0.7);
    return Container(
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
              color: isMe ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            reply.content.trim().isEmpty ? 'Message' : reply.content.trim(),
            maxLines: dense ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isMe ? Colors.white70 : theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
    if (content.isEmpty) return;
    final editingMessageId = _editingMessageId;
    final replyingToMessageId = _replyingToMessage?.id;
    setState(() => _isSending = true);
    _messageController.clear();

    try {
      if (editingMessageId != null) {
        final response = await ApiService.editChatMessage(
          messageId: editingMessageId,
          content: content,
        );
        final msg = response['message'];
        if (msg is Map<String, dynamic> && mounted) {
          setState(() {
            _addMessageIfMissing(ChatMessage.fromJson(msg));
            _editingMessageId = null;
          });
        }
        return;
      }

      final listingPreviewForMessage =
          _pendingInitialListingContext ? _listingPreview : null;
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

      final response = await ApiService.sendChatMessageByConversation(
        conversationId: widget.carId,
        content: content,
        receiverId: widget.receiverId,
        listingPreview: listingPreviewForMessage,
        replyToMessageId: replyingToMessageId,
      );
      final msg = response['message'];
      if (msg is Map<String, dynamic> && mounted) {
        setState(() {
          _addMessageIfMissing(ChatMessage.fromJson(msg));
          _pendingInitialListingContext = false;
          _replyingToMessage = null;
        });
        _scrollToBottom();
      }
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
          content: Text(e.toString()),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      } else {
        _isSending = false;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _typingDebounce?.cancel();
    _scrollRetryTimer?.cancel();
    if (_isTyping) {
      WebSocketService.sendTypingStop(widget.carId);
    }
    _messageSub?.cancel();
    _messageUpdateSub?.cancel();
    _messageDeleteSub?.cancel();
    _errorSub?.cancel();
    _typingSub?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _composerScrollController.dispose();
    WebSocketService.leaveChat();
    super.dispose();
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User blocked')),
                );
                Navigator.pop(context);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
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
                  const SnackBar(content: Text('Please provide a reason'), backgroundColor: Colors.orange),
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
                  SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Submit Report', style: TextStyle(color: Colors.red)),
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
    final price = (car['price'] ?? '').toString().trim();
    final currency = (car['currency'] ?? '').toString().trim();
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
    final imageUrl = _listingImageUrl(car);
    final title = _listingTitle(car);
    final price = _listingPrice(car);
    final location =
        (car['location'] ?? car['city'] ?? '').toString().trim();

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.pushNamed(
          context,
          '/car_detail',
          arguments: {'carId': (car['id'] ?? widget.carId).toString()},
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
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
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (price.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                price,
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
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
                style: Theme.of(context).textTheme.bodySmall,
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
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 26),
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
        errorBuilder: (context, error, stackTrace) =>
            Container(
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
      onTap: message.isPending
          ? null
          : () => _openChatMediaViewer(message),
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
                final remaining = index == previewCount - 1 && attachments.length > 4
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

  Widget _buildMessageStatusIndicator(BuildContext context, ChatMessage message) {
    final color = message.isRead ? Colors.lightBlueAccent : Colors.white70;
    if (message.isPending) {
      return const Icon(
        Icons.schedule,
        size: 14,
        color: Colors.white70,
      );
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
    final bodyStyle = DefaultTextStyle.of(context).style.copyWith(
      color: isMe ? Colors.white : null,
    );
    final timeStyle = TextStyle(
      color: isMe ? Colors.white70 : Colors.grey,
      fontSize: 12,
    );
    final senderStyle = Theme.of(context).textTheme.bodySmall;

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

    final footerWidth = timeWidth + (isMe ? 24 : 0);
    final contentWidth = math.max(bodyWidth, math.max(senderWidth, footerWidth));
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
                const PopupMenuItem(value: 'block', child: Text('Block User')),
                const PopupMenuItem(value: 'report', child: Text('Report User')),
              ],
            ),
          const _ThemeToggleAction(),
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
                    itemCount: _messages.length + (_hasMoreMessages ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_hasMoreMessages && index == 0) {
                        return _loadingOlderMessages
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink();
                      }
                      final msgIndex = _hasMoreMessages ? index - 1 : index;
                      final message = _messages[msgIndex];
                      final authService = Provider.of<AuthService>(
                        context,
                        listen: false,
                      );
                      final isMe = message.senderId == authService.userId;
                      final isTextOnlyMessage =
                          message.attachments.isEmpty &&
                          message.listingPreview == null;
                      final bubbleMaxWidth = message.attachments.isNotEmpty
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

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: message.isPending
                              ? null
                              : () => _showMessageActions(message, isMe),
                          child: Container(
                          constraints: BoxConstraints(
                            minWidth: textBubbleWidth ?? 0,
                            maxWidth: textBubbleWidth ?? bubbleMaxWidth,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Theme.of(context).primaryColor
                                : Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Text(
                                  message.senderName ?? AppLocalizations.of(context)!.unknownSender,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (message.replyToMessage != null)
                                _buildReplyPreviewCard(
                                  context,
                                  message.replyToMessage!,
                                  isMe: isMe,
                                ),
                              if (message.attachments.isNotEmpty) ...[
                                _buildMediaGroupBubble(context, message),
                                if (!_isAttachmentPlaceholder(message.content))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      message.content,
                                      style: TextStyle(
                                        color: isMe ? Colors.white : null,
                                      ),
                                    ),
                                  ),
                              ] else if (message.listingPreview != null) ...[
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 280),
                                  child: _buildListingCard(
                                    context,
                                    message.listingPreview!,
                                  ),
                                ),
                                if (message.content.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      message.content,
                                      style: TextStyle(
                                        color: isMe ? Colors.white : null,
                                      ),
                                    ),
                                  ),
                              ] else
                                Text(
                                  message.content,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : null,
                                    fontStyle: message.isDeleted
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  if (message.editedAt != null && !message.isDeleted)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Text(
                                        'Edited',
                                        style: TextStyle(
                                          color: isMe ? Colors.white70 : Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    _relativeTime(context, message.createdAt),
                                    style: TextStyle(
                                      color: isMe ? Colors.white70 : Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const Spacer(),
                                    _buildMessageStatusIndicator(context, message),
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
          if (_otherUserTypingName != null && _otherUserTypingName!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                      child: _pendingInitialListingContext &&
                              _listingPreview != null
                          ? Container(
                              constraints: const BoxConstraints(maxHeight: 240),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                color: Theme.of(context).scaffoldBackgroundColor,
                              ),
                              child: Scrollbar(
                                controller: _composerScrollController,
                                child: SingleChildScrollView(
                                  controller: _composerScrollController,
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildListingCard(context, _listingPreview!),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _messageController,
                                        focusNode: _messageFocusNode,
                                        decoration: InputDecoration.collapsed(
                                          hintText: AppLocalizations.of(context)!
                                              .typeMessage,
                                        ),
                                        keyboardType: TextInputType.multiline,
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
                          : Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                color: Theme.of(context).scaffoldBackgroundColor,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: TextField(
                                controller: _messageController,
                                focusNode: _messageFocusNode,
                                decoration: InputDecoration(
                                  hintText:
                                      AppLocalizations.of(context)!.typeMessage,
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                maxLines: null,
                                onChanged: _onTextChanged,
                              ),
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
        title: Text(AppLocalizations.of(context)!.paymentHistoryTitle),
        actions: [const _ThemeToggleAction()],
      ),
      body: _notifications.isEmpty
          ? Center(child: Text(AppLocalizations.of(context)!.noCarsFound))
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
