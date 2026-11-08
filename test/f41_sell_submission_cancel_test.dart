// F-41: safe cancellation of a listing submission.
import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/features/sell/sell_listing_media_upload.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SellSubmissionRecord _record({
  String? carId,
  bool isEdit = false,
  SellSubmissionStatus status = SellSubmissionStatus.retryable,
}) =>
    SellSubmissionRecord(
      draftId: 'd1',
      status: status,
      carData: const {'brand': 'toyota'},
      idempotencyKey: 'k1',
      createdAt: 1,
      updatedAt: 1,
      isEdit: isEdit,
      carId: carId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = PendingSellSubmissionService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('cancel before the listing exists removes the record, no retry left',
      () async {
    await SellSubmissionStatePrefs.upsert(_record());
    expect(await svc.canCancel('d1'), isTrue);
    expect(await svc.cancelSubmission('d1'), SellCancelOutcome.draftKept);
    expect(await SellSubmissionStatePrefs.load('d1'), isNull);
    expect(svc.isCancelRequested('d1'), isFalse);
  });

  test('cancel after the listing exists parks it as needsAttention (no retry)',
      () async {
    await SellSubmissionStatePrefs.upsert(_record(carId: 'car_9'));
    final events = <SellSubmissionEvent>[];
    final sub = svc.events.listen(events.add);
    expect(await svc.cancelSubmission('d1'),
        SellCancelOutcome.listingNeedsAttention);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    final r = await SellSubmissionStatePrefs.load('d1');
    expect(r!.status, SellSubmissionStatus.needsAttention);
    expect(r.lastErrorRetryable, isFalse);
    expect(r.carId, 'car_9');
    expect(events.single.needsAttention, isTrue);
    expect(SellListingMediaUpload.isCancelled('car_9'), isFalse);
  });

  test('edits and finished submissions are not cancellable', () async {
    await SellSubmissionStatePrefs.upsert(_record(isEdit: true, carId: 'c'));
    expect(await svc.canCancel('d1'), isFalse);
    expect(await svc.cancelSubmission('d1'), isNull);
    await SellSubmissionStatePrefs.upsert(
      _record(status: SellSubmissionStatus.needsAttention, carId: 'c'),
    );
    expect(await svc.cancelSubmission('d1'), isNull);
    expect(await svc.cancelSubmission('nope'), isNull);
  });
}
