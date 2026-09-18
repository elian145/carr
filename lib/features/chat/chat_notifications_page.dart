part of 'chat_pages.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final List<AppNotification> _notifications = [];
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasNext = false;
  // B-04: tracks whether the most recent *initial* load (refresh: true)
  // failed, so a failed load can be distinguished from a genuinely empty
  // inbox instead of both rendering the same "No notifications yet" state.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _setupWebSocketListeners();
  }

  void _setupWebSocketListeners() {
    _notificationSub?.cancel();
    _notificationSub = WebSocketService.notifications.listen((notification) {
      if (!mounted) return;
      final incoming = AppNotification.fromJson(notification);
      if (incoming.id.isEmpty) return;
      setState(() {
        final existingIndex = _notifications.indexWhere(
          (n) => n.id == incoming.id,
        );
        if (existingIndex >= 0) {
          _notifications[existingIndex] = incoming;
        } else {
          _notifications.insert(0, incoming);
        }
      });
    });
  }

  Future<void> _loadNotifications({bool refresh = true}) async {
    if (refresh) {
      if (mounted) {
        setState(() {
          _loading = true;
          _page = 1;
          // B-04: clear any stale error from a previous attempt up front so
          // a new load never briefly shows a leftover error state.
          _loadFailed = false;
        });
      }
    } else {
      if (_loadingMore || !_hasNext) return;
      if (mounted) setState(() => _loadingMore = true);
    }

    final page = refresh ? 1 : _page + 1;
    try {
      final response = await ApiService.getUserNotifications(
        page: page,
        perPage: 30,
      );
      final raw = response['notifications'];
      final parsed = <AppNotification>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          final notification = AppNotification.fromJson(map);
          if (notification.id.isEmpty) continue;
          parsed.add(notification);
        }
      }
      final pagination = response['pagination'];
      final hasNext = pagination is Map && pagination['has_next'] == true;

      if (!mounted) return;
      setState(() {
        if (refresh) {
          _notifications
            ..clear()
            ..addAll(parsed);
        } else {
          for (final notification in parsed) {
            if (_notifications.any((n) => n.id == notification.id)) continue;
            _notifications.add(notification);
          }
        }
        _page = page;
        _hasNext = hasNext;
        _loading = false;
        _loadingMore = false;
        // B-04: any successful load clears a previously-shown error state.
        _loadFailed = false;
      });
    } catch (e, st) {
      logNonFatal(e, st, 'NotificationsPage.load');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        // B-04: only the initial-load/pull-to-refresh path (refresh: true)
        // shows the distinct error/retry state. A failed "load more" page
        // must not replace already-loaded notifications with an error
        // screen — it silently stops, exactly as before this fix.
        if (refresh) _loadFailed = true;
      });
    }
  }

  Future<void> _markNotificationRead(AppNotification notification) async {
    if (notification.isRead || notification.id.isEmpty) return;
    final index = _notifications.indexWhere((n) => n.id == notification.id);
    if (index >= 0 && mounted) {
      setState(() {
        _notifications[index] = notification.copyWith(isRead: true);
      });
    }
    try {
      await ApiService.markUserNotificationRead(notification.id);
    } catch (e, st) {
      logNonFatal(e, st, 'NotificationsPage.markRead');
    }
  }

  Future<void> _onNotificationTap(AppNotification notification) async {
    await _markNotificationRead(notification);
    if (!mounted) return;
    final type = notification.notificationType.toLowerCase();
    final data = notification.data ?? const <String, dynamic>{};
    if (type == 'message' || type == 'chat_message') {
      final carId =
          (data['car_id'] ?? data['carId'] ?? data['conversation_id'] ?? '')
              .toString()
              .trim();
      if (carId.isNotEmpty) {
        await Navigator.pushNamed(
          context,
          '/chat/conversation',
          arguments: {
            'carId': carId,
            if ((data['sender_id'] ?? data['receiver_id']) != null)
              'receiverId': (data['sender_id'] ?? data['receiver_id'])
                  .toString(),
          },
        );
      } else {
        await Navigator.pushNamed(context, '/chat');
      }
      return;
    }
    if (type == 'dealer_application') {
      // B-07: the dealer onboarding/status screen already shows the user's
      // current application/status, so route there instead of no-op'ing.
      await Navigator.pushNamed(context, '/dealer-onboarding');
      return;
    }
    final listingId =
        (data['listing_id'] ?? data['car_id'] ?? data['carId'] ?? '')
            .toString()
            .trim();
    if (listingId.isNotEmpty) {
      await Navigator.pushNamed(
        context,
        '/car_detail',
        arguments: {'carId': listingId},
      );
    }
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.notificationsTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadNotifications(refresh: true),
              child: _notifications.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.55,
                          // B-04: a failed initial/refresh load must not look
                          // identical to a genuinely empty inbox — show a
                          // distinct, retryable error state instead, reusing
                          // the existing EmptyStatePanel's optional action.
                          child: _loadFailed
                              ? EmptyStatePanel(
                                  icon: Icons.cloud_off,
                                  title: loc.failedToLoadNotifications,
                                  actionLabel: loc.retryAction,
                                  actionIcon: Icons.refresh,
                                  onAction: () =>
                                      _loadNotifications(refresh: true),
                                )
                              : EmptyStatePanel(
                                  icon: Icons.notifications_none_rounded,
                                  title: loc.noNotificationsYet,
                                ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _notifications.length + (_hasNext ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _notifications.length) {
                          if (!_loadingMore) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _loadNotifications(refresh: false);
                            });
                          }
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final notification = _notifications[index];
                        final unread = !notification.isRead;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _onNotificationTap(notification),
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: unread
                                      ? AppColors.brandOrange.withValues(
                                          alpha:
                                              theme.brightness ==
                                                  Brightness.light
                                              ? 0.08
                                              : 0.14,
                                        )
                                      : theme.colorScheme.surfaceContainerHighest
                                            .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: unread
                                        ? AppColors.brandOrange.withValues(
                                            alpha: 0.28,
                                          )
                                        : theme.dividerColor.withValues(
                                            alpha: 0.5,
                                          ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: AppColors.brandOrange
                                            .withValues(
                                              alpha: unread ? 0.16 : 0.1,
                                            ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        _getNotificationIcon(
                                          notification.notificationType,
                                        ),
                                        size: 18,
                                        color: unread
                                            ? AppColors.brandOrange
                                            : ink.withValues(alpha: 0.55),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            notification.title.isEmpty
                                                ? loc.notificationsTitle
                                                : notification.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: unread
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: ink,
                                            ),
                                          ),
                                          if (notification.message
                                              .trim()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              notification.message,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                height: 1.35,
                                                color: ink.withValues(
                                                  alpha: 0.7,
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          Text(
                                            _relativeTime(
                                              context,
                                              notification.createdAt,
                                            ),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: ink.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (unread) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(top: 6),
                                        decoration: const BoxDecoration(
                                          color: AppColors.brandOrange,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  IconData _getNotificationIcon(String type) {
    switch (type.toLowerCase()) {
      case 'message':
      case 'chat_message':
        return Icons.message_outlined;
      case 'listing':
      case 'saved_search':
        return Icons.directions_car_outlined;
      case 'favorite':
        return Icons.favorite_outline;
      case 'dealer_application':
        return Icons.storefront_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }
}
