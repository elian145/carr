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
    final languageCode = Localizations.localeOf(context).languageCode;
    final bool useLatinDisplayFont =
        languageCode != 'ar' && languageCode != 'ku';
    final textStyle = (useLatinDisplayFont
            ? GoogleFonts.orbitron(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
                height: 1.2,
              )
            : TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ));

    return Semantics(
      button: true,
      label: '${AppLocalizations.of(context)!.clearFilters}, $chipLabel',
      child: Container(
        padding: const EdgeInsetsDirectional.only(
          start: 10,
          end: 2,
          top: 6,
          bottom: 6,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(descriptor.icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(
              chipLabel,
              style: textStyle,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 8, 2),
                  child: Icon(Icons.close, color: color, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
