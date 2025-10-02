import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import '../theme_provider.dart';

String _digitsLocalized(BuildContext context, String input) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar' || code == 'ku') {
    const western = ['0','1','2','3','4','5','6','7','8','9'];
    const eastern = ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'];
    var out = input;
    for (int i = 0; i < western.length; i++) { out = out.replaceAll(western[i], eastern[i]); }
    return out;
  }
  return input;
}

String _relativeTime(BuildContext context, DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);
  final code = Localizations.localeOf(context).languageCode;
  String formatNum(int n) => _digitsLocalized(context, n.toString());
  if (diff.inDays > 0) {
    if (code == 'ar') return 'قبل ${formatNum(diff.inDays)} يوم';
    if (code == 'ku') return 'پێش ${formatNum(diff.inDays)} ڕۆژ';
    return '${diff.inDays}d ago';
  } else if (diff.inHours > 0) {
    if (code == 'ar') return 'قبل ${formatNum(diff.inHours)} ساعة';
    if (code == 'ku') return 'پێش ${formatNum(diff.inHours)} کاتژمێر';
    return '${diff.inHours}h ago';
  } else if (diff.inMinutes > 0) {
    if (code == 'ar') return 'قبل ${formatNum(diff.inMinutes)} دقيقة';
    if (code == 'ku') return 'پێش ${formatNum(diff.inMinutes)} خولەک';
    return '${diff.inMinutes}m ago';
  }
  if (code == 'ar') return 'الآن';
  if (code == 'ku') return 'ئێستا';
  return 'Just now';
}

 

String _noMessagesText(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'لا رسائل بعد. ابدأ محادثة!';
  if (code == 'ku') return 'هیچ نامەیەک نییە. گفتوگۆیەک دەست پێبکە!';
  return 'No messages yet. Start a conversation!';
}

class _ThemeToggleAction extends StatelessWidget {
  const _ThemeToggleAction({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
          tooltip: themeProvider.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
        );
      },
    );
  }
}

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  _ChatListPageState createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _currentCarId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
  }

  void _setupWebSocketListeners() {
    WebSocketService.onMessage = (message) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage.fromJson(message));
        });
        _scrollToBottom();
      }
    };

    WebSocketService.onNotification = (notification) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(notification['message']),
            backgroundColor: Colors.blue,
          ),
        );
      }
    };
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
                      final authService = Provider.of<AuthService>(context, listen: false);
                      final isMe = message.senderId == authService.userId;

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                  message.senderName ?? 'Unknown',
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
                top: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
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
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  const ChatConversationPage({
    super.key,
    required this.carId,
    this.receiverId,
  });

  @override
  _ChatConversationPageState createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
    _joinChat();
  }

  void _setupWebSocketListeners() {
    WebSocketService.onMessage = (message) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage.fromJson(message));
        });
        _scrollToBottom();
      }
    };
  }

  void _joinChat() {
    WebSocketService.joinChat(widget.carId);
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
    if (_messageController.text.trim().isEmpty) return;

    WebSocketService.sendChatMessage(
      widget.carId,
      _messageController.text.trim(),
      receiverId: widget.receiverId,
    );

    _messageController.clear();
  }

  @override
  void dispose() {
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
            child: _messages.isEmpty ? Center(child: Text(_noMessagesText(context)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final authService = Provider.of<AuthService>(context, listen: false);
                      final isMe = message.senderId == authService.userId;

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                  message.senderName ?? 'Unknown',
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
                top: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
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
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({Key? key}) : super(key: key);

  @override
  _NotificationsPageState createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final List<AppNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
  }

  void _setupWebSocketListeners() {
    WebSocketService.onNotification = (notification) {
      if (mounted) {
        setState(() {
          _notifications.insert(0, AppNotification.fromJson(notification));
        });
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.paymentHistoryTitle),
        actions: [const _ThemeToggleAction()],
      ),
      body: _notifications.isEmpty
          ? Center(
              child: Text(AppLocalizations.of(context)!.noCarsFound),
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
                      color: notification.isRead ? Colors.grey : Theme.of(context).primaryColor,
                    ),
                    title: Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(notification.message),
                    trailing: Text(
                      _formatTime(notification.createdAt),
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

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
