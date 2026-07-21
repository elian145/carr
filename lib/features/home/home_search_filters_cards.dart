part of 'home_flow.dart';

const Color _searchAccent = Color(0xFFFF6B00);

mixin _HomePageSearchFiltersCards on _HomePageMoreFiltersDialog {

  MoreFiltersDialogStyle _searchMoreFiltersStyle(BuildContext context) {
    final base = _moreFiltersStyle(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return MoreFiltersDialogStyle(
      onSurface: base.onSurface,
      muted: base.muted,
      anyOrange: base.anyOrange,
      fieldFill: isLight ? Colors.white : base.fieldFill,
      menuFill: base.menuFill,
      fieldGap: 12,
    );
  }

  Widget _searchNumericRangeCard({
    required BuildContext context,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _searchCard(
        context,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
  String _searchBrandLabel(BuildContext context) {
    final brand = _homeSelectedBrand;
    if (brand == null) return '';
    final localized = CarNameTranslations.getLocalizedBrand(context, brand);
    return localized.isNotEmpty ? localized : brand;
  }

  String _searchModelLabel(BuildContext context) {
    if (selectedModel == null || selectedModel!.isEmpty) return '';
    final localized = CarNameTranslations.getLocalizedModel(
      context,
      _homeSingleSelectedBrand,
      selectedModel,
    );
    return localized.isNotEmpty ? localized : selectedModel!;
  }

  String _searchTrimLabel(BuildContext context) {
    if (selectedTrim == null || selectedTrim!.isEmpty) return '';
    return selectedTrim!;
  }

  String _searchShowCarsLabel(BuildContext context) {
    return AppLocalizations.of(context)!.showCars;
  }
  BoxDecoration _searchCardDecoration(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxDecoration(
      color: isLight ? const Color(0xFFF7F7F9) : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isLight ? const Color(0xFFE8E8ED) : Colors.white12,
      ),
    );
  }

  Widget _searchCard(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: _searchCardDecoration(context),
      child: child,
    );
  }

  Widget _searchSectionHeader(
    BuildContext context, {
    required String title,
    required String valueSummary,
    VoidCallback? onSummaryTap,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final titleColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final summaryColor = isLight ? const Color(0xFF8E8E93) : Colors.white70;
    final summaryStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: summaryColor,
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: titleColor,
            ),
          ),
        ),
        InkWell(
          onTap: onSummaryTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  valueSummary,
                  style: summaryStyle,
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: summaryColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}
