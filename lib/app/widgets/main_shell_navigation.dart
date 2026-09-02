import 'dart:ui' as ui;
import '../../theme/app_colors.dart';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../navigation/app_page_route.dart';
import '../../shared/ui/responsive.dart';
import '../route_registry.dart';

/// Main-tab switch using [AppPageRoute] so edge swipe-back can return to the
/// previous tab instead of replacing the navigator stack.
void navigateMainShellTab(BuildContext context, String routeName) {
  final currentRoute = ModalRoute.of(context)?.settings.name;
  if (currentRoute == routeName) return;

  final navigator = Navigator.of(context);

  var foundTarget = false;
  navigator.popUntil((route) {
    if (route.settings.name == routeName) {
      foundTarget = true;
      return true;
    }
    if (route.isFirst) {
      return true;
    }
    return false;
  });

  if (!foundTarget && ModalRoute.of(context)?.settings.name != routeName) {
    final builder = appRouteBuilders[routeName];
    if (builder == null) {
      navigator.pushNamed(routeName);
      return;
    }

    navigator.push(
      AppPageRoute<void>(
        settings: RouteSettings(name: routeName),
        builder: builder,
      ),
    );
  }
}

Widget buildFloatingBottomNav(
  BuildContext context, {
  required int currentIndex,
  required ValueChanged<int> onTap,
  bool solidBackground = false,
}) {
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
        backgroundColor: solidBackground ? solidFill : Colors.transparent,
        elevation: 0,
      ),
    ),
    child: BottomNavigationBar(
      key: ValueKey<int>(currentIndex),
      type: BottomNavigationBarType.fixed,
      backgroundColor: solidBackground ? solidFill : Colors.transparent,
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
      currentIndex: currentIndex,
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

  final Widget navBody = solidBackground
      ? bar
      : BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: bar,
        );

  return Semantics(
    container: true,
    label: 'Main navigation',
    child: Padding(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 12, 0, compact ? 8 : 12, 10),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: solidBackground ? solidFill : null,
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
