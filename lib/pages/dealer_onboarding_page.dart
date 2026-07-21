import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../shared/debug/app_log.dart';
import '../shared/errors/user_error_text.dart';

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
              fallback: AppLocalizations.of(context)!.unableToSelectThatPhoto,
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
            AppLocalizations.of(context)!.pleaseUploadAClearPhotoOfYourBusiness,
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
            AppLocalizations.of(context)!.dealershipDetailsSubmittedYourApplicationIsPendingReview,
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
              AppLocalizations.of(context)!.addAPhotoThatHelpsUsVerifyThisDealership,
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
            AppLocalizations.of(context)!.privateDealershipPhotoUploaded,
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
            AppLocalizations.of(context)!.createDealershipAccount,
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
                                  AppLocalizations.of(context)!.finalSetupStep,
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
                            AppLocalizations.of(context)!.buildYourDealershipPresence,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppLocalizations.of(context)!.addAccurateBusinessDetailsSoBuyersCanTrustAndContactYourDealership,
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
                                  AppLocalizations.of(context)!.reviewUsuallyTakes12BusinessDays,
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
                                    AppLocalizations.of(context)!.changesRequested,
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
                      title: AppLocalizations.of(context)!.businessInformation,
                      subtitle: AppLocalizations.of(context)!.theseDetailsWillAppearOnYourPublicDealershipProfile,
                      children: [
                        TextFormField(
                          controller: _dealershipNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _fieldDecoration(
                            context,
                            label: AppLocalizations.of(context)!.dealershipName,
                            hint: AppLocalizations.of(context)!.yourRegisteredOrTradingName,
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
                            label: AppLocalizations.of(context)!.businessPhone,
                            hint: AppLocalizations.of(context)!.aNumberBuyersCanReach,
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
                            label: AppLocalizations.of(context)!.dealershipLocation,
                            hint: AppLocalizations.of(context)!.cityDistrictAndStreet,
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
                            label: AppLocalizations.of(context)!.aboutYourDealershipOptional,
                            hint: AppLocalizations.of(context)!.describeYourInventoryExperienceAndCustomerService,
                            icon: Icons.notes_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      context,
                      icon: Icons.add_a_photo_outlined,
                      title: AppLocalizations.of(context)!.dealershipVerificationPhoto,
                      subtitle: AppLocalizations.of(context)!.requiredUsedPrivatelyByOurReviewTeamAndNeverShownOnYourPublicProfile,
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
                                  ? AppLocalizations.of(context)!.chooseVerificationPhoto
                                  : AppLocalizations.of(context)!.replacePhoto,
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
                          AppLocalizations.of(context)!.uploadOneClearRecentPhotoOfTheDealershipStorefrontCarsForSaleShowroomOrO,
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
                              ? AppLocalizations.of(context)!.submitting
                              : AppLocalizations.of(context)!.submitForReview,
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
                            AppLocalizations.of(context)!.yourBusinessInformationIsHandledSecurely,
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
