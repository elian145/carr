import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
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
  final diff = now.difference(dateTime);
  final loc = AppLocalizations.of(context)!;
  String formatNum(int n) => _digitsLocalized(context, n.toString());
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
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image,
                color: Colors.white,
                size: 64,
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
                    if (ts.isNotEmpty) dt = DateTime.parse(ts);
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

  const ChatConversationPage({super.key, required this.carId, this.receiverId});

  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage>
    with WidgetsBindingObserver {
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _messageSub;
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
  bool _isTyping = false;
  String? _otherUserTypingName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _setupWebSocketListeners();
    _setupTypingListener();
    _loadHistory();
    _joinChat();
    _startPolling();
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
      });
      if (_messages.length > hadMessages) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToBottom();
        });
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
    final exists = _messages.any((m) => m.id == message.id);
    if (exists) return;
    _messages.add(message);
  }

  void _setupWebSocketListeners() {
    _messageSub?.cancel();
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
      });
      _scrollToBottom();
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
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
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

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_isSending) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      setState(() => _isSending = true);
      final response = await ApiService.sendChatImage(
        conversationId: widget.carId,
        imageFile: picked,
        receiverId: widget.receiverId,
      );
      final msg = response['message'];
      if (msg is Map<String, dynamic> && mounted) {
        setState(() {
          _addMessageIfMissing(ChatMessage.fromJson(msg));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    setState(() => _isSending = true);
    _messageController.clear();

    try {
      if (WebSocketService.isConnected) {
        WebSocketService.sendChatMessage(
          widget.carId,
          content,
          receiverId: widget.receiverId,
        );
        return;
      }

      final response = await ApiService.sendChatMessageByConversation(
        conversationId: widget.carId,
        content: content,
        receiverId: widget.receiverId,
      );
      final msg = response['message'];
      if (msg is Map<String, dynamic> && mounted) {
        setState(() {
          _addMessageIfMissing(ChatMessage.fromJson(msg));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      _messageController.text = content;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
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
    if (_isTyping) {
      WebSocketService.sendTypingStop(widget.carId);
    }
    _messageSub?.cancel();
    _errorSub?.cancel();
    _typingSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.chatTitle),
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

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Text(
                                  message.senderName ?? AppLocalizations.of(context)!.unknownSender,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (message.messageType == 'image' && message.attachmentUrl != null && message.attachmentUrl!.isNotEmpty) ...[
                                GestureDetector(
                                  onTap: () => _showFullImage(context, message.attachmentUrl!),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
                                      child: Image.network(
                                        message.attachmentUrl!,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, progress) {
                                          if (progress == null) return child;
                                          return SizedBox(
                                            width: 150,
                                            height: 150,
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                value: progress.expectedTotalBytes != null
                                                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                                    : null,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          );
                                        },
                                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
                                      ),
                                    ),
                                  ),
                                ),
                                if (message.content.isNotEmpty && message.content != '[Image]')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      message.content,
                                      style: TextStyle(color: isMe ? Colors.white : null),
                                    ),
                                  ),
                              ] else
                                Text(
                                  message.content,
                                  style: TextStyle(color: isMe ? Colors.white : null),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                _relativeTime(context, message.createdAt),
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
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
            child: Row(
              children: [
                IconButton(
                  onPressed: _isSending ? null : _pickAndSendImage,
                  icon: const Icon(Icons.image),
                  tooltip: 'Send image',
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.typeMessage,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    onChanged: _onTextChanged,
                    onSubmitted: (_) => _sendMessage(),
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
