import 'package:flutter/material.dart';
import 'dart:async';
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

class _ChatListPageState extends State<ChatListPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _carIdController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _currentCarId;
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
  }

  void _setupWebSocketListeners() {
    _messageSub?.cancel();
    _notificationSub?.cancel();
    _errorSub?.cancel();

    _messageSub = WebSocketService.messages.listen((message) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage.fromJson(message));
      });
      _scrollToBottom();
    });

    _notificationSub = WebSocketService.notifications.listen((notification) {
      if (!mounted) return;
      final msg = (notification['message'] ?? '').toString();
      if (msg.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.blue,
        ),
      );
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

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty || _currentCarId == null) return;

    WebSocketService.sendChatMessage(
      _currentCarId!,
      _messageController.text.trim(),
    );

    _messageController.clear();
    // Tracking disabled or not available in this build
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _notificationSub?.cancel();
    _errorSub?.cancel();
    _carIdController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.chatTitle),
        actions: [const _ThemeToggleAction()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _carIdController,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.carIdChatRoom,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) {
                      final id = _carIdController.text.trim();
                      if (id.isEmpty) return;
                      setState(() => _currentCarId = id);
                      WebSocketService.joinChat(id);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    final id = _carIdController.text.trim();
                    if (id.isEmpty) return;
                    setState(() => _currentCarId = id);
                    WebSocketService.joinChat(id);
                  },
                  icon: const Icon(Icons.login),
                  tooltip: AppLocalizations.of(context)!.joinLabel,
                ),
              ],
            ),
          ),
          // Chat messages
          Expanded(
            child: _messages.isEmpty
                ? Center(child: Text(_noMessagesText(context)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
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
                              Text(
                                message.content,
                                style: TextStyle(
                                  color: isMe ? Colors.white : null,
                                ),
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
          // Message input
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
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendMessage,
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

class ChatConversationPage extends StatefulWidget {
  final String carId;
  final String? receiverId;

  const ChatConversationPage({super.key, required this.carId, this.receiverId});

  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<String>? _errorSub;
  bool _isSending = false;
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
    _loadHistory();
    _joinChat();
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
      final rows = await ApiService.getChatMessagesByConversation(widget.carId);
      if (!mounted) return;
      final loaded = rows.map(ChatMessage.fromJson).toList();
      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      setState(() {
        _messages
          ..clear()
          ..addAll(loaded);
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
    _messageSub?.cancel();
    _errorSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    WebSocketService.leaveChat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.chatTitle),
        actions: [const _ThemeToggleAction()],
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
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
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
                              Text(
                                message.content,
                                style: TextStyle(
                                  color: isMe ? Colors.white : null,
                                ),
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
          // Message input
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
