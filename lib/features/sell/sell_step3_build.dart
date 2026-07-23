part of 'sell_flow.dart';

mixin _SellStep3Build on _SellStep3BuildDetails {
  List<Widget> _sellStep3BuildHeaderSection() {
    return [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.brandOrange.withValues(alpha: 0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.brandOrange.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.attach_money, size: 48, color: AppColors.brandOrange),
                  SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)!.pricingContactTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.setYourPriceAndContactInformation,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
    ];
  }

  List<Widget> _sellStep3BuildNavSection() {
    return [
      const SizedBox(height: 32),
      buildSellWizardNavRow(
        context,
        onPrevious: _onSellStep3PreviousPressed,
        onNext: _onSellStep3NextPressed,
      ),
    ];
  }

  void _onSellStep3PreviousPressed() {
    _dismissKeyboard();
    setState(() {
      contactPhones = _collectContactPhonesFromControllers();
      contactPhone = contactPhones.isEmpty ? null : contactPhones.first;
    });
    _syncStep3DraftToParent();
    context.findAncestorStateOfType<_SellCarPageState>()?._goToPreviousStep();
  }

  void _onSellStep3NextPressed() async {
    _dismissKeyboard();
    final l = AppLocalizations.of(context)!;
    final phoneLabel = AppLocalizations.of(context)!.whatsappPhoneNumber;
    final List<String> missing = [];

    if (selectedCity == null || selectedCity!.trim().isEmpty) {
      missing.add(l.cityLabel);
    }

    setState(() {
      contactPhones = _collectContactPhonesFromControllers();
      contactPhone = contactPhones.isEmpty ? null : contactPhones.first;
    });
    if (contactPhones.isEmpty) {
      missing.add(phoneLabel);
    }

    final formValid = _formKey.currentState?.validate() ?? false;

    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_pleaseFillRequiredGlobal(context)}: ${missing.join(', ')}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!formValid) return;

    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final auth = context.read<AuthService>();
    for (final phone in contactPhones) {
      final ok = isListingContactPhoneVerified(
        contactPhone: phone,
        auth: auth,
        verifiedPhonesCache: parentState?._verifiedListingPhones,
      );
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.verifyContactPhonesBeforeContinuing),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    _syncStep3DraftToParent();
    parentState?._goToNextStep();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._sellStep3BuildHeaderSection(),
            ..._sellStep3BuildPriceSection(),
            ..._sellStep3BuildDetailsSection(),
            ..._sellStep3BuildNavSection(),
          ],
        ),
      ),
    );
  }
}
