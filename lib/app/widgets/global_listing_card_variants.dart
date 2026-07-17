part of 'global_listing_card.dart';

enum _CardLogoStyle { square, circle, soft, none }

enum _CardSpecsStyle { chips, outline, plain, icons }

enum _CardPriceStyle { solid, outline, underline, plain }

@immutable
class _ListingCardPreset {
  const _ListingCardPreset({
    required this.accent,
    required this.composition,
    required this.radius,
    required this.logo,
    required this.specs,
    required this.price,
    this.borderWidth = 0,
    this.elevation = 8,
    this.imageFlex = 5,
    this.imageTrailing = false,
    this.imageScale = 1,
    this.accentEdge = false,
    this.centered = false,
  });

  final Color accent;
  final int composition;
  final double radius;
  final _CardLogoStyle logo;
  final _CardSpecsStyle specs;
  final _CardPriceStyle price;
  final double borderWidth;
  final double elevation;
  final int imageFlex;
  final bool imageTrailing;
  final double imageScale;
  final bool accentEdge;
  final bool centered;
}

const _orange = Color(0xFFFF5A00);
const _blue = Color(0xFF1677FF);
const _teal = Color(0xFF00897B);
const _purple = Color(0xFF7E57C2);
const _red = Color(0xFFE53935);
const _indigo = Color(0xFF3949AB);
const _green = Color(0xFF2E7D32);
const _gold = Color(0xFFF9A825);
const _pink = Color(0xFFD81B60);
const _cyan = Color(0xFF00838F);

