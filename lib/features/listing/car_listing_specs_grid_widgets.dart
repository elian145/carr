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
      return const SizedBox.shrink();
    }
    final isLight = Theme.of(context).brightness == Brightness.light;
    const brandOrange = AppColors.brandOrange;
    const iconCircleFillLight = Color(0xFFFFF0E6);
    const iconCircleFillDark = Color(0xFFFFE8D6);
    const labelGrey = Color(0xFF8E8E93);
    final cardBg = onTap != null
        ? (isLight
            ? const Color(0xFFFFF7F0)
            : const Color(0xFF2A211C))
        : (isLight ? Colors.white : const Color(0xFF1E1E1E));
    final iconCircleFill = isLight ? iconCircleFillLight : iconCircleFillDark;
    final valueColor = isLight ? Colors.black : Colors.white;

    final row = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconCircleFill,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: brandOrange),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: labelGrey,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
              if (valueWidget != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: valueWidget,
                  ),
                ),
              ] else if (value != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value!,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onTap != null ? brandOrange : valueColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    color: brandOrange,
                    size: 22,
                  ),
                ],
              ] else if (onTap != null) ...[
                const Spacer(),
                const Icon(
                  Icons.chevron_right,
                  color: brandOrange,
                  size: 22,
                ),
              ],
            ],
          ),
        ),
        const ColoredBox(
          color: brandOrange,
          child: SizedBox(height: 2.5, width: double.infinity),
        ),
      ],
    );

    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.10 : 0.50),
            blurRadius: isLight ? 18 : 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.05 : 0.28),
            blurRadius: isLight ? 6 : 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: onTap != null
            ? Border.all(color: brandOrange.withValues(alpha: 0.55))
            : Border.all(
                color: isLight
                    ? const Color(0xFFE8E8ED)
                    : Colors.white.withValues(alpha: 0.08),
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: row,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: card,
      ),
    );
  }

Widget carListingSpecsCard(ListingSpecItem item) {
  const brandOrange = AppColors.brandOrange;
  const labelGrey = Color(0xFF8E8E93);

  return Semantics(
    label: '${item.label}: ${item.value ?? ''}',
    child: Builder(
      builder: (context) {
        final isLight = Theme.of(context).brightness == Brightness.light;
        final cardBg = isLight ? Colors.white : const Color(0xFF1E1E1E);
        final iconCircleFill =
            isLight ? const Color(0xFFFFF0E6) : const Color(0xFFFFE8D6);
        final valueColor = isLight ? Colors.black : Colors.white;

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: cardBg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.10 : 0.50),
                blurRadius: isLight ? 16 : 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.28),
                blurRadius: isLight ? 4 : 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: isLight
                  ? const Color(0xFFE8E8ED)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final double iconSize =
                              (constraints.maxWidth * 0.28).clamp(22.0, 30.0);
                          final double circleSize =
                              (constraints.maxWidth * 0.42).clamp(34.0, 44.0);
                          final double labelFontSize =
                              (constraints.maxWidth * 0.12).clamp(9.0, 11.0);
                          final double valueFontSize =
                              (constraints.maxWidth * 0.15).clamp(11.0, 14.0);

                          final Widget iconGlyph;
                          final asset = item.imageAsset;
                          if (asset != null && asset.isNotEmpty) {
                            iconGlyph = ColorFiltered(
                              colorFilter: const ColorFilter.mode(
                                brandOrange,
                                BlendMode.srcIn,
                              ),
                              child: Image.asset(
                                asset,
                                width: iconSize,
                                height: iconSize,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (context, error, stackTrace) =>
                                    Icon(
                                  item.icon,
                                  size: iconSize,
                                  color: brandOrange,
                                ),
                              ),
                            );
                          } else {
                            iconGlyph = Icon(
                              item.icon,
                              size: iconSize,
                              color: brandOrange,
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Center(
                                  child: Container(
                                    width: circleSize,
                                    height: circleSize,
                                    decoration: BoxDecoration(
                                      color: iconCircleFill,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: iconGlyph,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: AutoSizeText(
                                    item.label,
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    textScaleFactor: 1.0,
                                    style: TextStyle(
                                      fontSize: labelFontSize,
                                      height: 1.05,
                                      color: labelGrey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    minFontSize: 7,
                                    stepGranularity: 0.5,
                                    overflow: TextOverflow.clip,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Center(
                                  child: AutoSizeText(
                                    item.value!,
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    textScaleFactor: 1.0,
                                    style: TextStyle(
                                      fontSize: valueFontSize,
                                      height: 1.05,
                                      color: valueColor,
                                      fontWeight: FontWeight.w800,
                                    ),
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
                    ),
                  ),
                  const ColoredBox(
                    color: brandOrange,
                    child: SizedBox(height: 2.5, width: double.infinity),
                  ),
                ],
              ),
            ),
          );
      },
    ),
  );
}
