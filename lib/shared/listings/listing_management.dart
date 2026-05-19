import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../shared/errors/user_error_text.dart';
import 'listing_events.dart' show ListingEvents, invalidateListingDiskCaches;
import 'listing_identity.dart';
import 'listing_to_sell_draft.dart';

/// Confirms deletion, calls API, shows errors. Returns true when deleted.
Future<bool> confirmAndDeleteListing(
  BuildContext context,
  String carId,
) async {
  if (carId.trim().isEmpty) return false;
  final loc = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(loc?.deleteListingTitle ?? 'Delete listing?'),
      content: Text(
        loc?.deleteListingBody ?? 'This will remove it from public listings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(loc?.cancelAction ?? 'Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            loc?.deleteAction ?? 'Delete',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  if (ok != true) return false;

  try {
    await ApiService.deleteCar(carId);
    ListingEvents.notifyDeleted(carId);
    await invalidateListingDiskCaches(carId);
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Listing removed')),
    );
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userErrorText(
            context,
            e,
            fallback: loc?.errorTitle ?? 'Error',
          ),
        ),
      ),
    );
    return false;
  }
}

/// Mark listing sold or available again. Returns updated car map on success.
Future<Map<String, dynamic>?> setListingSoldStatus(
  BuildContext context,
  String carId, {
  required bool sold,
}) async {
  if (carId.trim().isEmpty) return null;
  final loc = AppLocalizations.of(context);
  try {
    final res = sold
        ? await ApiService.markListingSold(carId)
        : await ApiService.markListingActive(carId);
    final car = res['car'];
    if (car is Map) {
      return Map<String, dynamic>.from(car.cast<String, dynamic>());
    }
    return <String, dynamic>{'status': sold ? 'sold' : 'active'};
  } catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userErrorText(
            context,
            e,
            fallback: loc?.errorTitle ?? 'Error',
          ),
        ),
      ),
    );
    return null;
  }
}

Future<bool> confirmMarkListingSold(BuildContext context) async {
  final loc = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        _soldDialogText(context, 'Mark as sold?', 'تحديد كمباع؟', 'وەک فرۆشراو نیشان بکەیت؟'),
      ),
      content: Text(
        _soldDialogText(
          context,
          'This keeps the listing visible with a SOLD badge. You can mark it available again later.',
          'سيبقى الإعلان ظاهراً مع شارة مُباع. يمكنك إعادته لاحقاً.',
          'ڕیکلامەکە بە نیشانی فرۆشراو دیار دەبێت. دواتر دەتوانیت بیگەڕێنیتەوە.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(loc?.cancelAction ?? 'Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            _soldDialogText(context, 'Mark sold', 'مباع', 'فرۆشراو'),
            style: const TextStyle(color: Color(0xFFFF6B00)),
          ),
        ),
      ],
    ),
  );
  return ok == true;
}

String _soldDialogText(
  BuildContext context,
  String en,
  String ar,
  String ku,
) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return ar;
  if (code == 'ku' || code == 'ckb') return ku;
  return en;
}

/// Opens the full sell wizard pre-filled for editing; returns updated car when saved.
Future<Map<String, dynamic>?> openEditListingPage(
  BuildContext context,
  Map<String, dynamic> car,
) async {
  final auth = Provider.of<AuthService>(context, listen: false);
  final snapshot = listingToSellDraftSnapshot(
    car,
    contactPhoneFallback: auth.userPhone,
  );

  final result = await Navigator.pushNamed(
    context,
    '/sell',
    arguments: {
      'draftSnapshot': snapshot,
      'editListing': true,
    },
  );

  if (result is Map) {
    final updated = result['car'];
    if (updated is Map<String, dynamic>) {
      return Map<String, dynamic>.from(updated);
    }
    if (updated is Map) {
      return Map<String, dynamic>.from(updated.cast<String, dynamic>());
    }
  }
  return null;
}

String listingTitleLabel(Map<String, dynamic> car) {
  final title = (car['title'] ?? '').toString().trim();
  if (title.isNotEmpty) return title;
  final brand = (car['brand'] ?? '').toString().trim();
  final model = (car['model'] ?? '').toString().trim();
  final year = (car['year'] ?? '').toString().trim();
  return [brand, model, year].where((s) => s.isNotEmpty).join(' ').trim();
}
