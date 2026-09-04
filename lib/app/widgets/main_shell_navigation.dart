import 'dart:ui' as ui;
import '../../theme/app_colors.dart';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/device_performance.dart';
import '../../shared/ui/responsive.dart';
import 'main_shell.dart';

Route<T> _zeroAnimRoute<T>(String routeName, WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: routeName),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  );
}

int? _shellTabIndexForRoute(String routeName) {
  switch (routeName) {
    case '/' || '/home':
      return 0;
    case '/dealers':
      return 2;
    case '/profile':
      return 3;
    default:
      return null;
  }
}

/// Switch main tabs. Home/Dealers/Profile stay alive under [MainShell]; Sell is pushed.
void navigateMainShellTab(BuildContext context, String routeName) {
  if (routeName == '/sell') {
    Navigator.of(context).pushNamed('/sell');
    return;
  }

  if (routeName == '/login') {
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    return;
  }

  final tabIndex = _shellTabIndexForRoute(routeName);
  if (tabIndex == null) {
    Navigator.of(context).pushNamedAndRemoveUntil(routeName, (route) => false);
    return;
  }

  final shellInTree = MainShell.of(context);
  if (shellInTree != null) {
    shellInTree.selectTab(tabIndex);
    return;
  }

  // Overlay (Sell, Login, …): pop back to the shell root when possible.
  final nav = Navigator.of(context);
  final attached = MainShell.attached;
  if (attached != null && attached.mounted) {
    attached.selectTab(tabIndex);
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
    return;
  }

  // No shell on the stack — install one at the requested tab.
  nav.pushAndRemoveUntil<void>(
    _zeroAnimRoute<void>(
      '/',
      (_) => MainShell(initialIndex: tabIndex),
    ),
    (route) => false,
  );
}

Widget buildFloatingBottomNav(
  BuildContext context, {
  required int currentIndex,
  required ValueChanged<int> onTap,
  bool solidBackground = false,
}) {
  // Android: skip live blur — BackdropFilter during scroll is a common mid-GPU hitch.
  final useSolid = solidBackground || DevicePerformance.preferSolidChrome;
  final brightness = Theme.of(context).brightness;
  final compact = AppResponsive.isCompactPhone(context);
  final isLight = brightness == Brightness.light;
  final unselectedItemColor = isLight
      ? const Color(0xFF666666)
      : const Color(0xD9FFFFFF);
  final solidFill = isLight ? Colors.white : const Color(0xFF1C1C1E);

  final bar = Theme(
    data: Theme.of(context).copyWith(
      canvasColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: useSolid ? solidFill : Colors.transparent,
        elevation: 0,
      ),
    ),
    child: BottomNavigationBar(
      key: ValueKey<int>(currentIndex),
      type: BottomNavigationBarType.fixed,
      backgroundColor: useSolid ? solidFill : Colors.transparent,
      elevation: 0,
      selectedItemColor: AppColors.brandOrange,
      unselectedItemColor: unselectedItemColor,
      selectedFontSize: compact ? 10 : 12,
      unselectedFontSize: compact ? 10 : 11,
      iconSize: compact ? 21 : 24,
      selectedLabelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
        overflow: TextOverflow.ellipsis,
      ),
      unselectedLabelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        overflow: TextOverflow.ellipsis,
      ),
      showSelectedLabels: true,
      showUnselectedLabels: !compact,
      currentIndex: currentIndex.clamp(0, 3),
      onTap: onTap,
      items: [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: AppLocalizations.of(context)!.navHome,
          tooltip: AppLocalizations.of(context)!.navHome,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.add),
          label: AppLocalizations.of(context)!.sellButton,
          tooltip: AppLocalizations.of(context)!.sellButton,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.storefront_outlined),
          label: AppLocalizations.of(context)!.navDealers,
          tooltip: AppLocalizations.of(context)!.navDealers,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: AppLocalizations.of(context)!.navProfile,
          tooltip: AppLocalizations.of(context)!.navProfile,
        ),
      ],
    ),
  );

  final Widget navBody = useSolid
      ? bar
      : BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: bar,
        );

  return Semantics(
    container: true,
    label: 'Main navigation',
    // SafeArea outside decorative padding so the 10dp gap stays above the
    // Android system navigation bar (edge-to-edge), not under it.
    child: SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 8 : 12, 0, compact ? 8 : 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: useSolid ? solidFill : null,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isLight
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.14),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: navBody,
          ),
        ),
      ),
    ),
  );
}
