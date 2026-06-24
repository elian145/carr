part of 'sell_flow.dart';

mixin _SellStep2Build on _SellStep2BuildMechanical {
  void _onSellStep2NextPressed() {
    final l = AppLocalizations.of(context)!;
    final List<String> missing = [];

    if (selectedMileage == null || selectedMileage!.trim().isEmpty) {
      missing.add(l.mileageKmLabel);
    }
    if (selectedCondition == null || selectedCondition!.trim().isEmpty) {
      missing.add(l.conditionLabel);
    }
    if (selectedTransmission == null || selectedTransmission!.trim().isEmpty) {
      missing.add(l.transmissionLabel);
    }
    if (selectedFuelType == null || selectedFuelType!.trim().isEmpty) {
      missing.add(l.fuelTypeLabel);
    }
    if (selectedBodyType == null || selectedBodyType!.trim().isEmpty) {
      missing.add(l.bodyTypeLabel);
    }
    if (selectedColor == null || selectedColor!.trim().isEmpty) {
      missing.add(l.colorLabel);
    }
    if (selectedDriveType == null || selectedDriveType!.trim().isEmpty) {
      missing.add(l.driveType);
    }
    final regionCode = selectedRegionSpecs?.trim().toLowerCase() ?? '';
    if (regionCode.isEmpty || !isValidCarRegionSpecCode(regionCode)) {
      missing.add(l.regionSpecsLabel);
    }
    if (selectedSeating == null || selectedSeating!.trim().isEmpty) {
      missing.add(l.seating);
    }
    if (selectedTitleStatus == null || selectedTitleStatus!.trim().isEmpty) {
      missing.add(l.titleStatus);
    }

    setState(() {
      errMileage = selectedMileage == null || selectedMileage!.trim().isEmpty;
      errCondition =
          selectedCondition == null || selectedCondition!.trim().isEmpty;
      errTransmission = selectedTransmission == null ||
          selectedTransmission!.trim().isEmpty;
      errFuelType =
          selectedFuelType == null || selectedFuelType!.trim().isEmpty;
      errBodyType =
          selectedBodyType == null || selectedBodyType!.trim().isEmpty;
      errColor = selectedColor == null || selectedColor!.trim().isEmpty;
      errDrive =
          selectedDriveType == null || selectedDriveType!.trim().isEmpty;
      errRegionSpecs =
          regionCode.isEmpty || !isValidCarRegionSpecCode(regionCode);
      errSeating = selectedSeating == null || selectedSeating!.trim().isEmpty;
      errTitle = selectedTitleStatus == null ||
          selectedTitleStatus!.trim().isEmpty;
    });

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

    _syncStep2DraftToParent();
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    parentState?._goToNextStep();
  }

  List<Widget> _sellStep2BuildNavSection() {
    return [
      const SizedBox(height: 32),
      buildSellWizardNavRow(
        context,
        onPrevious: () {
          _syncStep2DraftToParent();
          context
              .findAncestorStateOfType<_SellCarPageState>()
              ?._goToPreviousStep();
        },
        onNext: _onSellStep2NextPressed,
      ),
    ];
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
            ..._sellStep2BuildCoreSection(),
            ..._sellStep2BuildAppearanceSection(),
            ..._sellStep2BuildMechanicalSection(),
            ..._sellStep2BuildNavSection(),
          ],
        ),
      ),
    );
  }
}
