part of 'comparison_page.dart';

extension _CarComparisonPageHelpers on CarComparisonPage {
  Widget _buildCarImage(BuildContext context, Map<String, dynamic> car) {
    final imageUrl = car['image_url']?.toString();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final built = buildLegacyFullImageUrl(imageUrl);
      return listingNetworkImage(built, fit: BoxFit.cover);
    }
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Icon(
        Icons.directions_car_outlined,
        color: scheme.onSurfaceVariant,
        size: 36,
      ),
    );
  }

  String _carTitle(BuildContext context, Map<String, dynamic> car) {
    final title = (car['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    return [
      localizedCarTitleForCard(context, car),
      localizedTrimForCard(context, car),
    ].where((s) => s.isNotEmpty).join(' ');
  }

  Widget _buildComparisonCarCard(
    BuildContext context,
    CarComparisonStore comparisonStore,
    Map<String, dynamic> car, {
    double? width,
  }) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final cardFill = isLight
        ? AppThemes.listingCardFillGridOnLightShell()
        : Colors.white.withValues(alpha: 0.10);
    final borderColor = isLight
        ? theme.colorScheme.outlineVariant
        : Colors.white24;

    final card = Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _buildCarImage(context, car),
            ),
          ),
          const SizedBox(height: 10),
          AutoSizeText(
            _carTitle(context, car),
            textScaleFactor: 1.0,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            minFontSize: 10,
            stepGranularity: 0.5,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            formatCurrency(context, car['price']?.toString() ?? '0'),
            style: const TextStyle(
              color: Color(0xFFFF6B00),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => comparisonStore.removeCarFromComparison(car['id']),
              child: Tooltip(
                message: AppLocalizations.of(context)!.removeAction,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonValueChip(BuildContext context, String text) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B00),
            borderRadius: BorderRadius.circular(999),
          ),
          child: AutoSizeText(
            text,
            textScaleFactor: 1.0,
            textAlign: TextAlign.center,
            maxLines: 2,
            minFontSize: 8,
            stepGranularity: 0.5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        );
      },
    );
  }

  Widget _buildComparisonLabel(
    BuildContext context, {
    required IconData icon,
    required String label,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B00),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: compact ? 16 : 18, color: Colors.black),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: isLight
                  ? theme.colorScheme.onSurfaceVariant
                  : Colors.white70,
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  BoxDecoration _comparisonRowDecoration(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxDecoration(
      color: isLight
          ? const Color(0xFFF3F3F3)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isLight ? const Color(0xFFE0E0E0) : Colors.white12,
      ),
    );
  }
}
