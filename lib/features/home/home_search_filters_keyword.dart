part of 'home_flow.dart';

mixin _HomePageSearchFiltersKeyword on _HomePageSearchFiltersFields {
  InputDecoration _searchKeywordFieldDecoration(
    BuildContext context,
    StateSetter setStateDialog,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: isLight ? const Color(0xFFE8E8ED) : Colors.white24,
      ),
    );
    return InputDecoration(
      hintText: AppLocalizations.of(context)!.searchMakeOrModel,
      prefixIcon: const Icon(Icons.search, color: _searchAccent),
      suffixIcon: _searchFiltersKeywordController.text.trim().isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.clear, size: 20),
              color: _searchAccent,
              onPressed: () {
                _searchFiltersKeywordController.clear();
                setStateDialog(() {});
              },
            ),
      filled: true,
      fillColor: isLight ? const Color(0xFFF7F7F9) : Colors.white10,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _searchAccent, width: 2),
      ),
    );
  }

  Widget _searchKeywordResultsPanel(
    BuildContext context,
    StateSetter setStateDialog,
    String query,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final mutedColor = isLight ? const Color(0xFF6B6B6B) : Colors.white70;
    final brands = _searchKeywordMatchedBrands(query);
    final modelHits = _searchKeywordMatchedModels(query);
    const maxResults = 10;
    final brandSlots = brands.take(maxResults).toList();
    final modelSlots = modelHits.take(maxResults - brandSlots.length).toList();

    if (brandSlots.isEmpty && modelSlots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          AppLocalizations.of(context)!.noMakesOrModelsMatchYourSearch,
          style: TextStyle(color: mutedColor, fontSize: 14),
        ),
      );
    }

    return Material(
      color: isLight ? Colors.white : Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final brand in brandSlots)
            ListTile(
              dense: true,
              leading: _searchBrandLogoCircle(brand),
              title: Text(
                CarNameTranslations.getLocalizedBrand(context, brand).isNotEmpty
                    ? CarNameTranslations.getLocalizedBrand(context, brand)
                    : brand,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                AppLocalizations.of(context)!.make,
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
              onTap: () {
                setState(() {
                  _homeSetSelectedBrand(brand);
                  clearFiltersOnVehicleChange();
                  _searchFiltersKeywordController.clear();
                  _searchFiltersKeywordFocusNode.unfocus();
                });
                setStateDialog(() {});
              },
            ),
          for (final item in modelSlots)
            ListTile(
              dense: true,
              leading: _searchBrandLogoCircle(item['brand']!),
              title: Text(
                item['model']!,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                CarNameTranslations.getLocalizedBrand(
                          context,
                          item['brand']!,
                        ).isNotEmpty
                    ? CarNameTranslations.getLocalizedBrand(
                        context,
                        item['brand']!,
                      )
                    : item['brand']!,
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
              onTap: () {
                setState(() {
                  _homeSetSelectedBrand(item['brand']);
                  selectedModel = item['model'];
                  selectedTrim = null;
                  clearFiltersOnVehicleChange();
                  _searchFiltersKeywordController.clear();
                  _searchFiltersKeywordFocusNode.unfocus();
                });
                setStateDialog(() {});
              },
            ),
        ],
      ),
    );
  }

  Widget _searchKeywordField(
    BuildContext context,
    StateSetter setStateDialog, {
    bool autofocus = false,
  }) {
    final query = _searchFiltersKeywordController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchFiltersKeywordController,
          focusNode: _searchFiltersKeywordFocusNode,
          autofocus: autofocus,
          onChanged: (_) => setStateDialog(() {}),
          textInputAction: TextInputAction.search,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.words,
          enableInteractiveSelection: true,
          decoration: _searchKeywordFieldDecoration(context, setStateDialog),
        ),
        if (query.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: _searchKeywordResultsPanel(
                context,
                setStateDialog,
                query,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
