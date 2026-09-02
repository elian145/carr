part of 'sell_flow.dart';

mixin _SellStep2BuildAppearance on _SellStep2BuildCore {
  List<Widget> _sellStep2BuildAppearanceSection() {
    final loc = AppLocalizations.of(context)!;

    return [
      FilterIconCardSection(
        title: loc.bodyTypeLabel,
        options: getAvailableBodyTypes(),
        selected: selectedBodyType,
        requiredField: true,
        isError: errBodyType,
        scrollHorizontally: true,
        tileWidth: 100,
        tileImageWidth: 52,
        tileImageHeight: 40,
        tileImageBorderRadius: 8,
        imageAssetForOption: body_type_assets.bodyTypeImageAsset,
        labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
        onSelected: (value) {
          setState(() {
            selectedBodyType = value;
            _syncStep2ToOnlineVariant({'body'});
          });
          _syncStep2DraftToParent();
        },
        onClear: selectedBodyType != null
            ? () {
                setState(() => selectedBodyType = null);
                _syncStep2DraftToParent();
              }
            : null,
      ),
      FilterColorField(
        colors: getAvailableColors(),
        selectedColor: selectedColor,
        requiredField: true,
        isError: errColor,
        labelForColor: (ctx, color) =>
            _translateValueGlobal(ctx, color) ?? color,
        onColorSelected: (value) {
          setState(() => selectedColor = value);
          _syncStep2DraftToParent();
        },
        onClear: selectedColor != null
            ? () {
                setState(() => selectedColor = null);
                _syncStep2DraftToParent();
              }
            : null,
      ),
    ];
  }
}
