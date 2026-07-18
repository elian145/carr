import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  XFile? _businessPhoto;
  Uint8List? _businessPhotoBytes;
  bool _hasExistingVerificationPhoto = false;
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
    _hasExistingVerificationPhoto =
        application['has_verification_photo'] == true;
  }

  @override
  void dispose() {
    _dealershipNameController.dispose();
    _dealershipPhoneController.dispose();
    _dealershipLocationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickBusinessPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1000,
        imageQuality: 88,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _businessPhoto = picked;
        _businessPhotoBytes = bytes;
      });
    } catch (e, st) {
      if (!mounted) return;
      logNonFatal(e, st, 'DealerOnboardingPage.pickBusinessPhoto');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: trLegacyText(
                context,
                'Unable to select that photo.',
                ar: 'تعذر اختيار هذه الصورة.',
                ku: 'نەتوانرا ئەم وێنەیە هەڵبژێردرێت.',
              ),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_businessPhoto == null && !_hasExistingVerificationPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            trLegacyText(
              context,
              'Please upload a clear photo of your business.',
              ar: 'يرجى رفع صورة واضحة لنشاطك التجاري.',
              ku: 'تکایە وێنەیەکی ڕوونی شوێنی بازرگانییەکەت باربکە.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final applicationData = <String, dynamic>{
        'submit': true,
        'dealership_name': _dealershipNameController.text.trim(),
        'dealership_phone': _dealershipPhoneController.text.trim(),
        'dealership_location': _dealershipLocationController.text.trim(),
        'dealership_description': _descriptionController.text.trim(),
        'business_registration_number': '',
        'document_urls': const <String>[],
      };
      if (_businessPhoto != null) {
        await authService.saveDealerApplication({
          ...applicationData,
          'submit': false,
        });
        await authService.uploadDealerVerificationPhoto(_businessPhoto!);
      }
      await authService.saveDealerApplication(applicationData);
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

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    required IconData icon,
    String? hint,
    String? helper,
    bool required = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: required ? '$label *' : label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      prefixIcon: Icon(icon, color: colors.primary),
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.42),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.error, width: 2),
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: colors.primary, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _businessPhotoPlaceholder(BuildContext context, ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 46, color: colors.primary),
            const SizedBox(height: 10),
            Text(
              trLegacyText(
                context,
                'Add a photo that helps us verify this dealership',
                ar: 'أضف صورة تساعدنا في التحقق من هذه الوكالة',
                ku: 'وێنەیەک زیاد بکە کە یارمەتیمان بدات ئەم ناوەندی فرۆشتنە پشتڕاست بکەینەوە',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _uploadedPhotoPlaceholder(BuildContext context, ColorScheme colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 48, color: colors.primary),
          const SizedBox(height: 10),
          Text(
            trLegacyText(
              context,
              'Private dealership photo uploaded',
              ar: 'تم رفع صورة الوكالة الخاصة',
              ku: 'وێنەی نهێنی ناوەندی فرۆشتن بارکرا',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    final rawApplication = user?['dealer_application'];
    final reviewReason = rawApplication is Map
        ? (rawApplication['review_reason'] ?? '').toString().trim()
        : '';

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          elevation: 0,
          title: Text(
            trLegacyText(
              context,
              'Create dealership account',
              ar: 'إنشاء حساب وكالة',
              ku: 'دروستکردنی هەژماری ناوەندی فرۆشتن',
            ),
          ),
        ),
        body: Container(
          color: colors.surfaceContainerLowest,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colors.primary,
                            Color.lerp(colors.primary, Colors.black, 0.24)!,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.25),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.verified_user_outlined,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  trLegacyText(
                                    context,
                                    'Final setup step',
                                    ar: 'الخطوة الأخيرة للإعداد',
                                    ku: 'کۆتا هەنگاوی ڕێکخستن',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            trLegacyText(
                              context,
                              'Build your dealership presence',
                              ar: 'أنشئ حضور وكالتك',
                              ku: 'ناسنامەی ناوەندی فرۆشتنەکەت دروست بکە',
                            ),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            trLegacyText(
                              context,
                              'Add accurate business details so buyers can trust and contact your dealership.',
                              ar: 'أضف معلومات دقيقة عن نشاطك ليتمكن المشترون من الوثوق بوكالتك والتواصل معها.',
                              ku: 'زانیاری وردی بازرگانی زیاد بکە بۆ ئەوەی کڕیاران متمانەت پێ بکەن و پەیوەندیت پێوە بکەن.',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.88),
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  trLegacyText(
                                    context,
                                    'Review usually takes 1–2 business days',
                                    ar: 'تستغرق المراجعة عادةً من يوم إلى يومي عمل',
                                    ku: 'پێداچوونەوە زۆرجار ١–٢ ڕۆژی کار دەخایەنێت',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (reviewReason.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colors.error.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: colors.onErrorContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    trLegacyText(
                                      context,
                                      'Changes requested',
                                      ar: 'التغييرات المطلوبة',
                                      ku: 'گۆڕانکارییە داواکراوەکان',
                                    ),
                                    style: TextStyle(
                                      color: colors.onErrorContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    reviewReason,
                                    style: TextStyle(
                                      color: colors.onErrorContainer,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _sectionCard(
                      context,
                      icon: Icons.storefront_rounded,
                      title: trLegacyText(
                        context,
                        'Business information',
                        ar: 'معلومات النشاط',
                        ku: 'زانیاری بازرگانی',
                      ),
                      subtitle: trLegacyText(
                        context,
                        'These details will appear on your public dealership profile.',
                        ar: 'ستظهر هذه المعلومات في الملف العام لوكالتك.',
                        ku: 'ئەم زانیارییانە لە پڕۆفایلی گشتی ناوەندەکەت دەردەکەون.',
                      ),
                      children: [
                        TextFormField(
                          controller: _dealershipNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _fieldDecoration(
                            context,
                            label: trLegacyText(
                              context,
                              'Dealership name',
                              ar: 'اسم الوكالة',
                              ku: 'ناوی ناوەندی فرۆشتن',
                            ),
                            hint: trLegacyText(
                              context,
                              'Your registered or trading name',
                              ar: 'الاسم المسجل أو التجاري',
                              ku: 'ناوی تۆمارکراو یان بازرگانی',
                            ),
                            icon: Icons.badge_outlined,
                            required: true,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? loc.requiredField
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _dealershipPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: _fieldDecoration(
                            context,
                            label: trLegacyText(
                              context,
                              'Business phone',
                              ar: 'هاتف النشاط',
                              ku: 'تەلەفۆنی بازرگانی',
                            ),
                            hint: trLegacyText(
                              context,
                              'A number buyers can reach',
                              ar: 'رقم يمكن للمشترين التواصل معه',
                              ku: 'ژمارەیەک کە کڕیاران بتوانن پەیوەندی پێوە بکەن',
                            ),
                            icon: Icons.phone_outlined,
                            required: true,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? loc.requiredField
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _dealershipLocationController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _fieldDecoration(
                            context,
                            label: trLegacyText(
                              context,
                              'Dealership location',
                              ar: 'موقع الوكالة',
                              ku: 'شوێنی ناوەندی فرۆشتن',
                            ),
                            hint: trLegacyText(
                              context,
                              'City, district, and street',
                              ar: 'المدينة والمنطقة والشارع',
                              ku: 'شار، گەڕەک و شەقام',
                            ),
                            icon: Icons.location_on_outlined,
                            required: true,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? loc.requiredField
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _descriptionController,
                          minLines: 3,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: _fieldDecoration(
                            context,
                            label: trLegacyText(
                              context,
                              'About your dealership (optional)',
                              ar: 'عن وكالتك (اختياري)',
                              ku: 'دەربارەی ناوەندی فرۆشتنەکەت (ئارەزوومەندانە)',
                            ),
                            hint: trLegacyText(
                              context,
                              'Describe your inventory, experience, and customer service',
                              ar: 'صف مخزونك وخبرتك وخدمة العملاء',
                              ku: 'ئۆتۆمبێلەکان، ئەزموون و خزمەتگوزارییەکانت باس بکە',
                            ),
                            icon: Icons.notes_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      context,
                      icon: Icons.add_a_photo_outlined,
                      title: trLegacyText(
                        context,
                        'Dealership verification photo',
                        ar: 'صورة التحقق من الوكالة',
                        ku: 'وێنەی پشتڕاستکردنەوەی ناوەندی فرۆشتن',
                      ),
                      subtitle: trLegacyText(
                        context,
                        'Required · Used privately by our review team and never shown on your public profile.',
                        ar: 'مطلوب · يستخدمها فريق المراجعة بشكل خاص ولن تظهر أبداً في ملفك العام.',
                        ku: 'پێویستە · تەنها تیمی پێداچوونەوە بە نهێنی بەکاری دەهێنێت و لە پڕۆفایلی گشتی نیشان نادرێت.',
                      ),
                      children: [
                        Container(
                          height: 190,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: _businessPhotoBytes != null
                              ? Image.memory(
                                  _businessPhotoBytes!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                )
                              : _hasExistingVerificationPhoto
                              ? _uploadedPhotoPlaceholder(context, colors)
                              : _businessPhotoPlaceholder(context, colors),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _pickBusinessPhoto,
                            icon: Icon(
                              _businessPhotoBytes == null &&
                                      !_hasExistingVerificationPhoto
                                  ? Icons.upload_rounded
                                  : Icons.refresh_rounded,
                            ),
                            label: Text(
                              _businessPhotoBytes == null &&
                                      !_hasExistingVerificationPhoto
                                  ? trLegacyText(
                                      context,
                                      'Choose verification photo',
                                      ar: 'اختر صورة التحقق',
                                      ku: 'وێنەی پشتڕاستکردنەوە هەڵبژێرە',
                                    )
                                  : trLegacyText(
                                      context,
                                      'Replace photo',
                                      ar: 'استبدال الصورة',
                                      ku: 'گۆڕینی وێنە',
                                    ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.primary,
                              side: BorderSide(
                                color: colors.primary.withValues(alpha: 0.65),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          trLegacyText(
                            context,
                            'Upload one clear, recent photo of the dealership storefront, cars for sale, showroom, or office—anything that helps our team confirm the business is genuine.',
                            ar: 'ارفع صورة حديثة وواضحة لواجهة الوكالة أو السيارات المعروضة أو صالة العرض أو المكتب—أي صورة تساعد فريقنا على التأكد من أن النشاط حقيقي.',
                            ku: 'یەک وێنەی ڕوون و نوێی پێشەوەی ناوەندی فرۆشتن، ئۆتۆمبێلەکانی فرۆشتن، ناوەوە یان ئۆفیس باربکە—هەر شتێک کە یارمەتی تیمەکەمان بدات ڕاستیی بازرگانییەکە پشتڕاست بکاتەوە.',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(
                          _loading
                              ? trLegacyText(
                                  context,
                                  'Submitting…',
                                  ar: 'جارٍ الإرسال…',
                                  ku: 'دەنێردرێت…',
                                )
                              : trLegacyText(
                                  context,
                                  'Submit for review',
                                  ar: 'إرسال للمراجعة',
                                  ku: 'ناردن بۆ پێداچوونەوە',
                                ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          disabledBackgroundColor: colors.primary.withValues(
                            alpha: 0.55,
                          ),
                          disabledForegroundColor: colors.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 15,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            trLegacyText(
                              context,
                              'Your business information is handled securely.',
                              ar: 'يتم التعامل مع معلومات نشاطك بأمان.',
                              ku: 'زانیاری بازرگانییەکانت بە پارێزراوی بەڕێوەدەبرێن.',
                            ),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
