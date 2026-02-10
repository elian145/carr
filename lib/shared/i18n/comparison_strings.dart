import 'package:flutter/widgets.dart';

import 'digits.dart';

String removedFromComparisonText(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'تمت الإزالة من المقارنة';
  if (code == 'ku') return 'لە بەراوردن لابرا';
  return 'Removed from comparison';
}

String addedToComparisonText(BuildContext context, int count) {
  final code = Localizations.localeOf(context).languageCode;
  final cnt = localizeDigits(context, count.toString());
  final max = localizeDigits(context, '5');
  if (code == 'ar') return 'تمت الإضافة إلى المقارنة ($cnt/$max)';
  if (code == 'ku') return 'زیاد کرا بۆ بەراوردن ($cnt/$max)';
  return 'Added to comparison ($cnt/$max)';
}

String comparisonMaxLimitText(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  final five = localizeDigits(context, '5');
  if (code == 'ar') return 'يمكن مقارنة $five سيارات كحد أقصى';
  if (code == 'ku') return 'زۆرترین $five ئێنتەمبێل دەتوانرێت بەراورد بکرێن';
  return 'Maximum $five cars can be compared';
}

String compareLabel(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'قارن +';
  if (code == 'ku') return 'بەراوردکردن +';
  return 'compare +';
}

String addedLabel(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'تمت الإضافة';
  if (code == 'ku') return 'زیاد کرا';
  return 'Added';
}
