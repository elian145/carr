part of 'production_account_pages.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? me;
  bool _loading = true;
  late final AuthService _authService;
  int _unreadChatCount = 0;
  StreamSubscription<Map<String, dynamic>>? _chatNotificationSub;

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
      final type = (notification['notification_type'] ?? '').toString();
      if (type == 'message') {
        _loadUnreadChatCount();
      }
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
    await _loadUnreadChatCount();
    if (mounted) {
      setState(() {
        _loading = false;
      });
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
    } catch (e, st) { logNonFatal(e, st); }
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
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushReplacementNamed(context, '/signup');
              },
              child: Text(AppLocalizations.of(ctx)!.signupTitle),
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.profileTitle)),
      body: _loading
          ? Stack(
              children: [
                Container(decoration: _shellDecoration(context)),
                const Center(child: CircularProgressIndicator()),
              ],
            )
          : _buildLoggedInState(context),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        onTap: (idx) {
          switch (idx) {
            case 0:
              navigateMainShellTab(context, '/');
              break;
            case 1:
              navigateMainShellTab(context, '/favorites');
              break;
            case 2:
              navigateMainShellTab(context, '/dealers');
              break;
            case 3:
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                navigateMainShellTab(context, '/profile');
              }
              break;
          }
        },
      ),
    );
  }
}
