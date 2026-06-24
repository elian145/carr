part of 'sell_flow.dart';

mixin _SellStep1Pickers on _SellStep1PickersTrim {
  Future<String?> _pickFromList(
    String title,
    List<String> options, {
    String? contextBrand,
  }) async {
    services.HapticFeedback.selectionClick();
    String query = '';
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final loc = AppLocalizations.of(context)!;
            final isYearPicker =
                title == loc.yearLabel || title.toLowerCase().contains('year');
            final normalizedQuery = query.trim().toLowerCase();
            final filtered = options.where((value) {
              if (isYearPicker) return true;
              if (normalizedQuery.isEmpty) return true;
              if (value.toLowerCase().contains(normalizedQuery)) return true;
              if (contextBrand != null) {
                final locModel = CarNameTranslations.getLocalizedModel(
                  context,
                  contextBrand,
                  value,
                ).toLowerCase();
                if (locModel.contains(normalizedQuery)) return true;
              }
              final locBrand = CarNameTranslations.getLocalizedBrand(
                context,
                value,
              ).toLowerCase();
              if (locBrand.contains(normalizedQuery)) return true;
              final translated = (_translateValueGlobal(context, value) ?? '')
                  .toLowerCase();
              return translated.contains(normalizedQuery);
            }).toList();
            return Dialog(
              backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 420,
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: Color(0xFFFF6B00),
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    if (!isYearPicker) ...[
                      TextField(
                        onChanged: (value) {
                          query = value;
                          setStateDialog(() {});
                        },
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _trLegacyText(
                            context,
                            'Search...',
                            ar: 'بحث...',
                            ku: 'گەڕان...',
                          ),
                          hintStyle: const TextStyle(color: Colors.white60),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white70,
                          ),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.2),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFFF6B00),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                    ],
                    SizedBox(
                      height: 400,
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final value = filtered[index];
                          final lowerTitle = title.toLowerCase();
                          final loc = AppLocalizations.of(context)!;
                          final isModelTitle = title == loc.modelLabel;
                          final isTrimTitle = title == loc.trimLabel;
                          final isBrandTitle = title == loc.brandLabel;
                          String displayText = value;
                          final bool isNumeric = RegExp(
                            r'^[0-9]+(\.[0-9]+)?$',
                          ).hasMatch(value);
                          if (lowerTitle.contains('price')) {
                            displayText = _formatCurrencyGlobal(context, value);
                          } else if (lowerTitle.contains('mileage') &&
                              isNumeric) {
                            final nf = _decimalFormatterGlobal(context);
                            displayText =
                                '${_localizeDigitsGlobal(context, nf.format(num.tryParse(value) ?? 0))} ${AppLocalizations.of(context)!.unit_km}';
                          } else if (lowerTitle.contains('year') && isNumeric) {
                            displayText = _localizeDigitsGlobal(context, value);
                          } else if (lowerTitle.contains('seating') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} ${_trLegacyText(context, 'seats', ar: 'مقاعد', ku: 'دانیشتن')}';
                          } else if (lowerTitle.contains('cylinder') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} ${_trLegacyText(context, 'cylinders', ar: 'أسطوانات', ku: 'سیلەندەر')}';
                          } else if (lowerTitle.contains('region') &&
                              isValidCarRegionSpecCode(value)) {
                            displayText =
                                carRegionSpecDisplayLabelLocalized(context, value);
                          } else if (lowerTitle.contains('engine') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} L';
                          } else if (value == 'Any') {
                            displayText = AppLocalizations.of(
                              context,
                            )!.anyOption;
                          } else if (isModelTitle && contextBrand != null) {
                            displayText =
                                CarNameTranslations.getLocalizedModel(
                                  context,
                                  contextBrand,
                                  value,
                                ).isNotEmpty
                                ? CarNameTranslations.getLocalizedModel(
                                    context,
                                    contextBrand,
                                    value,
                                  )
                                : value;
                          } else if (isTrimTitle) {
                            displayText = value;
                          } else if (isBrandTitle) {
                            displayText =
                                CarNameTranslations.getLocalizedBrand(
                                  context,
                                  value,
                                ).isNotEmpty
                                ? CarNameTranslations.getLocalizedBrand(
                                    context,
                                    value,
                                  )
                                : value;
                          } else {
                            final translated = _translateValueGlobal(
                              context,
                              value,
                            );
                            if (translated != null) displayText = translated;
                          }
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(context, value),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.06),
                                    Colors.white.withValues(alpha: 0.02),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayText,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _pickBrandModal() async {
    String query = '';
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final normalizedQuery = query.trim().toLowerCase();
            final filteredBrands = brands.where((brand) {
              if (normalizedQuery.isEmpty) return true;
              if (brand.toLowerCase().contains(normalizedQuery)) return true;
              final localized = CarNameTranslations.getLocalizedBrand(
                context,
                brand,
              ).toLowerCase();
              return localized.contains(normalizedQuery);
            }).toList();
            return Dialog(
              backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 480,
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.selectBrand,
                          style: TextStyle(
                            color: Color(0xFFFF6B00),
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    TextField(
                      onChanged: (value) {
                        query = value;
                        setStateDialog(() {});
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                          hintText: _trLegacyText(
                            context,
                            'Search...',
                            ar: 'بحث...',
                            ku: 'گەڕان...',
                          ),
                        hintStyle: const TextStyle(color: Colors.white60),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white70,
                        ),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.2),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFFF6B00),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    SizedBox(
                      height: 420,
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: BouncingScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: filteredBrands.length,
                        itemBuilder: (context, index) {
                          final brand = filteredBrands[index];
                          final logoFile = sellBrandSlug(brand);
                          final logoUrl =
                              '${getApiBase()}/static/images/brands/$logoFile.png';
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(context, brand),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              padding: EdgeInsets.all(6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    padding: EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: logoUrl,
                                      placeholder: (context, url) => SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Image.network(
                                            '${getApiBase()}/static/images/brands/default.png',
                                            fit: BoxFit.contain,
                                          ),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    CarNameTranslations.getLocalizedBrand(
                                          context,
                                          brand,
                                        ).isNotEmpty
                                        ? CarNameTranslations.getLocalizedBrand(
                                            context,
                                            brand,
                                          )
                                        : brand,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
