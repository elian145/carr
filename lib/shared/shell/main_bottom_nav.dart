import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

Widget buildFloatingBottomNav(
  BuildContext context, {
  required int currentIndex,
  required ValueChanged<int> onTap,
  bool solidBackground = false,
}) {
  final brightness = Theme.of(context).brightness;
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
      selectedItemColor: const Color(0xFFFF6B00),
      unselectedItemColor: unselectedItemColor,
      selectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      showSelectedLabels: true,
      showUnselectedLabels: true,
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: AppLocalizations.of(context)!.navHome,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.favorite),
          label: AppLocalizations.of(context)!.navSaved,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.storefront_outlined),
          label: AppLocalizations.of(context)!.navDealers,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: AppLocalizations.of(context)!.navProfile,
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

  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    child: SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: solidBackground ? solidFill : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isLight
                ? Colors.white.withOpacity(0.14)
                : Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isLight ? 0.08 : 0.14),
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
  );
}
