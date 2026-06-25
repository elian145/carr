part of 'home_flow.dart';

mixin _HomePageFilterBarBrand on _HomePageFilterLogic {
  Future<List<String>?> _showHomeBrandMultiPickerDialog(
    BuildContext context, {
    required List<String> initialSelection,
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        final selected = Set<String>.from(initialSelection);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void toggle(String brand) {
              setDialogState(() {
                if (selected.contains(brand)) {
                  selected.remove(brand);
                } else {
                  selected.add(brand);
                }
              });
            }

            return Dialog(
              backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.selectBrand,
                            style: GoogleFonts.orbitron(
                              color: const Color(0xFFFF6B00),
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, <String>[]),
                          child: Text(
                            AppLocalizations.of(context)!.any,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                    if (selected.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _trLegacyText(
                            context,
                            '${selected.length} selected',
                            ar: '${selected.length} محدد',
                            ku: '${selected.length} هەڵبژێردراو',
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    SizedBox(
                      height: 380,
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: homeBrands.length,
                        itemBuilder: (context, index) {
                          final brand = homeBrands[index];
                          final isSelected = selected.contains(brand);
                          final logoFile =
                              brandLogoFilenames[brand] ??
                              brand
                                  .toLowerCase()
                                  .replaceAll(' ', '-')
                                  .replaceAll('Ã©', 'e')
                                  .replaceAll('Ã¶', 'o');
                          final logoUrl =
                              '${getApiBase()}/static/images/brands/$logoFile.png';
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => toggle(brand),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFFF6B00)
                                      : Colors.white24,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: logoUrl,
                                      placeholder: (context, url) =>
                                          const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          const Icon(
                                        Icons.directions_car,
                                        size: 22,
                                        color: Color(0xFFFF6B00),
                                      ),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
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
                                    style: GoogleFonts.orbitron(
                                      fontSize: 10,
                                      color: isSelected
                                          ? const Color(0xFFFF6B00)
                                          : Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          selected.toList(),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                        ),
                        child: Text(
                          _trLegacyText(
                            context,
                            'Apply',
                            ar: 'تطبيق',
                            ku: 'جێبەجێکردن',
                          ),
                        ),
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

  Future<String?> _showHomeModelPickerDialog(
    BuildContext context, {
    required String brand,
  }) {
    final modelList = models[brand] ?? const <String>[];
    final localizedBrand =
        CarNameTranslations.getLocalizedBrand(context, brand).isNotEmpty
            ? CarNameTranslations.getLocalizedBrand(context, brand)
            : brand;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _trLegacyText(
                              context,
                              'Select Model',
                              ar: 'اختر الموديل',
                              ku: 'مۆدێل هەڵبژێرە',
                            ),
                            style: GoogleFonts.orbitron(
                              color: const Color(0xFFFF6B00),
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            localizedBrand,
                            style: GoogleFonts.orbitron(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 380,
                  child: modelList.isEmpty
                      ? Center(
                          child: Text(
                            _trLegacyText(
                              context,
                              'No models found',
                              ar: 'لا توجد موديلات',
                              ku: 'هیچ مۆدێلێک نەدۆزرایەوە',
                            ),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: modelList.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final model = modelList[index];
                            final display =
                                CarNameTranslations.getLocalizedModel(
                                          context,
                                          brand,
                                          model,
                                        ).isNotEmpty
                                    ? CarNameTranslations.getLocalizedModel(
                                        context,
                                        brand,
                                        model,
                                      )
                                    : model;
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.pop(context, model),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(
                                  display,
                                  style: GoogleFonts.orbitron(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
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
  }

  Future<void> _pickHomeBrand(BuildContext context) async {
    final brands = await _showHomeBrandMultiPickerDialog(
      context,
      initialSelection: _homeSelectedBrands,
    );
    if (brands == null) return;
    setState(() {
      _homeSetSelectedBrands(brands);
      clearFiltersOnVehicleChange();
    });
    onFilterChanged();
  }

  String _homeBrandFilterLabel(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return homeFilterSummaryLabel(
      loc.any,
      _homeSelectedBrands,
      (brand) {
        final localized =
            CarNameTranslations.getLocalizedBrand(context, brand);
        return localized.isNotEmpty ? localized : brand;
      },
    );
  }
}
