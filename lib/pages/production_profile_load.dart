part of 'production_account_pages.dart';

mixin _ProfilePageLoad on _ProfilePageStyle {
  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _authService.addListener(_onAuthChange);
    final cached = _authService.currentUser;
    if (cached != null) {
      me = Map<String, dynamic>.from(cached);
    }
    _loadMe();
    _chatNotificationSub = WebSocketService.notifications.listen((
      notification,
    ) {
      if (!mounted) return;
      final type = (notification['notification_type'] ??
              notification['type'] ??
              '')
          .toString();
      if (type == 'message') {
        _loadUnreadChatCount();
      }
      _loadUnreadNotificationCount();
    });
  }

  @override
  void dispose() {
    // Do not use context in dispose; the element is being deactivated.
    _authService.removeListener(_onAuthChange);
    _chatNotificationSub?.cancel();
    super.dispose();
  }

  void _onAuthChange() {
    if (mounted) {
      _loadMe();
    }
  }

  Map<String, dynamic>? _effectiveProfile() => me ?? _authService.currentUser;

  Future<void> _loadMe() async {
    final cached = _authService.currentUser;
    if (cached != null) {
      me = Map<String, dynamic>.from(cached);
    }
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        setState(() {
          me = null;
          _loading = false;
          _unreadChatCount = 0;
          _unreadNotificationCount = 0;
        });
        return;
      }
      final response = await ApiService.getProfile();
      me = AuthService.profileFromResponse(response);
    } on ApiException catch (e, st) {
      logNonFatal(e, st);
    } catch (e, st) {
      logNonFatal(e, st);
    }
    if (me == null && _authService.currentUser != null) {
      me = Map<String, dynamic>.from(_authService.currentUser!);
    }
    await Future.wait([_loadUnreadChatCount(), _loadUnreadNotificationCount()]);
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadUnreadNotificationCount() async {
    final tok = ApiService.accessToken;
    if (tok == null || tok.isEmpty) {
      if (mounted) {
        setState(() => _unreadNotificationCount = 0);
      } else {
        _unreadNotificationCount = 0;
      }
      return;
    }
    try {
      final response = await ApiService.getUserNotifications(
        unreadOnly: true,
        perPage: 1,
      );
      final rawCount = response['unread_count'];
      final count = rawCount is int
          ? rawCount
          : int.tryParse(rawCount?.toString() ?? '') ?? 0;
      if (mounted) {
        setState(() => _unreadNotificationCount = count);
      } else {
        _unreadNotificationCount = count;
      }
    } catch (e, st) {
      logNonFatal(e, st, 'ProfilePage.loadUnreadNotificationCount');
    }
  }

  Future<void> _loadUnreadChatCount() async {
    final tok = ApiService.accessToken;
    if (tok == null || tok.isEmpty) {
      if (mounted) {
        setState(() => _unreadChatCount = 0);
      } else {
        _unreadChatCount = 0;
      }
      return;
    }
    try {
      final count = await ApiService.getUnreadChatCount();
      if (mounted) {
        setState(() => _unreadChatCount = count);
      } else {
        _unreadChatCount = count;
      }
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  void refreshProfile() {
    _loadMe();
  }

  Future<void> _showAuthRequiredDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.loginTitle),
          content: Text(AppLocalizations.of(ctx)!.notLoggedIn),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx)!.cancelAction),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: Text(AppLocalizations.of(ctx)!.loginAction),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }
}
