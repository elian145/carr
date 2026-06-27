part of 'home_flow.dart';

mixin _HomePageFilterBarBrand on _HomePageFilterLogic {
  Future<String?> _showHomeBrandPickerDialog(
    BuildContext context, {
    String? initialBrand,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? selected = initialBrand;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ResponsiveDialogBody(
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
                          onPressed: () => Navigator.pop(dialogContext, ''),
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
                    SizedBox(
                      height: AppResponsive.dialogScrollHeight(
                        context,
                        preferred: 380,
                      ),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: AppResponsive.pickerGridCrossAxisCount(
                            context,
                          ),
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: homeBrands.length,
                        itemBuilder: (context, index) {
                          final brand = homeBrands[index];
                          final isSelected = selected == brand;
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
                            onTap: () =>
                                Navigator.pop(dialogContext, brand),
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
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ResponsiveDialogBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        localizedBrand,
                        style: GoogleFonts.orbitron(
                          color: const Color(0xFFFF6B00),
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
                SizedBox(
                  height: AppResponsive.dialogScrollHeight(
                    context,
                    preferred: 380,
                  ),
                  child: modelList.isEmpty
                      ? Center(
                          child: Text(
                            AppLocalizations.of(context)!.pleaseSelectModel,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.separated(
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
    final brand = await _showHomeBrandPickerDialog(
      context,
      initialBrand: _homeSelectedBrand,
    );
    if (brand == null) return;
    setState(() {
      _homeSetSelectedBrand(brand.isEmpty ? null : brand);
      clearFiltersOnVehicleChange();
    });
    onFilterChanged();
  }
}
