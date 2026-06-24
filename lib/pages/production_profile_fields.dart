part of 'production_account_pages.dart';

abstract class _ProfilePageFields extends State<ProfilePage> {
  Map<String, dynamic>? me;
  bool _loading = true;
  late final AuthService _authService;
  int _unreadChatCount = 0;
  StreamSubscription<Map<String, dynamic>>? _chatNotificationSub;
}
