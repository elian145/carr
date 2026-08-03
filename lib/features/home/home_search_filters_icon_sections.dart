part of 'home_flow.dart';

mixin _HomePageSearchFiltersIconSections on _HomePageSearchFiltersBrand {
  String _searchOptionSummary(
    BuildContext context,
    String? selected, {
    String Function(BuildContext, String)? labelForOption,
  }) {
    if (selected == null || selected.isEmpty || selected == 'Any') {
      return '';
    }
    return labelForOption?.call(context, selected) ??
        _translateValueGlobal(context, selected) ??
        selected;
  }

  double _searchIconTileHeight({
    required bool textOnly,
    double? imageHeight,
    bool compactImageTile = false,
  }) {
    if (textOnly) return 52;
    final slotHeight = imageHeight ?? 26;
    // Tile uses symmetric vertical padding; selected state adds a 2px border.
    final verticalPadding = compactImageTile
        ? 16.0
        : (slotHeight > 80 ? 16.0 : 20.0);
    const gap = 6.0;
    const labelHeight = 15.0;
    const borderAllowance = 4.0;
    return verticalPadding + slotHeight + gap + labelHeight + borderAllowance;
  }

  double _searchIconScrollListHeight({
    required bool textOnly,
    required List<String> options,
    double? tileImageHeight,
    String? Function(String option)? imageAssetForOption,
    Widget? Function(String option)? graphicForOption,
    bool compactImageTile = false,
  }) {
    if (textOnly) return 52;
    var maxHeight = 0.0;
    for (final option in options) {
      final hasGraphic = graphicForOption != null ||
          (imageAssetForOption?.call(option) != null);
      final height = _searchIconTileHeight(
        textOnly: false,
        imageHeight: hasGraphic ? tileImageHeight : null,
        compactImageTile: compactImageTile,
      );
      if (height > maxHeight) maxHeight = height;
    }
    return maxHeight + 4;
  }

  Widget _searchIconOptionTile(
    BuildContext context, {
    required bool selected,
    IconData? icon,
    String? imageAsset,
    Widget? customGraphic,
    required String label,
    required VoidCallback onTap,
    double? width = 72,
    double? imageWidth,
    double? imageHeight,
    BoxFit imageFit = BoxFit.contain,
    double imageBorderRadius = 0,
    bool textOnly = false,
    bool compactImageTile = false,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final idleColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final isFuelAsset =
        imageAsset != null && imageAsset.startsWith('assets/fuel_types/');
    final effectiveImageWidth = isFuelAsset
        ? (imageWidth == null ? 40.0 : imageWidth!.clamp(32.0, 48.0).toDouble())
        : imageWidth;
    final effectiveImageHeight = isFuelAsset
        ? (imageHeight == null
            ? 40.0
            : imageHeight!.clamp(32.0, 48.0).toDouble())
        : imageHeight;
    final effectiveCompact = compactImageTile || isFuelAsset;
    final effectiveWidth = isFuelAsset
        ? (width == null ? 80.0 : width!.clamp(72.0, 88.0).toDouble())
        : width;
    final Widget? graphic;
    if (textOnly) {
      graphic = null;
    } else if (customGraphic != null) {
      final slotWidth = effectiveImageWidth ?? 26;
      final slotHeight = effectiveImageHeight ?? 26;
      graphic = SizedBox(
        width: slotWidth,
        height: slotHeight,
        child: Center(child: customGraphic),
      );
    } else {
      final slotWidth = effectiveImageWidth ?? 26;
      final slotHeight = effectiveImageHeight ?? 26;
      final Widget slotChild;
      if (imageAsset != null) {
        slotChild = buildFilterIconImage(
          context: context,
          imageAsset: imageAsset,
          width: slotWidth,
          height: slotHeight,
          fit: imageFit,
          borderRadius: imageBorderRadius,
        );
      } else {
        slotChild = Icon(
          icon ?? Icons.grid_view_rounded,
          size: slotHeight * 0.85,
          color: selected ? _searchAccent : idleColor,
        );
      }
      graphic = SizedBox(
        width: slotWidth,
        height: slotHeight,
        child: Center(child: slotChild),
      );
    }
    final hPad = textOnly
        ? 12.0
        : (AppResponsive.isCompactPhone(context) ? 4.0 : 6.0);
    final vPad = textOnly
        ? 14.0
        : (effectiveCompact
            ? ((effectiveImageHeight ?? 26) <= 24 ? 4.0 : 6.0)
            : ((effectiveImageHeight ?? 0) > 80 ? 8.0 : 10.0));
    final gap = effectiveCompact && (effectiveImageHeight ?? 26) <= 40 ? 4.0 : 6.0;
    final radius =
        effectiveCompact && (effectiveImageHeight ?? 26) <= 40 ? 8.0 : 12.0;
    final tile = Material(
      color: isLight ? Colors.white : filterIconTileBackdropColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: selected ? _searchAccent : const Color(0xFFE0E0E5),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (graphic != null) ...[
                Center(child: graphic),
                SizedBox(height: gap),
              ],
              AppResponsive.fittedLabel(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppResponsive.filterIconLabelFontSize(
                    context,
                    textOnly: textOnly,
                    regular: effectiveCompact &&
                            (effectiveImageHeight ?? 26) < 36
                        ? 11
                        : 12,
                  ),
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: selected ? _searchAccent : idleColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (effectiveWidth == null) {
      return SizedBox(width: double.infinity, child: tile);
    }
    return SizedBox(
      width: AppResponsive.filterIconTileWidth(
        context,
        effectiveWidth,
        compactBoost: effectiveCompact ? 0 : 16,
      ),
      child: tile,
    );
  }

  Widget _searchIconCardSection(
    BuildContext context,
    StateSetter setStateDialog, {
    required String title,
    required List<String> options,
    required String? selected,
    required void Function(String? value) onSelected,
    IconData Function(String option)? iconForOption,
    String? Function(String option)? imageAssetForOption,
    Widget? Function(String option)? graphicForOption,
    String Function(BuildContext, String)? labelForOption,
    bool scrollHorizontally = false,
    bool textOnly = false,
    double tileWidth = 72,
    double? tileImageWidth,
    double? tileImageHeight,
    BoxFit tileImageFit = BoxFit.contain,
    double tileImageBorderRadius = 0,
    double? scrollListHeight,
    bool compactImageTile = false,
  }) {
    final visibleOptions =
        options.where((option) => option != 'Any').toList(growable: false);
    final normalizedSelected =
        (selected == null || selected.isEmpty || selected == 'Any')
            ? null
            : selected;

    final tiles = visibleOptions.map((option) {
      final isSelected = normalizedSelected == option;
      final label = labelForOption?.call(context, option) ??
          _translateValueGlobal(context, option) ??
          option;
      final customGraphic = graphicForOption?.call(option);
      final usesImageAsset = !textOnly &&
          customGraphic == null &&
          imageAssetForOption != null;
      return _searchIconOptionTile(
        context,
        selected: isSelected,
        icon: textOnly
            ? null
            : (customGraphic != null
                ? null
                : (usesImageAsset &&
                        imageAssetForOption.call(option) == null
                    ? iconForOption?.call(option)
                    : (usesImageAsset ? null : iconForOption?.call(option)))),
        imageAsset: textOnly || customGraphic != null
            ? null
            : imageAssetForOption?.call(option),
        customGraphic: customGraphic,
        label: label,
        width: scrollHorizontally ? tileWidth : null,
        imageWidth: (usesImageAsset || customGraphic != null)
            ? tileImageWidth
            : null,
        imageHeight: (usesImageAsset || customGraphic != null)
            ? tileImageHeight
            : null,
        imageFit: tileImageFit,
        imageBorderRadius: tileImageBorderRadius,
        textOnly: textOnly,
        compactImageTile: compactImageTile,
        onTap: () {
          setState(() => onSelected(isSelected ? null : option));
          setStateDialog(() {});
        },
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _searchCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _searchSectionHeader(
              context,
              title: title,
              valueSummary: _searchOptionSummary(
                context,
                selected,
                labelForOption: labelForOption,
              ),
              onSummaryTap: () {
                setState(() => onSelected(null));
                setStateDialog(() {});
              },
            ),
            const SizedBox(height: 12),
            if (scrollHorizontally)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      tiles[i],
                    ],
                  ],
                ),
              )
            else
              Row(
                children: tiles
                    .map(
                      (tile) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: tile,
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _searchMultiIconCardSection(
    BuildContext context,
    StateSetter setStateDialog, {
    required String title,
    required List<String> options,
    required List<String> selectedValues,
    required void Function(String value) onToggle,
    required VoidCallback onClear,
    IconData Function(String option)? iconForOption,
    String? Function(String option)? imageAssetForOption,
    String Function(BuildContext, String)? labelForOption,
    bool scrollHorizontally = false,
    double tileWidth = 72,
    double? tileImageWidth,
    double? tileImageHeight,
    BoxFit tileImageFit = BoxFit.contain,
    double tileImageBorderRadius = 0,
    double? scrollListHeight,
  }) {
    final visibleOptions =
        options.where((option) => option != 'Any').toList(growable: false);

    final tiles = visibleOptions.map((option) {
      final isSelected = selectedValues.contains(option);
      final label = labelForOption?.call(context, option) ??
          _translateValueGlobal(context, option) ??
          option;
      return _searchIconOptionTile(
        context,
        selected: isSelected,
        icon: imageAssetForOption?.call(option) == null
            ? iconForOption?.call(option)
            : null,
        imageAsset: imageAssetForOption?.call(option),
        label: label,
        width: scrollHorizontally ? tileWidth : null,
        imageWidth: imageAssetForOption == null ? null : tileImageWidth,
        imageHeight: imageAssetForOption == null ? null : tileImageHeight,
        imageFit: tileImageFit,
        imageBorderRadius: tileImageBorderRadius,
        onTap: () {
          setState(() => onToggle(option));
          setStateDialog(() {});
        },
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _searchCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _searchSectionHeader(
              context,
              title: title,
              valueSummary: homeFilterSummaryLabel(
                '',
                selectedValues,
                (value) =>
                    labelForOption?.call(context, value) ??
                    _translateValueGlobal(context, value) ??
                    value,
              ),
              onSummaryTap: () {
                setState(onClear);
                setStateDialog(() {});
              },
            ),
            const SizedBox(height: 12),
            if (scrollHorizontally)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      tiles[i],
                    ],
                  ],
                ),
              )
            else
              Row(
                children: tiles
                    .map(
                      (tile) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: tile,
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}
