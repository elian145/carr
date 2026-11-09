import 'package:flutter/material.dart';

/// F-24: tappable badge drawn on top of a photo/video thumbnail in the sell
/// flow (remove "x", cover "star"). The visible badge stays compact, but the
/// hit area is at least [kMinTapTarget] x [kMinTapTarget] (WCAG 2.5.5 /
/// Material 48dp) and it is exposed to screen readers as one labelled button.
class SellMediaOverlayButton extends StatelessWidget {
  const SellMediaOverlayButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconSize = 18,
    this.roundedRect = false,
  });

  static const double kMinTapTarget = 48;

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double iconSize;

  /// Cover star uses a rounded square badge, remove uses a circle.
  final bool roundedRect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        width: kMinTapTarget,
        height: kMinTapTarget,
        child: InkResponse(
          onTap: onTap,
          radius: kMinTapTarget / 2,
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: roundedRect ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: roundedRect ? BorderRadius.circular(8) : null,
              ),
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: iconSize, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
