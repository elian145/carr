import 'package:flutter/material.dart';

import '../../features/home/home_flow.dart' show HomePage;
import '../../pages/dealers_directory_page.dart';
import '../../pages/production_account_pages.dart' show ProfilePage;
import '../carzo_shared.dart' show AuthGuard;
import 'home_tab_actions.dart';
import 'main_shell_navigation.dart';

/// Persistent host for Home / Dealers / Profile so tab switches do not remount
/// the feed. Sell is pushed as a normal route on top (wizard remounts each time).
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  /// Bottom-nav index: 0 Home, 2 Dealers, 3 Profile. (1 = Sell is never kept here.)
  final int initialIndex;

  static MainShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<MainShellState>();

  /// Attach so overlays (Sell/Login) can switch tabs after pop without finding
  /// the shell in their ancestor chain.
  static MainShellState? _attached;

  static void attach(MainShellState state) => _attached = state;

  static void detach(MainShellState state) {
    if (identical(_attached, state)) _attached = null;
  }

  static MainShellState? get attached => _attached;

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  late int _tabIndex;
  final Set<int> _visitedTabs = <int>{0};

  @override
  void initState() {
    super.initState();
    _tabIndex = _sanitize(widget.initialIndex);
    _visitedTabs.add(_tabIndex);
    MainShell.attach(this);
  }

  @override
  void dispose() {
    MainShell.detach(this);
    super.dispose();
  }

  int _sanitize(int index) {
    if (index == 1) return 0; // Sell is not a kept tab
    if (index < 0 || index > 3) return 0;
    return index;
  }

  void selectTab(int index) {
    final next = _sanitize(index);
    if (!mounted) return;
    if (next == _tabIndex) {
      if (next == 0) HomeTabActions.scrollToTop();
      return;
    }
    setState(() {
      _tabIndex = next;
      _visitedTabs.add(next);
    });
  }

  void selectRoute(String routeName) {
    switch (routeName) {
      case '/' || '/home':
        selectTab(0);
      case '/dealers':
        selectTab(2);
      case '/profile':
        selectTab(3);
      default:
        break;
    }
  }

  int get tabIndex => _tabIndex;

  int get _stackIndex => switch (_tabIndex) {
        2 => 1,
        3 => 2,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _stackIndex,
        sizing: StackFit.expand,
        children: [
          const HomePage(embedInShell: true),
          _visitedTabs.contains(2)
              ? const DealersDirectoryPage(embedInShell: true)
              : const SizedBox.shrink(),
          _visitedTabs.contains(3)
              ? const AuthGuard(
                  allowWhenLoggedOut: true,
                  child: ProfilePage(embedInShell: true),
                )
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: _tabIndex,
        onTap: (idx) {
          if (idx == 1) {
            Navigator.of(context).pushNamed('/sell');
            return;
          }
          selectTab(idx);
        },
      ),
    );
  }
}
