import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/app_localizations.dart';
import '../home_filter_chips.dart';

/// Tappable chip for one active home listing filter.
class HomeFilterChip extends StatelessWidget {
  const HomeFilterChip({
    super.key,
    required this.descriptor,
    required this.onClear,
  });

  final HomeFilterChipDescriptor descriptor;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final chipLabel = '${descriptor.label}: ${descriptor.value}';
    final color = descriptor.color;
    return Semantics(
      button: true,
      label: '${AppLocalizations.of(context)!.clearFilters}, $chipLabel',
      child: GestureDetector(
        onTap: onClear,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(descriptor.icon, color: color, size: 10),
              const SizedBox(width: 4),
              Text(
                chipLabel,
                style: GoogleFonts.orbitron(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 4),
              Icon(Icons.close, color: color, size: 9),
            ],
          ),
        ),
      ),
    );
  }
}
