import 'package:flutter/widgets.dart';

/// Lightweight helpers for translating UI snippets not covered by [AppLocalizations].
String trLegacyText(
  BuildContext context,
  String en, {
  String? ar,
  String? ku,
}) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return ar ?? en;
  if (code == 'ku' || code == 'ckb') return ku ?? en;
  return en;
}

String yesText(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'نعم';
  if (code == 'ku') return 'بەڵێ';
  return 'Yes';
}

String noText(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'لا';
  if (code == 'ku') return 'نەخێر';
  return 'No';
}

String pleaseSelectPhotoText(BuildContext context) {
  return trLegacyText(
    context,
    'Please select at least one photo',
    ar: 'يرجى اختيار صورة واحدة على الأقل',
    ku: 'تکایە لانیکەم یەک وێنە هەڵبژێرە',
  );
}

String listingSubmittedSuccessText(BuildContext context) {
  return trLegacyText(
    context,
    'Listing submitted successfully!',
    ar: 'تم إرسال الإعلان بنجاح!',
    ku: 'ڕیکلام بە سەرکەوتوویی نێردرا!',
  );
}

String couldNotLoadListingsText(BuildContext context) {
  return trLegacyText(
    context,
    'Could not load listings',
    ar: 'تعذر تحميل الإعلانات',
    ku: 'نەتوانرا ڕیکلامەکان باربکرێن',
  );
}

String photosUploadedText(BuildContext context) {
  return trLegacyText(
    context,
    'Photos uploaded',
    ar: 'تم تحميل الصور',
    ku: 'وێنەکان بارکران',
  );
}
