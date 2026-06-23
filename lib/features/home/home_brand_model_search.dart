import 'package:flutter/material.dart';

import '../../app/widgets/home_search_dialog.dart';

/// Opens brand/model search used from the home filter bar.
void showHomeBrandModelSearchDialog({
  required BuildContext context,
  required List<String> brands,
  required Map<String, List<String>> models,
  required void Function(String brand) onBrandSelected,
  required void Function(String brand, String model) onModelSelected,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => HomeSearchDialog(
      brands: brands,
      models: models,
      onBrandSelected: (brand) {
        onBrandSelected(brand);
        Navigator.pop(dialogContext);
      },
      onModelSelected: (brand, model) {
        onModelSelected(brand, model);
        Navigator.pop(dialogContext);
      },
    ),
  );
}
