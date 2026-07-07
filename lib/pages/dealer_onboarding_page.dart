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
  bool _loading = false;

  @override
  void dispose() {
    _dealershipNameController.dispose();
    _dealershipPhoneController.dispose();
    _dealershipLocationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.updateProfile({
        'is_dealer': true,
        'dealership_name': _dealershipNameController.text.trim(),
        'dealership_phone': _dealershipPhoneController.text.trim(),
        'dealership_location': _dealershipLocationController.text.trim(),
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
