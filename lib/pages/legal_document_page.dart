import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum LegalDocument { terms, privacy }

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({
    super.key,
    required this.document,
    this.externalUrl = '',
  });

  final LegalDocument document;
  final String externalUrl;

  String _tr(BuildContext context, String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  String _title(BuildContext context) {
    return document == LegalDocument.terms
        ? _tr(context, 'Terms of Service', ar: 'شروط الخدمة', ku: 'مەرجەکانی خزمەتگوزاری')
        : _tr(context, 'Privacy Policy', ar: 'سياسة الخصوصية', ku: 'سیاسەتی تایبەتمەندی');
  }

  String _body(BuildContext context) {
    if (document == LegalDocument.terms) {
      return _tr(
        context,
        'By using this app you agree to list and browse vehicles responsibly, '
        'provide accurate information, and comply with local laws. We may remove '
        'listings or accounts that violate our policies. Fees and promotions may '
        'change with notice where required by law.\n\n'
        'For the full terms, tap “Open in browser” below.',
        ar: 'باستخدام هذا التطبيق فإنك توافق على نشر الإعلانات والتصفح بمسؤولية '
            'وتقديم معلومات دقيقة والامتثال للقوانين المحلية. قد نزيل الإعلانات أو '
            'الحسابات التي تنتهك سياساتنا.',
        ku: 'بە بەکارهێنانی ئەم ئەپە ڕازیت بە بەرپرسیارانە ڕیکلام بکەیت و بگەڕێیت '
            'و زانیاری دروست بدەیت و یاسای ناوخۆ ڕەچاو بکەیت.',
      );
    }
    return _tr(
      context,
      'We collect account and listing data needed to operate the marketplace, '
      'including contact details you provide, device tokens for notifications, '
      'and usage analytics to improve the service. We do not sell your personal '
      'data. You may request account deletion from Settings.\n\n'
      'For the full privacy policy, tap “Open in browser” below.',
      ar: 'نجمع بيانات الحساب والإعلانات اللازمة لتشغيل السوق، بما في ذلك '
          'بيانات الاتصال ورموز الإشعارات والتحليلات لتحسين الخدمة. لا نبيع بياناتك الشخصية.',
      ku: 'ئێمە داتای هەژمار و ڕیکلام کۆدەکەینەوە بۆ کارپێکردنی بازاڕەکە. '
          'داتای کەسیت نافروشین.',
    );
  }

  Future<void> _openExternal(BuildContext context) async {
    final url = externalUrl.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(context, 'Could not open link', ar: 'تعذر فتح الرابط', ku: 'نەتوانرا بەستەر بکرێتەوە'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = externalUrl.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(_title(context))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (hasUrl)
            FilledButton.icon(
              onPressed: () => _openExternal(context),
              icon: const Icon(Icons.open_in_browser),
              label: Text(
                _tr(
                  context,
                  'Open in browser',
                  ar: 'فتح في المتصفح',
                  ku: 'کردنەوە لە وێبگەڕ',
                ),
              ),
            ),
          if (hasUrl) const SizedBox(height: 20),
          Text(_body(context), style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
