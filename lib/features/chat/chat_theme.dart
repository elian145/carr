import 'package:flutter/material.dart';

import '../../theme_provider.dart';

/// Brand orange (matches home listing cards); explicit color avoids
/// [Theme.primaryColor] matching surfaces inside chat bubbles in dark mode.
const Color kChatListingCardAccentOrange = Color(0xFFFF6B00);

const Color kComposerOutlineOrange = Color(0xFFFF7A00);

/// Chat list row inks when chat UI is light ([ChatUiThemeController]).
const Color kChatListRowInkLight = Color(0xFF000000);
const Color kChatListRowInkDarkPrimary = Color(0xFFF5F5F5);
const Color kChatListRowInkDarkMuted = Color(0xFFCFCFCF);

/// Peer bubble / preview fill: frosted on dark shell; solid blend on light shell.
Color homeListingCardBackgroundFill(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return Colors.white.withValues(alpha: 0.10);
  }
  return AppThemes.listingCardFillGridOnLightShell();
}

Color peerBubbleTextStrong(BuildContext context) {
  final theme = Theme.of(context);
  if (theme.brightness == Brightness.light) {
    return theme.colorScheme.onSurface;
  }
  return Colors.white;
}

Color peerBubbleTextMuted(BuildContext context) {
  final theme = Theme.of(context);
  if (theme.brightness == Brightness.light) {
    return theme.colorScheme.onSurfaceVariant;
  }
  return Colors.white70;
}

Color peerBubbleBorderColor(BuildContext context) {
  final theme = Theme.of(context);
  if (theme.brightness == Brightness.light) {
    return theme.colorScheme.outline.withValues(alpha: 0.28);
  }
  return Colors.white.withValues(alpha: 0.12);
}