// Explicit rather than generated: every entry describes a deliberate composition.
const List<_ListingCardPreset> _horizontalCardPresets = [
  _ListingCardPreset(
    accent: _orange,
    composition: 0,
    radius: 14,
    logo: _CardLogoStyle.square,
    specs: _CardSpecsStyle.chips,
    price: _CardPriceStyle.solid,
  ),
  _ListingCardPreset(
    accent: _blue,
    composition: 1,
    radius: 8,
    logo: _CardLogoStyle.circle,
    specs: _CardSpecsStyle.plain,
    price: _CardPriceStyle.outline,
    borderWidth: 1,
    elevation: 2,
    imageFlex: 4,
    accentEdge: true,
  ),
  _ListingCardPreset(
    accent: _teal,
    composition: 2,
    radius: 22,
    logo: _CardLogoStyle.soft,
    specs: _CardSpecsStyle.icons,
    price: _CardPriceStyle.solid,
    elevation: 14,
    imageFlex: 6,
    imageTrailing: true,
  ),
  _ListingCardPreset(
    accent: _purple,
    composition: 3,
    radius: 4,
    logo: _CardLogoStyle.none,
    specs: _CardSpecsStyle.outline,
    price: _CardPriceStyle.underline,
    borderWidth: 1,
    elevation: 0,
    imageFlex: 4,
  ),
  _ListingCardPreset(
    accent: _red,
    composition: 4,
    radius: 18,
    logo: _CardLogoStyle.circle,
    specs: _CardSpecsStyle.chips,
    price: _CardPriceStyle.plain,
    imageFlex: 5,
    imageTrailing: true,
    centered: true,
  ),
  _ListingCardPreset(
    accent: _indigo,
    composition: 0,
    radius: 26,
    logo: _CardLogoStyle.soft,
    specs: _CardSpecsStyle.outline,
    price: _CardPriceStyle.outline,
    elevation: 18,
    imageFlex: 4,
    accentEdge: true,
  ),
  _ListingCardPreset(
    accent: _green,
    composition: 1,
    radius: 12,
    logo: _CardLogoStyle.none,
    specs: _CardSpecsStyle.icons,
    price: _CardPriceStyle.solid,
    borderWidth: 1,
    elevation: 0,
    imageFlex: 6,
  ),
  _ListingCardPreset(
    accent: _gold,
    composition: 2,
    radius: 6,
    logo: _CardLogoStyle.square,
    specs: _CardSpecsStyle.plain,
    price: _CardPriceStyle.underline,
    elevation: 3,
    imageFlex: 4,
    imageTrailing: true,
  ),
  _ListingCardPreset(
    accent: _pink,
    composition: 3,
    radius: 20,
    logo: _CardLogoStyle.circle,
    specs: _CardSpecsStyle.chips,
    price: _CardPriceStyle.solid,
    imageFlex: 5,
    centered: true,
  ),
  _ListingCardPreset(
    accent: _cyan,
    composition: 4,
    radius: 10,
    logo: _CardLogoStyle.soft,
    specs: _CardSpecsStyle.outline,
    price: _CardPriceStyle.outline,
    borderWidth: 2,
    elevation: 0,
    imageFlex: 6,
    accentEdge: true,
  ),
  _ListingCardPreset(
    accent: _orange,
    composition: 1,
    radius: 24,
    logo: _CardLogoStyle.none,
    specs: _CardSpecsStyle.plain,
    price: _CardPriceStyle.plain,
    elevation: 16,
    imageFlex: 4,
    imageTrailing: true,
  ),
  _ListingCardPreset(
    accent: _blue,
    composition: 2,
    radius: 14,
    logo: _CardLogoStyle.square,
    specs: _CardSpecsStyle.icons,
    price: _CardPriceStyle.underline,
    borderWidth: 1,
    elevation: 0,
    imageFlex: 5,
  ),
  _ListingCardPreset(
    accent: _teal,
    composition: 3,
    radius: 30,
    logo: _CardLogoStyle.circle,
    specs: _CardSpecsStyle.outline,
    price: _CardPriceStyle.solid,
    elevation: 20,
    imageFlex: 6,
    imageTrailing: true,
  ),
  _ListingCardPreset(
    accent: _purple,
    composition: 4,
    radius: 8,
    logo: _CardLogoStyle.soft,
    specs: _CardSpecsStyle.chips,
    price: _CardPriceStyle.outline,
    borderWidth: 1,
    elevation: 2,
    imageFlex: 4,
  ),
  _ListingCardPreset(
    accent: _red,
    composition: 0,
    radius: 16,
    logo: _CardLogoStyle.none,
    specs: _CardSpecsStyle.icons,
    price: _CardPriceStyle.plain,
    imageFlex: 5,
    accentEdge: true,
    centered: true,
  ),
  _ListingCardPreset(
    accent: _indigo,
    composition: 2,
    radius: 5,
    logo: _CardLogoStyle.square,
    specs: _CardSpecsStyle.chips,
    price: _CardPriceStyle.solid,
    borderWidth: 2,
    elevation: 0,
    imageFlex: 4,
    imageTrailing: true,
  ),
  _ListingCardPreset(
    accent: _green,
    composition: 4,
    radius: 22,
    logo: _CardLogoStyle.circle,
    specs: _CardSpecsStyle.plain,
    price: _CardPriceStyle.underline,
    elevation: 12,
    imageFlex: 6,
  ),
  _ListingCardPreset(
    accent: _gold,
    composition: 3,
    radius: 12,
    logo: _CardLogoStyle.soft,
    specs: _CardSpecsStyle.icons,
    price: _CardPriceStyle.outline,
    borderWidth: 1,
    elevation: 5,
    imageFlex: 5,
    imageTrailing: true,
  ),
  _ListingCardPreset(
    accent: _pink,
    composition: 1,
    radius: 28,
    logo: _CardLogoStyle.none,
    specs: _CardSpecsStyle.outline,
    price: _CardPriceStyle.solid,
    elevation: 18,
    imageFlex: 4,
    centered: true,
  ),
  _ListingCardPreset(
    accent: _cyan,
    composition: 0,
    radius: 2,
    logo: _CardLogoStyle.square,
    specs: _CardSpecsStyle.plain,
    price: _CardPriceStyle.underline,
    borderWidth: 1,
    elevation: 0,
    imageFlex: 6,
    accentEdge: true,
  ),
];

