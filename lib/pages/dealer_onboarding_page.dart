import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../shared/debug/app_log.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/i18n/legacy_inline_text.dart';

class DealerOnboardingPage extends StatefulWidget {
  const DealerOnboardingPage({super.key});

  @override
  State<DealerOnboardingPage> createState() => _DealerOnboardingPageState();
}

class _DealerOnboardingPageState extends State<DealerOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _dealershipNameController = TextEditingController();
  final _dealershipPhoneController = TextEditingController();
  final _dealershipLocationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _registrationController = TextEditingController();
  final _documentUrlsController = TextEditingController();
  bool _initialized = false;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    final rawApplication = user?['dealer_application'];
    final application = rawApplication is Map
        ? Map<String, dynamic>.from(rawApplication)
        : <String, dynamic>{};
    _dealershipNameController.text =
        (application['dealership_name'] ?? user?['dealership_name'] ?? '')
            .toString();
    _dealershipPhoneController.text =
        (application['dealership_phone'] ?? user?['dealership_phone'] ?? '')
            .toString();
    _dealershipLocationController.text =
        (application['dealership_location'] ??
                user?['dealership_location'] ??
                '')
            .toString();
    _descriptionController.text = (application['dealership_description'] ?? '')
        .toString();
    _registrationController.text =
        (application['business_registration_number'] ?? '').toString();
    final documents = application['document_urls'];
    if (documents is List) {
      _documentUrlsController.text = documents.join('\n');
    }
  }

  @override
  void dispose() {
    _dealershipNameController.dispose();
    _dealershipPhoneController.dispose();
    _dealershipLocationController.dispose();
    _descriptionController.dispose();
    _registrationController.dispose();
    _documentUrlsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.saveDealerApplication({
        'submit': true,
        'dealership_name': _dealershipNameController.text.trim(),
        'dealership_phone': _dealershipPhoneController.text.trim(),
        'dealership_location': _dealershipLocationController.text.trim(),
        'dealership_description': _descriptionController.text.trim(),
        'business_registration_number': _registrationController.text.trim(),
        'document_urls': _documentUrlsController.text
            .split(RegExp(r'[\r\n,]+'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            trLegacyText(
              context,
              'Dealership details submitted. Your application is pending review.',
              ar: 'تم إرسال تفاصيل الوكالة. طلبك قيد المراجعة.',
              ku: 'وردەکاری ناوەندی فرۆشتن نێردرا. داواکارییەکەت لە چاوەڕوانی پێداچوونەوەیە.',
            ),
          ),
        ),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e, st) {
      if (!mounted) return;
      logNonFatal(e, st, 'DealerOnboardingPage.submit');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)!.error,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            trLegacyText(
              context,
              'Dealership details',
              ar: 'تفاصيل الوكالة',
              ku: 'وردەکاری ناوەندی فرۆشتن',
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  trLegacyText(
                    context,
                    'Tell us about your dealership to finish setting up your dealer account.',
                    ar: 'أخبرنا عن وكالتك لإكمال إعداد حساب الوكالة.',
                    ku: 'زانیاری دەربارەی ناوەندی فرۆشتنەکەت بنووسە بۆ تەواوکردنی هەژمارەکەت.',
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  trLegacyText(
                    context,
                    'Approval may take 1–2 business days.',
                    ar: 'قد تستغرق الموافقة من يوم إلى يومي عمل.',
                    ku: 'پەسەندکردن لەوانەیە ١–٢ ڕۆژی کار بخایەنێت.',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Builder(
                  builder: (context) {
                    final user = Provider.of<AuthService>(
                      context,
                      listen: false,
                    ).currentUser;
                    final rawApplication = user?['dealer_application'];
                    if (rawApplication is! Map) {
                      return const SizedBox.shrink();
                    }
                    final reason = (rawApplication['review_reason'] ?? '')
                        .toString()
                        .trim();
                    if (reason.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${trLegacyText(context, 'Changes requested', ar: 'التغييرات المطلوبة', ku: 'گۆڕانکارییە داواکراوەکان')}: $reason',
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _dealershipNameController,
                  decoration: InputDecoration(
                    labelText: trLegacyText(
                      context,
                      'Dealership name',
                      ar: 'اسم الوكالة',
                      ku: 'ناوی ناوەندی فرۆشتن',
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? loc.requiredField
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dealershipPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: trLegacyText(
                      context,
                      'Dealership phone',
                      ar: 'هاتف الوكالة',
                      ku: 'تەلەفۆنی ناوەندی فرۆشتن',
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? loc.requiredField
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dealershipLocationController,
                  decoration: InputDecoration(
                    labelText: trLegacyText(
                      context,
                      'Dealership location',
                      ar: 'موقع الوكالة',
                      ku: 'شوێنی ناوەندی فرۆشتن',
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? loc.requiredField
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: trLegacyText(
                      context,
                      'Dealership description',
                      ar: 'وصف الوكالة',
                      ku: 'وەسفی ناوەندی فرۆشتن',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _registrationController,
                  decoration: InputDecoration(
                    labelText: trLegacyText(
                      context,
                      'Business registration number',
                      ar: 'رقم تسجيل الشركة',
                      ku: 'ژمارەی تۆمارکردنی کۆمپانیا',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _documentUrlsController,
                  minLines: 2,
                  maxLines: 4,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: trLegacyText(
                      context,
                      'Verification document links',
                      ar: 'روابط مستندات التحقق',
                      ku: 'بەستەرەکانی بەڵگەنامەکانی پشتڕاستکردنەوە',
                    ),
                    helperText: trLegacyText(
                      context,
                      'One secure link per line',
                      ar: 'رابط آمن واحد في كل سطر',
                      ku: 'لە هەر دێڕێکدا یەک بەستەری پارێزراو',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          trLegacyText(
                            context,
                            'Submit dealership',
                            ar: 'إرسال تفاصيل الوكالة',
                            ku: 'ناردنی ناوەندی فرۆشتن',
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
