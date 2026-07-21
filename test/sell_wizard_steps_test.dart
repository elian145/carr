import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/sell/sell_wizard_steps.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_step.dart';

void main() {
  test('SellWizardSteps count and lastIndex stay aligned (L-03)', () {
    expect(SellWizardSteps.count, 6);
    expect(SellWizardSteps.lastIndex, SellWizardSteps.count - 1);
    expect(SellWizardSteps.reviewSubmit, SellWizardSteps.lastIndex);
    expect(SellWizardSteps.clampIndex(-1), 0);
    expect(SellWizardSteps.clampIndex(99), SellWizardSteps.lastIndex);
  });

  test('SellWizardSteps progress percent spans 17%…100% (UX-01)', () {
    expect(SellWizardSteps.progressPercent(0), 17);
    expect(SellWizardSteps.progressPercent(2), 50);
    expect(SellWizardSteps.progressPercent(SellWizardSteps.lastIndex), 100);
    expect(SellWizardSteps.progressFraction(0), closeTo(1 / 6, 1e-9));
    expect(SellWizardSteps.progressFraction(99), 1.0);
  });

  test('draft step helpers default to SellWizardSteps.lastIndex', () {
    expect(readSellDraftStepDynamic(99), SellWizardSteps.lastIndex);
    expect(mergeSellDraftStep(jsonStep: 2, prefsStep: 4), 4);
    expect(maxSellDraftStep(1, 3, 5), SellWizardSteps.lastIndex);
  });
}
