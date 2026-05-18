import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/trust_config.dart';
import 'legal_document_page.dart';

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  TrustConfigData? _config;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await TrustConfig.load();
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _loading = false;
    });
  }

  String _tr(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Could not open link'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cfg = _config ?? const TrustConfigData();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.helpSupportTitle ?? _tr('Help & Support')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  _tr(
                    'How can we help?',
                    ar: 'كيف يمكننا مساعدتك؟',
                    ku: 'چۆن دەتوانین یارمەتیت بدەین؟',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _FaqSection(
                  title: _tr('Buying', ar: 'الشراء', ku: 'کڕین'),
                  items: [
                    _FaqItem(
                      q: _tr('How do I contact a seller?'),
                      a: _tr(
                        'Open a listing and use Call, WhatsApp, or Chat on the detail page.',
                      ),
                    ),
                    _FaqItem(
                      q: _tr('Are listings verified?'),
                      a: _tr(
                        'Dealers with an approved badge are reviewed by our team. Always inspect a vehicle in person before paying.',
                      ),
                    ),
                  ],
                ),
                _FaqSection(
                  title: _tr('Selling', ar: 'البيع', ku: 'فرۆشتن'),
                  items: [
                    _FaqItem(
                      q: _tr('How do I post a listing?'),
                      a: _tr(
                        'Sign in, tap Sell, and follow the steps to add photos, price, and details.',
                      ),
                    ),
                    _FaqItem(
                      q: _tr('How do I edit or delete my listing?'),
                      a: _tr(
                        'Open your listing from My Listings or the listing page (owner tools) to edit or delete.',
                      ),
                    ),
                  ],
                ),
                _FaqSection(
                  title: _tr('Dealers', ar: 'الوكلاء', ku: 'وەکیلەکان'),
                  items: [
                    _FaqItem(
                      q: _tr('How do I register as a dealer?'),
                      a: _tr(
                        'Choose dealer signup and submit your dealership details. Approval may take 1–2 business days.',
                      ),
                    ),
                  ],
                ),
                _FaqSection(
                  title: _tr('Payments', ar: 'المدفوعات', ku: 'پارەدان'),
                  items: [
                    _FaqItem(
                      q: _tr('Does the app handle payments?'),
                      a: _tr(
                        'Payments are arranged directly between buyer and seller. Never send money before seeing the vehicle.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _tr('Contact support', ar: 'اتصل بالدعم', ku: 'پەیوەندی بە پشتیوانی'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (cfg.supportEmail.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: Text(cfg.supportEmail),
                    subtitle: Text(_tr('Email')),
                    onTap: () => _openUrl('mailto:${cfg.supportEmail}'),
                  ),
                if (cfg.supportPhone.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: Text(cfg.supportPhone),
                    subtitle: Text(_tr('Phone')),
                    onTap: () => _openUrl('tel:${cfg.supportPhone}'),
                  ),
                if (cfg.supportWhatsapp.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.chat_outlined),
                    title: Text(_tr('WhatsApp')),
                    subtitle: Text(cfg.supportWhatsapp),
                    onTap: () {
                      final w = cfg.supportWhatsapp;
                      final uri = w.startsWith('http')
                          ? w
                          : 'https://wa.me/${w.replaceAll(RegExp(r'[^0-9]'), '')}';
                      _openUrl(uri);
                    },
                  ),
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(_tr('Terms of Service')),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LegalDocumentPage(
                        document: LegalDocument.terms,
                        externalUrl: cfg.termsUrl,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(_tr('Privacy Policy')),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LegalDocumentPage(
                        document: LegalDocument.privacy,
                        externalUrl: cfg.privacyUrl,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FaqSection extends StatelessWidget {
  const _FaqSection({required this.title, required this.items});

  final String title;
  final List<_FaqItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...items.map(
          (e) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              title: Text(e.q, style: const TextStyle(fontWeight: FontWeight.w600)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(e.a),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FaqItem {
  const _FaqItem({required this.q, required this.a});
  final String q;
  final String a;
}