const List<_ListingCardPreset> _gridCardPresets = [
  _ListingCardPreset(
    accent: _orange,
    composition: 0,
    radius: 20,
    logo: _CardLogoStyle.square,
    specs: _CardSpecsStyle.chips,
    price: _CardPriceStyle.solid,
  ),
  _ListingCardPreset(
    accent: _teal,
    composition: 2,
    radius: 8,
    logo: _CardLogoStyle.circle,
    specs: _CardSpecsStyle.plain,
    price: _CardPriceStyle.outline,
    borderWidth: 1,
    elevation: 1,
    imageScale: .82,
  ),
  _ListingCardPreset(
    accent: _blue,
    composition: 1,
    radius: 24,
    logo: _CardLogoStyle.soft,
    specs: _CardSpecsStyle.icons,
    price: _CardPriceStyle.solid,
    elevation: 16,
    imageScale: 1.12,
  ),
  _ListingCardPreset(
    accent: _purple,
    composition: 3,
    radius: 4,
    logo: _CardLogoStyle.none,
    specs: _CardSpecsStyle.outline,
    price: _CardPriceStyle.underline,
    borderWidth: 1,
    elevation: 0,
    imageScale: .9,
  ),
  _ListingCardPreset(
    accent: _red,
    composition: 4,
    radius: 18,
    logo: _CardLogoStyle.circle,
    specs: _CardSpecsStyle.chips,
    price: _CardPriceStyle.plain,
    centered: true,
    imageScale: 1.05,
  ),
  _ListingCardPreset(
    accent: _gold,
    composition: 0,
    radius: 30,
    logo: _CardLogoStyle.none,
    specs: _CardSpecsStyle.plain,
    price: _CardPriceStyle.solid,
    elevation: 20,
    imageScale: .78,
    accentEdge: true,
  ),
  _ListingCardPreset(
    accent: _indigo,
    composition: 2,
    radius: 12,
    logo: _CardLogoStyle.square,
    specs: _CardSpecsStyle.icons,
    price: _CardPriceStyle.outline,
    borderWidth: 2,
    elevation: 0,
    imageScale: 1.15,
  ),
  _ListingCardPreset(
    accent: _green,
    composition: 1,
    radius: 6,
    logo: _CardLogoStyle.soft,
    specs: _CardSpecsStyle.outline,
    price: _CardPriceStyle.underline,
    elevation: 3,
    imageScale: .88,
  ),
  _ListingCardPreset(
    accent: _pink,
    composition: 3,
    radius: 22,
    logo: _CardLogoStyle.circle,
    specs: _CardSpecsStyle.chips,
    price: _CardPriceStyle.solid,
    centered: true,
    imageScale: 1.08,
  ),
  _ListingCardPreset(
    accent: _cyan,
    composition: 4,
    radius: 10,
    logo: _CardLogoStyle.none,
    specs: _CardSpecsStyle.plain,
    price: _CardPriceStyle.outline,
    borderWidth: 1,
    elevation: 0,
    imageScale: .74,
    accentEdge: true,
  ),
  _ListingCardPreset(
    accent: _orange,
    composition: 2,
    radius: 26,
    logo: _CardLogoStyle.soft,
    specs: _CardSpecsStyle.outline,
    price: _CardPriceStyle.plain,
    elevation: 18,
    imageScale: .95,
  ),
  _ListingCardPreset(
    accent: _blue,
    composition: 4,
    radius: 14,
    logo: _CardLogoStyle.square,
    specs: _CardSpecsStyle.icons,
    price: _CardPriceStyle.solid,
    borderWidth: 1,
    elevation: 0,
    imageScale: 1.18,
  ),
  _ListingCardPreset(
    accent: _teal,
    composition: 3,
    radius: 32,
    logo: _CardLogoStyle.circle,
    specs: _CardSpecsStyle.plain,
    price: _CardPriceStyle.underline,
    elevation: 22,
    imageScale: .84,
  ),
  _ListingCardPreset(
    accent: _purple,
    composition: 0,
    radius: 7,
    logo: _CardLogoStyle.none,
    specs: _CardSpecsStyle.chips,
    price: _CardPriceStyle.outline,
    borderWidth: 2,
    elevation: 0,
    imageScale: 1.04,
  ),
  _ListingCardPreset(
    accent: _red,
    composition: 1,
    radius: 16,
    logo: _CardLogoStyle.square,
    specs: _CardSpecsStyle.outline,
    price: _CardPriceStyle.solid,
    centered: true,
    imageScale: .76,
  ),
  _ListingCardPreset(
    accent: _indigo,
    composition: 4,
    radius: 3,
    logo: _CardLogoStyle.soft,
    specs: _CardSpecsStyle.icons,
    price: _CardPriceStyle.plain,
    borderWidth: 1,
    elevation: 0,
    imageScale: 1.1,
    accentEdge: true,
  ),
  _ListingCardPreset(
    accent: _green,
    composition: 2,
    radius: 20,
    logo: _CardLogoStyle.none,
    specs: _CardSpecsStyle.plain,
    price: _CardPriceStyle.underline,
    elevation: 14,
    imageScale: .92,
  ),
  _ListingCardPreset(
    accent: _gold,
    composition: 3,
    radius: 11,
    logo: _CardLogoStyle.circle,
    specs: _CardSpecsStyle.chips,
    price: _CardPriceStyle.outline,
    borderWidth: 1,
    elevation: 4,
    imageScale: 1.14,
  ),
  _ListingCardPreset(
    accent: _pink,
    composition: 0,
    radius: 28,
    logo: _CardLogoStyle.soft,
    specs: _CardSpecsStyle.icons,
    price: _CardPriceStyle.solid,
    centered: true,
    elevation: 18,
    imageScale: .8,
  ),
  _ListingCardPreset(
    accent: _cyan,
    composition: 1,
    radius: 5,
    logo: _CardLogoStyle.square,
    specs: _CardSpecsStyle.outline,
    price: _CardPriceStyle.underline,
    borderWidth: 1,
    elevation: 0,
    imageScale: 1,
    accentEdge: true,
  ),
];

