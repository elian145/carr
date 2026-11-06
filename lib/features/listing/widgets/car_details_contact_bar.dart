import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/app_text_scale.dart';
import '../../../shared/ui/responsive.dart';

/// WhatsApp + call actions on the listing detail page.
class CarDetailsContactBar extends StatelessWidget {
  const CarDetailsContactBar({
    super.key,
    required this.onWhatsApp,
    required this.onCall,
  });

  final VoidCallback onWhatsApp;
  final VoidCallback onCall;

  /// Above this system text scale the two buttons stack vertically.
  static const double stackAboveTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final compact = AppResponsive.isCompactPhone(context);
    final loc = AppLocalizations.of(context)!;

    final whatsApp = _ContactActionButton(
      compact: compact,
      backgroundColor: const Color(0xFF25D366),
      icon: Icons.chat,
      label: loc.chatOnWhatsApp,
      onPressed: onWhatsApp,
    );
    final call = _ContactActionButton(
      compact: compact,
      backgroundColor: const Color(0xFF007AFF),
      icon: Icons.phone,
      label: loc.callSeller,
      onPressed: onCall,
    );
    final gap = compact ? 6.0 : 8.0;

    // Large system text: two half-width buttons cannot hold the labels, so
    // stack them full width (each stays a full-size, reachable target).
    if (appTextScaleOf(context) > stackAboveTextScale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [whatsApp, SizedBox(height: gap), call],
      );
    }

    return Row(
      children: [
        Expanded(child: whatsApp),
        SizedBox(width: gap),
        Expanded(child: call),
      ],
    );
  }
}

class _ContactActionButton extends StatelessWidget {
  const _ContactActionButton({
    required this.compact,
    required this.backgroundColor,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool compact;
  final Color backgroundColor;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final double hPad = compact ? 8 : 12;
    final double iconSize = compact ? 18 : 20;
    final double fontSize = compact ? 14 : 16;
    final double gap = compact ? 5 : 6;

    // Button grows with the text (46dp at 1.0x) so scaled labels are not clipped.
    final double height = math.max(
      46.0,
      fontSize * appTextScaleOf(context) + 20,
    );

    return SizedBox(
      height: height,
      child: Semantics(
        button: true,
        label: label,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: Colors.black26,
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
            minimumSize: const Size(0, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          onPressed: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize),
              SizedBox(width: gap),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
