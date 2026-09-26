// Section B (real-device evidence): production kept re-polling the exact
// same Celery image-processing job id
// (`c2520566-22b1-418d-a5f9-de20f6aa1b74`) while newer jobs enqueued after
// it completed normally. Root cause: `SellAsyncJobTracker` durably records
// `path -> jobId` in `SellSubmissionRecord.pendingAsyncImageJobs` so a
// resumed submission can poll the SAME already-enqueued job instead of
// enqueueing a duplicate one -- but it never expired an entry, so a job
// that survived one interrupted poll (app killed mid-`await
// SellImageJobPolling.awaitImageJobRelPath(...)`, before the matching
// `tracker.clear()` could run) would be looked up and re-polled again on
// every future resume, forever, even if the underlying Celery task had been
// silently dropped (e.g. enqueued while the worker was OOM-crash-looping)
// and could never reach a terminal state.
//
// Fix: `record()` now stamps a recorded-at timestamp alongside the job id;
// `lookup()` treats an entry older than `SellAsyncJobTracker.maxJobAge` as
// A CANDIDATE for expiry -- never abandoned on age alone, though.
//
// Resume-audit follow-up (real-device evidence / 3-bug regression report):
// age-only abandonment could itself incorrectly re-enqueue a legitimate,
// still-processing job purely because a wall-clock cutoff was crossed (e.g.
// a large backlog, or several short interrupted resumes adding up) -- the
// exact "do NOT rely on a fixed arbitrary timeout if it can incorrectly
// re-enqueue a legitimate job" risk. `lookup()` now double-checks the job's
// REAL server-side state (`ApiService.getJobStatus`) once it crosses
// `maxJobAge`.
//
// Stale-job-reconciliation correction: the double-check's FIRST version
// still collapsed every non-PENDING/STARTED outcome (a genuine 404, a
// resolved SUCCESS/FAILURE the caller hadn't consumed yet, a 5xx, or a
// raw network/timeout error) into one "abandon it" bucket -- which itself
// violated the same "never discard a live/undetermined job" principle the
// original fix was for. It now abandons (clears + returns `null`) ONLY on
// an affirmative 404 (the server confirms the job id itself is unknown,
// e.g. evicted from the Celery result backend). Every other outcome --
// still PENDING/STARTED, a terminal state not yet reconciled, a 5xx, or a
// transport failure (offline/timeout/socket error) -- returns the job id
// unchanged so the normal poll immediately below can reconcile a result
// or the caller's bounded retry can re-check later, instead of this age
// check ever discarding a job the server hasn't confirmed is gone.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/sell_image_job_polling.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const draftId = 'draft_job_tracker';
  const localPath = '/tmp/some/local/photo.jpg';

  Future<void> seedRecord({Map<String, String>? pendingAsyncImageJobs}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await SellSubmissionStatePrefs.upsert(
      SellSubmissionRecord(
        draftId: draftId,
        status: SellSubmissionStatus.inProgress,
        carData: const {'images': <dynamic>[]},
        idempotencyKey: 'sell-create-$draftId',
        createdAt: now,
        updatedAt: now,
        pendingAsyncImageJobs: pendingAsyncImageJobs,
      ),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = true;
  });

  tearDown(() {
    ApiService.testHttpClient = null;
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  test(
    'record() then lookup() returns the SAME job id immediately (fresh, '
    'not expired)',
    () async {
      await seedRecord();
      final tracker = SellAsyncJobTracker(draftId);

      await tracker.record(localPath, 'job_123');
      final found = await tracker.lookup(localPath);

      expect(found, 'job_123');
    },
  );

  test(
    'clear() removes the recorded job id -- a later lookup() finds nothing',
    () async {
      await seedRecord();
      final tracker = SellAsyncJobTracker(draftId);

      await tracker.record(localPath, 'job_456');
      await tracker.clear(localPath);
      final found = await tracker.lookup(localPath);

      expect(found, isNull);
    },
  );

  test(
    'a job id recorded longer ago than maxJobAge, which the server '
    'confirms via a 404 (job unknown/evicted from the Celery result '
    'backend) is treated as expired: lookup() returns null AND clears the '
    'stale entry as a side effect, instead of returning it for re-polling '
    'forever',
    () async {
      const jobId = 'c2520566-22b1-418d-a5f9-de20f6aa1b74';
      final staleRecordedAt = DateTime.now()
          .subtract(SellAsyncJobTracker.maxJobAge + const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      await seedRecord(
        pendingAsyncImageJobs: {
          localPath: '$jobId|$staleRecordedAt',
        },
      );
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/jobs/$jobId') {
          return http.Response('{"message": "not found"}', 404);
        }
        return http.Response('{}', 404);
      });
      final tracker = SellAsyncJobTracker(draftId);

      final found = await tracker.lookup(localPath);
      expect(
        found,
        isNull,
        reason: 'an expired, server-confirmed-gone job must never be '
            'handed back for re-polling',
      );

      // Side effect: the stale entry is actually cleared from the durable
      // record, not just ignored -- otherwise every future lookup would
      // redundantly re-decide "expired" for the same dead entry forever
      // (harmless but wasteful) instead of the record settling back to a
      // clean "nothing outstanding" state once abandoned.
      final record = await SellSubmissionStatePrefs.load(draftId);
      expect(record, isNotNull);
      expect(
        record!.pendingAsyncImageJobs.containsKey(localPath),
        isFalse,
        reason: 'the stale entry must be cleared, not merely skipped',
      );
    },
  );

  test(
    'resume-audit fix: a job id older than maxJobAge that the server '
    'confirms is STILL PENDING (a genuinely slow, but alive, job) is kept '
    '-- lookup() returns the SAME job id instead of abandoning it purely '
    'because of its age, which would otherwise enqueue a duplicate job '
    'for a still-processing image',
    () async {
      const jobId = 'still_alive_job';
      final staleRecordedAt = DateTime.now()
          .subtract(SellAsyncJobTracker.maxJobAge + const Duration(minutes: 3))
          .millisecondsSinceEpoch;
      await seedRecord(
        pendingAsyncImageJobs: {
          localPath: '$jobId|$staleRecordedAt',
        },
      );
      var statusCallCount = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/jobs/$jobId') {
          statusCallCount++;
          return http.Response(
            json.encode({'task_id': jobId, 'state': 'PENDING'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });
      final tracker = SellAsyncJobTracker(draftId);

      final found = await tracker.lookup(localPath);

      expect(
        found,
        jobId,
        reason: 'a job the server confirms is still PENDING must never be '
            'abandoned on age alone',
      );
      expect(statusCallCount, 1, reason: 'must actually check live status');
      final record = await SellSubmissionStatePrefs.load(draftId);
      expect(
        record!.pendingAsyncImageJobs.containsKey(localPath),
        isTrue,
        reason: 'a still-active job must not be cleared from the tracker',
      );
    },
  );

  test(
    'stale-job-reconciliation fix: a job id older than maxJobAge that the '
    'server confirms has reached a terminal state (e.g. FAILURE) is NOT '
    'abandoned by lookup() itself -- the id is returned unchanged so the '
    'normal poll immediately below can apply the existing '
    'failure/needsAttention policy, instead of this age check silently '
    'discarding the outcome and duplicate-enqueueing a replacement job',
    () async {
      const jobId = 'terminal_job';
      final staleRecordedAt = DateTime.now()
          .subtract(SellAsyncJobTracker.maxJobAge + const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      await seedRecord(
        pendingAsyncImageJobs: {
          localPath: '$jobId|$staleRecordedAt',
        },
      );
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/jobs/$jobId') {
          return http.Response(
            json.encode({'task_id': jobId, 'state': 'FAILURE'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });
      final tracker = SellAsyncJobTracker(draftId);

      final found = await tracker.lookup(localPath);

      expect(
        found,
        jobId,
        reason: 'a resolved-but-not-yet-consumed terminal job must be '
            'handed back, not silently discarded by the age check',
      );
      final record = await SellSubmissionStatePrefs.load(draftId);
      expect(
        record!.pendingAsyncImageJobs.containsKey(localPath),
        isTrue,
        reason: 'lookup() must not clear an entry it did not confirm is '
            'genuinely gone -- clearing happens only after the caller '
            'actually consumes the result',
      );
    },
  );

  test(
    'stale-job-reconciliation fix: a job id older than maxJobAge that the '
    'server confirms has SUCCEEDED is NOT abandoned/duplicated -- the id '
    'is returned so the normal poll can reconcile the already-computed '
    'result',
    () async {
      const jobId = 'succeeded_job';
      final staleRecordedAt = DateTime.now()
          .subtract(SellAsyncJobTracker.maxJobAge + const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      await seedRecord(
        pendingAsyncImageJobs: {
          localPath: '$jobId|$staleRecordedAt',
        },
      );
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/jobs/$jobId') {
          return http.Response(
            json.encode({
              'task_id': jobId,
              'state': 'SUCCESS',
              'result': {'rel_path': 'listings/already_done.jpg'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });
      final tracker = SellAsyncJobTracker(draftId);

      final found = await tracker.lookup(localPath);

      expect(found, jobId);
      final record = await SellSubmissionStatePrefs.load(draftId);
      expect(record!.pendingAsyncImageJobs.containsKey(localPath), isTrue);
    },
  );

  test(
    'required semantics (1): a job id older than maxJobAge whose status '
    'check fails with a network/transport error (never reaches the '
    'server, e.g. offline/timeout -- NOT an HTTP 404) is NOT abandoned or '
    'duplicated -- it stays persisted for a later bounded retry',
    () async {
      const jobId = 'network_flaky_job';
      final staleRecordedAt = DateTime.now()
          .subtract(SellAsyncJobTracker.maxJobAge + const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      await seedRecord(
        pendingAsyncImageJobs: {
          localPath: '$jobId|$staleRecordedAt',
        },
      );
      ApiService.testHttpClient = MockClient((request) async {
        throw const SocketException('Network is unreachable');
      });
      final tracker = SellAsyncJobTracker(draftId);

      final found = await tracker.lookup(localPath);

      expect(
        found,
        jobId,
        reason: 'a transient network failure must never be treated as '
            'proof the job is gone',
      );
      final record = await SellSubmissionStatePrefs.load(draftId);
      expect(
        record!.pendingAsyncImageJobs.containsKey(localPath),
        isTrue,
        reason: 'the entry must remain persisted so a later resume/poll '
            'can retry the status check',
      );
    },
  );

  test(
    'required semantics (1): a job id older than maxJobAge whose status '
    'check fails with a 5xx server error is NOT abandoned or duplicated '
    '-- only an affirmative 404 (job id genuinely unknown) may abandon it',
    () async {
      const jobId = 'server_error_job';
      final staleRecordedAt = DateTime.now()
          .subtract(SellAsyncJobTracker.maxJobAge + const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      await seedRecord(
        pendingAsyncImageJobs: {
          localPath: '$jobId|$staleRecordedAt',
        },
      );
      ApiService.testHttpClient = MockClient((request) async {
        return http.Response('{"message": "internal error"}', 503);
      });
      final tracker = SellAsyncJobTracker(draftId);

      final found = await tracker.lookup(localPath);

      expect(found, jobId);
      final record = await SellSubmissionStatePrefs.load(draftId);
      expect(record!.pendingAsyncImageJobs.containsKey(localPath), isTrue);
    },
  );

  test(
    'a job id recorded well within maxJobAge is still returned for '
    're-polling (not prematurely abandoned)',
    () async {
      final recentRecordedAt = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      await seedRecord(
        pendingAsyncImageJobs: {
          localPath: 'job_recent|$recentRecordedAt',
        },
      );
      final tracker = SellAsyncJobTracker(draftId);

      final found = await tracker.lookup(localPath);

      expect(found, 'job_recent');
      final record = await SellSubmissionStatePrefs.load(draftId);
      expect(
        record!.pendingAsyncImageJobs.containsKey(localPath),
        isTrue,
        reason: 'a still-fresh entry must not be cleared',
      );
    },
  );

  test(
    'a pre-fix entry with no embedded timestamp (just a bare job id, as an '
    'older app version would have written) is treated as freshly-recorded '
    '-- returned once for a full re-poll instead of being discarded '
    'outright by this change',
    () async {
      await seedRecord(
        pendingAsyncImageJobs: {localPath: 'legacy_job_no_timestamp'},
      );
      final tracker = SellAsyncJobTracker(draftId);

      final found = await tracker.lookup(localPath);

      expect(found, 'legacy_job_no_timestamp');
    },
  );

  test(
    'lookup() for a draftId with no durable record at all returns null '
    '(never throws)',
    () async {
      final tracker = SellAsyncJobTracker(draftId);
      final found = await tracker.lookup(localPath);
      expect(found, isNull);
    },
  );

  test(
    'a null draftId makes every operation a no-op (never throws, always '
    'returns null from lookup)',
    () async {
      const tracker = SellAsyncJobTracker(null);
      await tracker.record(localPath, 'job_x');
      await tracker.clear(localPath);
      final found = await tracker.lookup(localPath);
      expect(found, isNull);
    },
  );
}
