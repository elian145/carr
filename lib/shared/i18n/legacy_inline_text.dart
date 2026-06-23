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

String homeFeedLoadingListingsText(BuildContext context) {
  return trLegacyText(
    context,
    'Loading listings...',
    ar: 'جاري تحميل الإعلانات...',
    ku: 'بارکردنی ڕیکلامەکان...',
  );
}

String homeFeedSortingListingsText(BuildContext context) {
  return trLegacyText(
    context,
    'Sorting listings...',
    ar: 'جاري ترتيب الإعلانات...',
    ku: 'ڕیزکردنی ڕیکلامەکان...',
  );
}

String homeFeedNetworkErrorText(BuildContext context) {
  return trLegacyText(
    context,
    'Could not reach the server. Check your connection and try again.',
    ar: 'تعذر الوصول إلى الخادم. تحقق من الاتصال وحاول مرة أخرى.',
    ku: 'نەتوانرا پەیوەندی بە سێرڤەر بکرێت. پەیوەندییەکەت بپشکنە و دووبارە هەوڵ بدەرەوە.',
  );
}

String homeFeedServerErrorText(BuildContext context, String statusCode) {
  return trLegacyText(
    context,
    'Server error ($statusCode). Please try again later.',
    ar: 'خطأ في الخادم ($statusCode). يرجى المحاولة لاحقاً.',
    ku: 'هەڵەی سێرڤەر ($statusCode). تکایە دواتر دووبارە هەوڵ بدەرەوە.',
  );
}

String acceptTermsRequiredText(BuildContext context) {
  return trLegacyText(
    context,
    'Please accept the Terms and Privacy Policy',
    ar: 'يرجى الموافقة على الشروط وسياسة الخصوصية',
    ku: 'تکایە مەرج و سیاسەتی تایبەتمەندی قبوڵ بکە',
  );
}

String videoPlaybackFailedText(BuildContext context) {
  return trLegacyText(
    context,
    'Could not play this video.',
    ar: 'تعذر تشغيل هذا الفيديو.',
    ku: 'نەتوانرا ئەم ڤیدیۆیە لێ بدرێت.',
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
