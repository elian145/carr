part of 'sell_flow.dart';

mixin _SellStep5Fields on State<SellStep5Page> {
  bool isSubmitting = false;
  String submitStatusMessage = '';

  /// F-41: the user tapped Cancel before the submission service was even
  /// called (phone verification / validation / prestage window), when there
  /// is nothing in the service to cancel yet. Consumed by `_submitListing`
  /// right before it hands the draft to the service.
  bool submitCancelRequested = false;
}
