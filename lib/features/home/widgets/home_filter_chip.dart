import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/app_localizations.dart';
import '../home_filter_chips.dart';

/// First Strong Isolate / Pop Directional Isolate — keeps [value] from being
/// reordered relative to [label] when scripts mix (RTL Arabic + Latin).
String _chipLabelText(String label, String value) =>
    '$label: \u2068$value\u2069';

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
    final chipLabel = _chipLabelText(descriptor.label, descriptor.value);
    final color = descriptor.color;
    final languageCode = Localizations.localeOf(context).languageCode;
    final bool useLatinDisplayFont =
        languageCode != 'ar' && languageCode != 'ku';
    final textStyle = (useLatinDisplayFont
            ? GoogleFonts.orbitron(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.bold,
                height: 1.15,
              )
            : TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ));

    return Semantics(
      button: true,
      label: '${AppLocalizations.of(context)!.clearFilters}, $chipLabel',
      child: Container(
        padding: const EdgeInsetsDirectional.only(
          start: 6,
          end: 1,
          top: 3,
          bottom: 3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(descriptor.icon, color: color, size: 12),
            const SizedBox(width: 4),
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
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(4, 1, 5, 1),
                  child: Icon(Icons.close, color: color, size: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
