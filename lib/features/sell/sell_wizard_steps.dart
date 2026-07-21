/// Sell listing wizard step indices and length (L-03).
///
/// Keep [count] in sync with the PageView children in [_SellCarPageFields].
abstract final class SellWizardSteps {
  static const int count = 6;
  static const int lastIndex = count - 1;

  static const int photos = 0;
  static const int basicInfo = 1;
  static const int carDetails = 2;
  static const int pricingContact = 3;
  static const int plateBlur = 4;
  static const int reviewSubmit = 5;

  static int clampIndex(num step) => step.clamp(0, lastIndex).toInt();
}
