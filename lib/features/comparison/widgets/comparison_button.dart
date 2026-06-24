import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/i18n/legacy_inline_text.dart';
import '../../../shared/listings/listing_identity.dart';
import '../state/car_comparison_store.dart';

/// Reusable comparison toggle for listing detail and compact toolbars.
class ComparisonButton extends StatelessWidget {
  final Map<String, dynamic> car;
  final bool isCompact;

  const ComparisonButton({super.key, required this.car, this.isCompact = false});

  String? _carId() {
    final id = listingPrimaryId(car);
    return id.isEmpty ? null : id;
  }

  void _toggle(BuildContext context, CarComparisonStore store, bool inComparison) {
    final l = AppLocalizations.of(context)!;
    final id = _carId();
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            trLegacyText(
              context,
              'Cannot add to comparison',
              ar: 'تعذر الإضافة إلى المقارنة',
              ku: 'نەتوانرا زیاد بکرێت بۆ بەراوردن',
            ),
          ),
        ),
      );
      return;
    }

    if (inComparison) {
      Navigator.pushNamed(context, '/comparison');
      return;
    }

    if (!store.canAddMore) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.comparisonMaxLimit(5))),
      );
      return;
    }

    final normalized = Map<String, dynamic>.from(car);
    normalized['id'] = id;
    final publicId = (car['public_id'] ?? '').toString().trim();
    if (publicId.isNotEmpty) {
      normalized['public_id'] = publicId;
    }
    store.addCarToComparison(normalized);
    Navigator.pushNamed(context, '/comparison');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CarComparisonStore>();
    final l = AppLocalizations.of(context)!;
    final id = _carId();
    final inComparison = id != null && store.isCarInComparison(id);

    if (isCompact) {
      return IconButton(
        onPressed: () => _toggle(context, store, inComparison),
        tooltip: inComparison ? l.addedLabel : l.compareLabel,
        icon: Icon(
          inComparison ? Icons.compare_arrows : Icons.compare_arrows_outlined,
          size: 18,
          color: inComparison ? Theme.of(context).colorScheme.primary : null,
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: () => _toggle(context, store, inComparison),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFF6B00),
          side: const BorderSide(color: Color(0xFFFF6B00)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          minimumSize: const Size(0, 46),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        icon: Icon(
          inComparison ? Icons.compare_arrows : Icons.compare_arrows_outlined,
          size: 19,
        ),
        label: Text(
          inComparison ? l.addedLabel : l.compareLabel,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
