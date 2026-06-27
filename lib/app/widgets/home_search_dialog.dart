import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/brand_logo_filenames.dart';
import '../../data/car_name_translations.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import '../../shared/ui/responsive.dart';
import '../app_api_base.dart';

// Search Dialog Widget
class HomeSearchDialog extends StatefulWidget {
  final Function(String) onBrandSelected;
  final Function(String, String) onModelSelected;
  final List<String> brands;
  final Map<String, List<String>> models;

  const HomeSearchDialog({
    super.key,
    required this.onBrandSelected,
    required this.onModelSelected,
    required this.brands,
    required this.models,
  });

  @override
  HomeSearchDialogState createState() => HomeSearchDialogState();
}

class HomeSearchDialogState extends State<HomeSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredBrands = [];
  List<Map<String, String>> _filteredModels = [];
  bool _isSearchingBrands = true;

  ButtonStyle _searchModeButtonStyle({required bool selected}) {
    final backgroundColor = selected
        ? const Color(0xFFFF6B00)
        : Colors.white.withValues(alpha: 0.12);
    final foregroundColor = selected ? Colors.white : Colors.white70;
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      disabledBackgroundColor: backgroundColor,
      disabledForegroundColor: foregroundColor,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _filteredBrands = List.from(widget.brands);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Rebuilds result lists from the current field text. In model mode, an empty
  /// query shows no rows (typing filters by model name, or by brand to narrow).
  void _rebuildFilteredLists() {
    final raw = _searchController.text.toLowerCase().trim();
    if (_isSearchingBrands) {
      _filteredBrands = widget.brands
          .where((brand) => brand.toLowerCase().contains(raw))
          .toList();
      return;
    }
    if (raw.isEmpty) {
      _filteredModels = [];
      return;
    }
    final seen = <String>{};
    _filteredModels = [];
    for (final brand in widget.brands) {
      final brandModels = widget.models[brand] ?? [];
      if (brand.toLowerCase().contains(raw)) {
        for (final model in brandModels) {
          final key = '$brand|$model';
          if (seen.add(key)) {
            _filteredModels.add({'brand': brand, 'model': model});
          }
        }
      }
      for (final model in brandModels) {
        if (model.toLowerCase().contains(raw)) {
          final key = '$brand|$model';
          if (seen.add(key)) {
            _filteredModels.add({'brand': brand, 'model': model});
          }
        }
      }
    }
    _filteredModels.sort((a, b) {
      final ma = a['model']!.toLowerCase();
      final mb = b['model']!.toLowerCase();
      final c = ma.compareTo(mb);
      if (c != 0) return c;
      return a['brand']!.toLowerCase().compareTo(b['brand']!.toLowerCase());
    });
  }

  void _onSearchChanged() {
    setState(_rebuildFilteredLists);
  }

  void _toggleSearchMode() {
    _searchController.removeListener(_onSearchChanged);
    setState(() {
      _isSearchingBrands = !_isSearchingBrands;
      _searchController.clear();
      _rebuildFilteredLists();
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ResponsiveDialogShell(
        preferredWidth: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  trLegacyText(
                    context,
                    'Search Cars',
                    ar: 'البحث عن السيارات',
                    ku: 'گەڕان بە دوای ئۆتۆمبێل',
                  ),
                  style: GoogleFonts.orbitron(
                    color: Color(0xFFFF6B00),
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(height: 20),

            // Search Toggle
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSearchingBrands ? null : _toggleSearchMode,
                    style: _searchModeButtonStyle(selected: _isSearchingBrands),
                    child: Text(
                      trLegacyText(
                        context,
                        'Search by Brand',
                        ar: 'بحث حسب العلامة',
                        ku: 'گەڕان بە براند',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSearchingBrands ? _toggleSearchMode : null,
                    style: _searchModeButtonStyle(selected: !_isSearchingBrands),
                    child: Text(
                      trLegacyText(
                        context,
                        'Search by Model',
                        ar: 'بحث حسب الموديل',
                        ku: 'گەڕان بە مۆدێل',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),

            // Search Field
            TextField(
              controller: _searchController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _isSearchingBrands
                    ? trLegacyText(
                        context,
                        'Search brands...',
                        ar: 'ابحث عن العلامات...',
                        ku: 'گەڕان بە براندەکان...',
                      )
                    : trLegacyText(
                        context,
                        'Search models...',
                        ar: 'ابحث عن الموديلات...',
                        ku: 'گەڕان بە مۆدێلەکان...',
                      ),
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Color(0xFFFF6B00)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Color(0xFFFF6B00), width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[800],
              ),
            ),
            SizedBox(height: 20),

            // Results
            Expanded(
              child: _isSearchingBrands
                  ? _buildBrandsList()
                  : _buildModelsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandsList() {
    return ListView.builder(
      itemCount: _filteredBrands.length,
      itemBuilder: (context, index) {
        final brand = _filteredBrands[index];
        final logoFile =
            brandLogoFilenames[brand] ??
            brand
                .toLowerCase()
                .replaceAll(' ', '-')
                .replaceAll('Ã©', 'e')
                .replaceAll('Ã¶', 'o');
        final logoUrl = '${getApiBase()}/static/images/brands/$logoFile.png';

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.all(4),
            child: CachedNetworkImage(
              imageUrl: logoUrl,
              placeholder: (context, url) => SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              errorWidget: (context, url, error) => Icon(
                Icons.directions_car,
                size: 24,
                color: Color(0xFFFF6B00),
              ),
              fit: BoxFit.contain,
            ),
          ),
          title: Text(
            CarNameTranslations.getLocalizedBrand(context, brand).isNotEmpty
                ? CarNameTranslations.getLocalizedBrand(context, brand)
                : brand,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          onTap: () => widget.onBrandSelected(brand),
        );
      },
    );
  }

  Widget _buildModelsList() {
    if (_filteredModels.isEmpty) {
      final emptyHint = _searchController.text.trim().isEmpty
          ? 'Type a model name to search. You can also type a brand to see all its models.'
          : 'No models match your search.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400], fontSize: 15),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _filteredModels.length,
      itemBuilder: (context, index) {
        final item = _filteredModels[index];
        final brand = item['brand']!;
        final model = item['model']!;
        final logoFile =
            brandLogoFilenames[brand] ??
            brand
                .toLowerCase()
                .replaceAll(' ', '-')
                .replaceAll('Ã©', 'e')
                .replaceAll('Ã¶', 'o');
        final logoUrl = '${getApiBase()}/static/images/brands/$logoFile.png';

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.all(4),
            child: CachedNetworkImage(
              imageUrl: logoUrl,
              placeholder: (context, url) => SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              errorWidget: (context, url, error) => Icon(
                Icons.directions_car,
                size: 24,
                color: Color(0xFFFF6B00),
              ),
              fit: BoxFit.contain,
            ),
          ),
          title: Text(
            CarNameTranslations.getLocalizedModel(
                  context,
                  brand,
                  model,
                ).isNotEmpty
                ? CarNameTranslations.getLocalizedModel(context, brand, model)
                : model,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            CarNameTranslations.getLocalizedBrand(context, brand).isNotEmpty
                ? CarNameTranslations.getLocalizedBrand(context, brand)
                : brand,
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          onTap: () => widget.onModelSelected(brand, model),
        );
      },
    );
  }
}
