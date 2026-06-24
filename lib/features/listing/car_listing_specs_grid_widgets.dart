part of 'car_listing_specs_grid.dart';

Widget carListingSpecsDetailRow(
  BuildContext context, {
    required IconData icon,
    required String label,
    required String? value,
    Widget? valueWidget,
    VoidCallback? onTap,
  }) {
    if (valueWidget == null && (value == null || value.isEmpty)) {
      return SizedBox.shrink();
    }
    final isLight = Theme.of(context).brightness == Brightness.light;
    final content = Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: onTap != null
            ? (isLight ? const Color(0xFFFFF2E8) : Colors.white.withValues(alpha: 0.09))
            : (isLight ? const Color(0xFFF3F3F3) : Colors.white.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: onTap != null
              ? const Color(0xFFFF6B00).withValues(alpha: isLight ? 0.34 : 0.42)
              : (isLight ? const Color(0xFFE0E0E0) : Colors.white12),
          width: onTap != null ? 1.2 : 1,
        ),
        boxShadow: onTap != null
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: onTap != null
                  ? const Color(0xFFFF6B00)
                  : const Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.black),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isLight ? const Color(0xFF3A3A3A) : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (valueWidget != null)
            valueWidget
          else if (onTap != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    value!,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Color(0xFFFF6B00)),
              ],
            )
          else
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Color(0xFFFF6B00),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                value!,
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }

Widget carListingSpecsCard(ListingSpecItem item) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double labelFontSize =
              (constraints.maxWidth * 0.13).clamp(9.0, 11.0);
          final double valueFontSize =
              (constraints.maxWidth * 0.16).clamp(10.0, 14.0);

          final labelStyle = TextStyle(
            fontSize: labelFontSize,
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            height: 1.05,
          );
          final valueStyle = TextStyle(
            fontSize: valueFontSize,
            height: 1.0,
            color: Colors.black,
            fontWeight: FontWeight.w800,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 6,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: constraints.maxWidth * 0.13,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              constraints.maxWidth - (constraints.maxWidth * 0.13) - 4,
                        ),
                        child: AutoSizeText(
                          item.label,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          softWrap: false,
                          textScaleFactor: 1.0,
                          style: labelStyle,
                          minFontSize: 7,
                          stepGranularity: 0.5,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  vertical: math.max(3.0, constraints.maxHeight * 0.02),
                  horizontal: 6,
                ),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.black.withValues(alpha: 0.22),
                ),
              ),
              Expanded(
                flex: 5,
                child: Center(
                  child: AutoSizeText(
                    item.value!,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    textScaleFactor: 1.0,
                    style: valueStyle,
                    minFontSize: 9,
                    stepGranularity: 0.5,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
