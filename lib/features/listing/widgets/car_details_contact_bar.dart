import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
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

  @override
  Widget build(BuildContext context) {
    final compact = AppResponsive.isCompactPhone(context);
    final loc = AppLocalizations.of(context)!;

    return Row(
      children: [
        Expanded(
          child: _ContactActionButton(
            compact: compact,
            backgroundColor: const Color(0xFF25D366),
            icon: Icons.chat,
            label: loc.chatOnWhatsApp,
            onPressed: onWhatsApp,
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: _ContactActionButton(
            compact: compact,
            backgroundColor: const Color(0xFF007AFF),
            icon: Icons.phone,
            label: loc.callSeller,
            onPressed: onCall,
          ),
        ),
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
    final double iconSize = compact ? 17 : 19;
    final double fontSize = compact ? 12 : 13;
    final double gap = compact ? 5 : 6;

    return SizedBox(
      height: 46,
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
                    textScaler: const TextScaler.linear(1.0),
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