@visibleForTesting
int get horizontalListingCardPresetCount => _horizontalCardPresets.length;

@visibleForTesting
int get gridListingCardPresetCount => _gridCardPresets.length;

_ListingCardPreset _cardPreset(bool listLayout, int design) {
  final presets = listLayout ? _horizontalCardPresets : _gridCardPresets;
  return presets[(design.clamp(1, 20)) - 1];
}

Widget _buildPresetCardText(
  BuildContext context,
  Map car, {
  required _ListingCardPreset preset,
  required String brandId,
  required String trimLine,
  required String engineLine,
  required String yearDisplay,
  required String mileageDisplay,
  required String cityLine,
  required Color titleColor,
  required Color metaColor,
  required bool listLayout,
}) {
  final rtl = Directionality.of(context) == TextDirection.rtl;
  final light = Theme.of(context).brightness == Brightness.light;
  final title = localizedCarTitleForCard(context, car);
  final priceValue = tryParseCurrencyValue(car['price']);
  final price = priceValue == null ? '' : formatCurrency(context, car['price']);
  final details = [
    engineLine,
    trimLine,
  ].where((value) => value.isNotEmpty).toList();
  final specs = [
    yearDisplay,
    mileageDisplay,
  ].where((value) => value.isNotEmpty).toList();
  final align = preset.centered ? TextAlign.center : TextAlign.start;
  final cross = preset.centered
      ? CrossAxisAlignment.center
      : CrossAxisAlignment.stretch;

  Widget oneLine(
    String value, {
    Color? color,
    FontWeight? weight,
    double size = 12,
  }) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    style: TextStyle(
      color: color ?? metaColor,
      fontWeight: weight,
      fontSize: size,
      height: 1.1,
    ),
  );

  Widget logo() {
    if (preset.logo == _CardLogoStyle.none ||
        (car['brand']?.toString().trim().isEmpty ?? true)) {
      return const SizedBox.shrink();
    }
    final circular = preset.logo == _CardLogoStyle.circle;
    return Container(
      width: listLayout ? 27 : 25,
      height: listLayout ? 27 : 25,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: preset.logo == _CardLogoStyle.soft
            ? preset.accent.withValues(alpha: .12)
            : Colors.white,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular
            ? null
            : BorderRadius.circular(
                preset.logo == _CardLogoStyle.soft ? 10 : 4,
              ),
        border: Border.all(color: preset.accent.withValues(alpha: .35)),
      ),
      child: CachedNetworkImage(
        imageUrl: '${getApiBase()}/static/images/brands/$brandId.png',
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) =>
            Icon(Icons.directions_car, size: 16, color: preset.accent),
      ),
    );
  }

  final titleWidget = AutoSizeText(
    title,
    maxLines: 2,
    minFontSize: 9,
    stepGranularity: .25,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    style: TextStyle(
      color: titleColor,
      fontSize: listLayout ? 15 : 14,
      height: 1.1,
      fontWeight: preset.composition.isEven ? FontWeight.w800 : FontWeight.w700,
    ),
  );

  final titleRow = Row(
    mainAxisAlignment: preset.centered
        ? MainAxisAlignment.center
        : MainAxisAlignment.start,
    children: [
      logo(),
      if (preset.logo != _CardLogoStyle.none &&
          !(car['brand']?.toString().trim().isEmpty ?? true))
        const SizedBox(width: 6),
      Flexible(child: titleWidget),
      if (listLayout && preset.composition != 4) ...[
        const SizedBox(width: 2),
        _ListingCardFavoriteButton(car: car, idleColor: preset.accent),
      ],
    ],
  );

  Widget token(String value, {IconData? icon}) {
    final text = oneLine(value, size: listLayout ? 11.5 : 10.5);
    switch (preset.specs) {
      case _CardSpecsStyle.plain:
        return text;
      case _CardSpecsStyle.icons:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.tune, size: 12, color: preset.accent),
            const SizedBox(width: 3),
            Flexible(child: text),
          ],
        );
      case _CardSpecsStyle.outline:
      case _CardSpecsStyle.chips:
        return Container(
          constraints: const BoxConstraints(maxWidth: 115),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: preset.specs == _CardSpecsStyle.chips
                ? preset.accent.withValues(alpha: light ? .09 : .16)
                : Colors.transparent,
            border: preset.specs == _CardSpecsStyle.outline
                ? Border.all(color: preset.accent.withValues(alpha: .45))
                : null,
            borderRadius: BorderRadius.circular(
              preset.specs == _CardSpecsStyle.chips ? 8 : 3,
            ),
          ),
          child: text,
        );
    }
  }

  Widget tokenRow(List<String> values, {bool detail = false}) => Wrap(
    alignment: preset.centered ? WrapAlignment.center : WrapAlignment.start,
    spacing: 5,
    runSpacing: 4,
    children: [
      for (var i = 0; i < values.length; i++)
        token(
          values[i],
          icon: detail
              ? Icons.settings_outlined
              : (i == 0 ? Icons.calendar_today_outlined : Icons.speed),
        ),
    ],
  );

  Widget priceWidget() {
    if (price.isEmpty) return const SizedBox.shrink();
    final text = oneLine(
      price,
      color: preset.price == _CardPriceStyle.solid
          ? Colors.white
          : preset.accent,
      weight: FontWeight.w800,
      size: listLayout ? 14 : 13,
    );
    switch (preset.price) {
      case _CardPriceStyle.solid:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: preset.accent,
            borderRadius: BorderRadius.circular(preset.radius > 18 ? 20 : 7),
          ),
          child: FittedBox(fit: BoxFit.scaleDown, child: text),
        );
      case _CardPriceStyle.outline:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: preset.accent),
            borderRadius: BorderRadius.circular(5),
          ),
          child: FittedBox(fit: BoxFit.scaleDown, child: text),
        );
      case _CardPriceStyle.underline:
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: preset.accent, width: 2)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: text,
          ),
        );
      case _CardPriceStyle.plain:
        return text;
    }
  }

  final detailWidget = details.isEmpty ? null : tokenRow(details, detail: true);
  final specsWidget = specs.isEmpty ? null : tokenRow(specs);
  final locationWidget = cityLine.isEmpty
      ? null
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_outlined, size: 14, color: preset.accent),
            const SizedBox(width: 2),
            Flexible(child: oneLine(cityLine)),
          ],
        );
  final pricePresent = price.isNotEmpty;
  final footer = (locationWidget == null && !pricePresent)
      ? null
      : Row(
          children: [
            if (locationWidget != null) Expanded(child: locationWidget),
            if (locationWidget == null) const Spacer(),
            if (pricePresent) Flexible(child: priceWidget()),
          ],
        );

  final sections = <Widget>[];
  void add(Widget? widget) {
    if (widget == null) return;
    if (sections.isNotEmpty) sections.add(SizedBox(height: listLayout ? 4 : 5));
    sections.add(widget);
  }

  switch (preset.composition) {
    case 1:
      add(titleRow);
      if (pricePresent)
        add(
          Align(
            alignment: preset.centered
                ? Alignment.center
                : AlignmentDirectional.centerStart,
            child: priceWidget(),
          ),
        );
      add(specsWidget);
      add(detailWidget);
      add(locationWidget);
    case 2:
      add(titleRow);
      add(detailWidget);
      add(footer);
      add(specsWidget);
    case 3:
      add(titleRow);
      add(Container(height: 2, color: preset.accent.withValues(alpha: .7)));
      add(detailWidget);
      add(specsWidget);
      add(footer);
    case 4:
      add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: preset.accent.withValues(alpha: light ? .11 : .2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: titleRow,
        ),
      );
      add(specsWidget);
      add(detailWidget);
      add(footer);
    default:
      add(titleRow);
      add(detailWidget);
      add(specsWidget);
      add(footer);
  }

  return LayoutBuilder(
    builder: (context, constraints) {
      final content = Column(
        crossAxisAlignment: cross,
        mainAxisSize: MainAxisSize.min,
        children: sections,
      );
      return Align(
        alignment: preset.centered
            ? Alignment.topCenter
            : AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: content,
        ),
      );
    },
  );
}
