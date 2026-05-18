import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../errors/user_error_text.dart';

/// Shared report dialog for users and listings.
Future<void> showReportDialog(
  BuildContext context, {
  required String title,
  required Future<void> Function(String reason, String? details) onSubmit,
}) async {
  final reasonController = TextEditingController();
  final detailsController = TextEditingController();
  final loc = AppLocalizations.of(context);

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: _tr(context, 'Reason', ar: 'السبب', ku: 'هۆکار'),
                hintText: _tr(
                  context,
                  'e.g. spam, scam, inappropriate',
                  ar: 'مثال: احتيال، مضايقة',
                  ku: 'وەک: سپام، فێڵ',
                ),
                border: const OutlineInputBorder(),
              ),
              maxLength: 200,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: detailsController,
              decoration: InputDecoration(
                labelText: _tr(
                  context,
                  'Details (optional)',
                  ar: 'تفاصيل (اختياري)',
                  ku: 'وردەکاری (ئارەزوومەندانە)',
                ),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 2000,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(loc?.cancelAction ?? 'Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final reason = reasonController.text.trim();
            if (reason.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text(
                    _tr(
                      context,
                      'Please provide a reason',
                      ar: 'يرجى إدخال السبب',
                      ku: 'تکایە هۆکارێک بنووسە',
                    ),
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            Navigator.pop(ctx);
            try {
              await onSubmit(
                reason,
                detailsController.text.trim().isEmpty
                    ? null
                    : detailsController.text.trim(),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _tr(
                      context,
                      'Report submitted. Thank you.',
                      ar: 'تم إرسال البلاغ. شكراً لك.',
                      ku: 'ڕاپۆرتەکە نێردرا. سوپاس.',
                    ),
                  ),
                ),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    userErrorText(
                      context,
                      e,
                      fallback: loc?.errorTitle ?? 'Error',
                    ),
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: Text(
            _tr(
              context,
              'Submit Report',
              ar: 'إرسال البلاغ',
              ku: 'ناردنی ڕاپۆرت',
            ),
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    ),
  );

  reasonController.dispose();
  detailsController.dispose();
}

Future<void> showReportUserDialog(
  BuildContext context, {
  required String userPublicId,
  String? title,
}) {
  return showReportDialog(
    context,
    title: title ??
        _tr(
          context,
          'Report User',
          ar: 'الإبلاغ عن المستخدم',
          ku: 'ڕاپۆرتکردنی بەکارهێنەر',
        ),
    onSubmit: (reason, details) => ApiService.reportUser(
      userPublicId,
      reason: reason,
      details: details,
    ),
  );
}

Future<void> showReportListingDialog(
  BuildContext context, {
  required String listingId,
  String? title,
}) {
  return showReportDialog(
    context,
    title: title ??
        _tr(
          context,
          'Report Listing',
          ar: 'الإبلاغ عن الإعلان',
          ku: 'ڕاپۆرتکردنی ڕیکلام',
        ),
    onSubmit: (reason, details) => ApiService.reportListing(
      listingId,
      reason: reason,
      details: details,
    ),
  );
}

String _tr(BuildContext context, String en, {String? ar, String? ku}) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return ar ?? en;
  if (code == 'ku' || code == 'ckb') return ku ?? en;
  return en;
}
