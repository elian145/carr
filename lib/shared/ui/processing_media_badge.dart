import 'package:flutter/material.dart';

/// Subtle, non-blocking "Processing media" pill -- same text/visual
/// language as `my_listings_page_widgets.dart`'s own card badge, extracted
/// here so the Car Details hero (which had no such indicator before the
/// optimistic-local-media fix) can show the identical badge without
/// duplicating the copy/styling. Deliberately never disables anything
/// beneath it -- the listing/media is fully usable the moment it exists;
/// this only informs.
class ProcessingMediaBadge extends StatelessWidget {
  const ProcessingMediaBadge({super.key});

  String _text(BuildContext context, String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  @override
  Widget build(BuildContext context) {
    final text = _text(
      context,
      'Processing media',
      ar: 'جارٍ معالجة الوسائط',
      ku: 'میدیا لە ئامادەکاریدایە',
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
