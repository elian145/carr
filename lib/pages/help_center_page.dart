import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../navigation/app_page_route.dart';
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
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final cfg = await TrustConfig.load();
      if (!mounted) return;
      setState(() {
        _config = cfg;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _config = const TrustConfigData();
        _loadError = AppLocalizations.of(context)!.error;
        _loading = false;
      });
    }
  }

  Future<void> _openUrl(String url) async {
    final loc = AppLocalizations.of(context);
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc?.helpCouldNotOpenLink ?? 'Could not open link'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final cfg = _config ?? const TrustConfigData();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.helpSupportTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MaterialBanner(
                      content: Text(_loadError!),
                      actions: [
                        TextButton(onPressed: _load, child: Text(loc.retryAction)),
                      ],
                    ),
                  ),
                Text(
                  loc.helpHowCanWeHelp,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _FaqSection(
                  title: loc.helpBuyingSection,
                  items: [
                    _FaqItem(
                      q: loc.helpFaqContactSellerQuestion,
                      a: loc.helpFaqContactSellerAnswer,
                    ),
                    _FaqItem(
                      q: loc.helpFaqListingsVerifiedQuestion,
                      a: loc.helpFaqListingsVerifiedAnswer,
                    ),
                  ],
                ),
                _FaqSection(
                  title: loc.helpSellingSection,
                  items: [
                    _FaqItem(
                      q: loc.helpFaqPostListingQuestion,
                      a: loc.helpFaqPostListingAnswer,
                    ),
                    _FaqItem(
                      q: loc.helpFaqEditDeleteListingQuestion,
                      a: loc.helpFaqEditDeleteListingAnswer,
                    ),
                  ],
                ),
                _FaqSection(
                  title: loc.helpDealersSection,
                  items: [
                    _FaqItem(
                      q: loc.helpFaqRegisterDealerQuestion,
                      a: loc.helpFaqRegisterDealerAnswer,
                    ),
                  ],
                ),
                _FaqSection(
                  title: loc.helpPaymentsSection,
                  items: [
                    _FaqItem(
                      q: loc.helpFaqPaymentsQuestion,
                      a: loc.helpFaqPaymentsAnswer,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  loc.helpContactSupport,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (cfg.supportEmail.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: Text(cfg.supportEmail),
                    subtitle: Text(loc.emailLabel),
                    onTap: () => _openUrl('mailto:${cfg.supportEmail}'),
                  ),
                if (cfg.supportPhone.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: Text(cfg.supportPhone),
                    subtitle: Text(loc.phoneLabel),
                    onTap: () => _openUrl('tel:${cfg.supportPhone}'),
                  ),
                if (cfg.supportWhatsapp.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.chat_outlined),
                    title: Text(loc.whatsappAction),
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
                  title: Text(loc.termsOfServiceTitle),
                  onTap: () => Navigator.push(
                    context,
                    AppPageRoute(
                      builder: (_) => LegalDocumentPage(
                        document: LegalDocument.terms,
                        externalUrl: cfg.termsUrl,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(loc.privacyPolicyTitle),
                  onTap: () => Navigator.push(
                    context,
                    AppPageRoute(
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
    final textAlign = Directionality.of(context) == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.left;

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
              title: Text(
                e.q,
                textAlign: textAlign,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(e.a, textAlign: textAlign),
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
