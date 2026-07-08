import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/app_api_base.dart' show getApiBase;
import '../../data/brand_logo_filenames.dart';
import '../../data/car_name_translations.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import 'filter_card_sections.dart';

List<String> makeModelKeywordMatchedBrands(
  List<String> brands,
  String raw,
) {
  final q = raw.toLowerCase().trim();
  if (q.isEmpty) return const [];
  return brands.where((b) => b.toLowerCase().contains(q)).toList();
}

List<Map<String, String>> makeModelKeywordMatchedModels(
  List<String> brands,
  Map<String, List<String>> models,
  String raw,
) {
  final q = raw.toLowerCase().trim();
  if (q.isEmpty) return const [];
  final seen = <String>{};
  final results = <Map<String, String>>[];
  for (final brand in brands) {
    final brandModels = models[brand] ?? const <String>[];
    if (brand.toLowerCase().contains(q)) {
      for (final model in brandModels) {
        final key = '$brand|$model';
        if (seen.add(key)) {
          results.add({'brand': brand, 'model': model});
        }
      }
    }
    for (final model in brandModels) {
      if (model.toLowerCase().contains(q)) {
        final key = '$brand|$model';
        if (seen.add(key)) {
          results.add({'brand': brand, 'model': model});
        }
      }
    }
  }
  results.sort((a, b) {
    final modelCmp =
        a['model']!.toLowerCase().compareTo(b['model']!.toLowerCase());
    if (modelCmp != 0) return modelCmp;
    return a['brand']!.toLowerCase().compareTo(b['brand']!.toLowerCase());
  });
  return results;
}

String _brandLogoSlug(String brand) {
  return brandLogoFilenames[brand] ??
      brand.toLowerCase().replaceAll(' ', '-');
}

class MakeModelKeywordSearch extends StatefulWidget {
  const MakeModelKeywordSearch({
    super.key,
    required this.brands,
    required this.models,
    required this.onBrandSelected,
    required this.onModelSelected,
    this.controller,
    this.focusNode,
  });

  final List<String> brands;
  final Map<String, List<String>> models;
  final ValueChanged<String> onBrandSelected;
  final void Function(String brand, String model) onModelSelected;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<MakeModelKeywordSearch> createState() => _MakeModelKeywordSearchState();
}

class _MakeModelKeywordSearchState extends State<MakeModelKeywordSearch> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final bool _ownsController;
  late final bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _ownsFocusNode = widget.focusNode == null;
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: isLight ? const Color(0xFFE8E8ED) : Colors.white24,
      ),
    );
    return InputDecoration(
      hintText: trLegacyText(
        context,
        'Search make or model',
        ar: 'ابحث عن الماركة أو الموديل',
        ku: 'براند یان مۆدێل بگەڕێ',
      ),
      prefixIcon: const Icon(Icons.search, color: kFilterAccentColor),
      suffixIcon: _controller.text.trim().isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.clear, size: 20),
              color: kFilterAccentColor,
              onPressed: () {
                _controller.clear();
                setState(() {});
              },
            ),
      filled: true,
      fillColor: isLight ? const Color(0xFFF7F7F9) : Colors.white10,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kFilterAccentColor, width: 2),
      ),
    );
  }

  Widget _brandLogoCircle(String brand, {double size = 40}) {
    final slug = _brandLogoSlug(brand);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(6),
      child: CachedNetworkImage(
        imageUrl: '${getApiBase()}/static/images/brands/$slug.png',
        placeholder: (context, url) => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (context, url, error) => Icon(
          Icons.directions_car,
          size: size * 0.5,
          color: kFilterAccentColor,
        ),
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _resultsPanel(BuildContext context, String query) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final mutedColor = isLight ? const Color(0xFF6B6B6B) : Colors.white70;
    final brands = makeModelKeywordMatchedBrands(widget.brands, query);
    final modelHits =
        makeModelKeywordMatchedModels(widget.brands, widget.models, query);
    const maxResults = 10;
    final brandSlots = brands.take(maxResults).toList();
    final modelSlots =
        modelHits.take(maxResults - brandSlots.length).toList();

    if (brandSlots.isEmpty && modelSlots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          trLegacyText(
            context,
            'No makes or models match your search.',
            ar: 'لا توجد ماركات أو موديلات مطابقة.',
            ku: 'هیچ براند یان مۆدێلێک نەدۆزرایەوە.',
          ),
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
              leading: _brandLogoCircle(brand),
              title: Text(
                CarNameTranslations.getLocalizedBrand(context, brand)
                        .isNotEmpty
                    ? CarNameTranslations.getLocalizedBrand(context, brand)
                    : brand,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                trLegacyText(
                  context,
                  'Make',
                  ar: 'الماركة',
                  ku: 'براند',
                ),
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
              onTap: () {
                _controller.clear();
                _focusNode.unfocus();
                widget.onBrandSelected(brand);
                setState(() {});
              },
            ),
          for (final item in modelSlots)
            ListTile(
              dense: true,
              leading: _brandLogoCircle(item['brand']!),
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
                _controller.clear();
                _focusNode.unfocus();
                widget.onModelSelected(item['brand']!, item['model']!);
                setState(() {});
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.words,
          decoration: _fieldDecoration(context),
        ),
        if (query.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: _resultsPanel(context, query),
            ),
          ),
        ],
      ],
    );
  }
}
