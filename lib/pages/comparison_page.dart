import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/widgets/global_listing_card.dart'
    show localizedCarTitleForCard, localizedTrimForCard;
import '../app/widgets/listing_network_image.dart';
import '../features/comparison/state/car_comparison_store.dart';
import '../l10n/app_localizations.dart';
import '../shared/debug/app_log.dart';
import '../shared/i18n/digits.dart';
import '../shared/i18n/listing_value_labels.dart';
import '../shared/i18n/locale_formatting.dart';
import '../shared/i18n/region_spec_labels.dart';
import '../shared/media/media_url.dart';
import '../theme_provider.dart';
import '../shared/i18n/legacy_inline_text.dart';

// Car Comparison Page

part 'comparison_page_helpers.dart';
part 'comparison_page_rows.dart';
part 'comparison_page_body_empty.dart';
part 'comparison_page_body_filled_header.dart';
part 'comparison_page_body_filled_table.dart';
part 'comparison_page_body_filled.dart';
part 'comparison_page_body.dart';

class CarComparisonPage extends StatelessWidget {
  const CarComparisonPage({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final isLightShell = brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLightShell ? AppThemes.lightAppBackground : null,
      appBar: AppBar(
        title: Text(loc.comparisonTitle),
        actions: [
          Consumer<CarComparisonStore>(
            builder: (context, comparisonStore, _) {
              if (comparisonStore.comparisonCount == 0) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: loc.shareAction,
                    child: IconButton(
                      tooltip: loc.shareAction,
                      onPressed: () => _shareComparison(context, comparisonStore),
                      icon: const Icon(Icons.share_outlined),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: loc.clearAll,
                    child: IconButton(
                      tooltip: loc.clearAll,
                      onPressed: () => _clearComparison(context, comparisonStore),
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(brightness),
          ),
          Consumer<CarComparisonStore>(
            builder: (context, comparisonStore, child) {
              return _buildComparisonBody(context, comparisonStore);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _shareComparison(
    BuildContext context,
    CarComparisonStore comparisonStore,
  ) async {
    try {
      final cars = comparisonStore.comparisonCars;
      final text = cars
          .map(
            (c) =>
                '${c['title'] ?? ''} • ${c['year'] ?? ''} • ${c['price'] ?? ''}',
          )
          .join('\n');
      if (text.trim().isNotEmpty) {
        await SharePlus.instance.share(ShareParams(text: text));
      }
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  void _clearComparison(BuildContext context, CarComparisonStore comparisonStore) {
    comparisonStore.clearComparison();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.comparisonCleared)),
    );
  }
}
