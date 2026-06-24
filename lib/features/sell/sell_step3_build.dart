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
                  colors: [Color(0xFFFF6B00).withValues(alpha: 0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFFF6B00).withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.attach_money, size: 48, color: Color(0xFFFF6B00)),
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
                    _trLegacyText(
                      context,
                      'Set your price and contact information',
                      ar: 'حدد السعر ومعلومات التواصل',
                      ku: 'نرخ و زانیاری پەیوەندی دابنێ',
                    ),
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
    final phoneDigits = _phoneController.text.trim();
    setState(() {
      contactPhone = phoneDigits.isEmpty ? null : '+964$phoneDigits';
    });
    _syncStep3DraftToParent();
    context.findAncestorStateOfType<_SellCarPageState>()?._goToPreviousStep();
  }

  void _onSellStep3NextPressed() {
    _dismissKeyboard();
    final l = AppLocalizations.of(context)!;
    final phoneLabel = _trLegacyText(
      context,
      'WhatsApp/Phone Number',
      ar: 'رقم واتساب/الهاتف',
      ku: 'ژمارەی واتساپ/مۆبایل',
    );
    final List<String> missing = [];

    if (selectedCity == null || selectedCity!.trim().isEmpty) {
      missing.add(l.cityLabel);
    }

    final phoneDigits = _phoneController.text.trim();
    setState(() {
      contactPhone = phoneDigits.isEmpty ? null : '+964$phoneDigits';
    });
    if (phoneDigits.isEmpty) {
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

    _syncStep3DraftToParent();
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
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
