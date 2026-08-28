part of 'sell_flow.dart';

/// Stages listing photos to storage while the seller fills later wizard steps,
/// so Submit mostly creates the car and attaches already-uploaded URLs.
mixin _SellCarPagePhotoPrestage on _SellCarPageDraftPersist {
  int _photoPrestageJobId = 0;
  Future<void>? _photoPrestageInFlight;

  /// Cancels the result of any in-flight prestage (photos changed).
  void invalidatePhotoPrestage() {
    _photoPrestageJobId++;
  }

  /// Uploads local listing/damage photos in the background.
  /// Safe to call repeatedly; only the latest job applies its result.
  Future<void> startBackgroundPhotoPrestage() {
    final jobId = ++_photoPrestageJobId;
    final future = _runBackgroundPhotoPrestage(jobId);
    _photoPrestageInFlight = future;
    return future;
  }

  Future<void> _runBackgroundPhotoPrestage(int jobId) async {
    try {
      final staged = await SellPhotoPrestage.stageCarData(carData);
      if (jobId != _photoPrestageJobId) return;
      if (staged > 0) {
        appLog('SellCarPage: background-staged $staged photos');
        unawaited(_saveSellDraftSnapshot());
      }
    } catch (e, st) {
      logNonFatal(e, st, 'SellCarPage.backgroundPhotoPrestage');
    }
  }

  /// Waits for the current background prestage (if any) before submit.
  Future<void> awaitBackgroundPhotoPrestage() async {
    final inFlight = _photoPrestageInFlight;
    if (inFlight == null) return;
    try {
      await inFlight;
    } catch (e, st) {
      logNonFatal(e, st, 'SellCarPage.awaitBackgroundPhotoPrestage');
    }
  }
}
