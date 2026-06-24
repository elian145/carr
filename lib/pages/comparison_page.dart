import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/widgets/global_listing_card.dart'
    show localizedCarTitleForCard, localizedTrimForCard;
import '../app/widgets/language_menu.dart';
import '../app/widgets/listing_network_image.dart';
import '../features/comparison/state/car_comparison_store.dart';
import '../l10n/app_localizations.dart';
import '../shared/debug/app_log.dart';
import '../shared/i18n/digits.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/i18n/listing_value_labels.dart';
import '../shared/i18n/locale_formatting.dart';
import '../shared/i18n/region_spec_labels.dart';
import '../shared/media/media_url.dart';
import '../theme_provider.dart';
import '../widgets/theme_toggle_widget.dart';

// Car Comparison Page

part 'comparison_page_helpers.dart';
part 'comparison_page_rows.dart';
part 'comparison_page_body.dart';

class CarComparisonPage extends StatelessWidget {
  const CarComparisonPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pageIsDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: pageIsDark ? null : AppThemes.lightAppBackground,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.specificationsLabel),
        elevation: 0,
        actions: [
          Semantics(
            button: true,
            label: AppLocalizations.of(context)!.shareAction,
            child: IconButton(
              tooltip: AppLocalizations.of(context)!.shareAction,
              onPressed: () async {
              try {
                final store = Provider.of<CarComparisonStore>(
                  context,
                  listen: false,
                );
                final cars = store.comparisonCars;
                final text = cars
                    .map(
                      (c) =>
                          '${c['title'] ?? ''} • ${c['year'] ?? ''} • ${c['price'] ?? ''}',
                    )
                    .join('\n');
                if (text.trim().isNotEmpty) {
                  SharePlus.instance.share(ShareParams(text: text));
                }
              } catch (e, st) { logNonFatal(e, st); }
            },
            icon: Icon(Icons.share_outlined),
            ),
          ),
          Consumer<CarComparisonStore>(
            builder: (context, comparisonStore, child) {
              if (comparisonStore.comparisonCount > 0) {
                return TextButton(
                  onPressed: () {
                    comparisonStore.clearComparison();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context)!.clearFilters,
                        ),
                        backgroundColor: Color(0xFFFF6B00),
                      ),
                    );
                  },
                  child: Text(
                    AppLocalizations.of(context)!.clearFilters,
                    style: TextStyle(color: Colors.white),
                  ),
                );
              }
              return SizedBox.shrink();
            },
          ),
          const ThemeToggleWidget(),
          buildLanguageMenu(),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: pageIsDark
                ? AppThemes.shellBackgroundDecoration(Brightness.dark)
                : const BoxDecoration(color: AppThemes.lightAppBackground),
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
}
