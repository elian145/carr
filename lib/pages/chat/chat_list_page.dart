part of '../chat_pages.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_formatSocketErrorForUser(context, err)),
          backgroundColor: Colors.red,
        ),
      );
    });
  }

  Future<void> _enrichChatsFromCars(List<Map<String, dynamic>> chats) async {
    final tasks = <Future<void>>[];
    for (final chat in chats) {
      final carId = (chat['car_id'] ?? '').toString().trim();
      if (carId.isEmpty) continue;
      tasks.add(() async {
        try {
          final car = await ApiService.getCar(carId);
          final brand = (car['brand'] ?? '').toString().trim();
          final model = (car['model'] ?? '').toString().trim();
          if (brand.isNotEmpty) chat['car_brand'] = brand;
          if (model.isNotEmpty) chat['car_model'] = model;
          final trim = (car['trim'] ?? '').toString().trim();
          if (trim.isNotEmpty) chat['car_trim'] = trim;
          final year = (car['year'] ?? '').toString().trim();
          if (year.isNotEmpty) chat['car_year'] = year;
          final image = listingImageUrlFromMap(car);
          if (image.isNotEmpty) {
            chat['car_image_url'] = image;
          }
        } catch (_) {}
      }());
    }
    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }
  }

  Future<void> _loadChats() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getChats();
      await _enrichChatsFromCars(data);
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
            tooltip: _chatText(
              context,
              'Notifications',
              ar: 'الإشعارات',
              ku: 'ئاگادارکردنەوەکان',
            ),
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
                        final carTitle = localizedListingTitle(
                          context,
                          listingMetaFromChatRow(c),
                        );
                        final carImageUrl = resolveListingImageUrl(
                          (c['car_image_url'] ??
                                  c['image_url'] ??
                                  '')
                              .toString(),
                        );
                        final preview = _chatLastMessagePreview(context, last);
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
                                        if (carTitle.isNotEmpty)
                                          'carTitle': carTitle,
                                        if (carImageUrl.isNotEmpty)
                                          'carImageUrl': carImageUrl,
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
                                  buildChatListingAvatar(
                                    context,
                                    imageUrl: carImageUrl,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          carTitle.isNotEmpty
                                              ? carTitle
                                              : AppLocalizations.of(
                                                  context,
                                                )!.listingTitle,
                                          style: nameStyle,
                                        ),
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

