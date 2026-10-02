/// Optimistic-local-media fix (Critical Issue 1): the read/merge/persist/
/// cleanup operations for `OwnerOptimisticMediaRecord`
/// (`owner_optimistic_media_prefs.dart`) -- kept separate from the prefs
/// class itself (pure data + storage) and from `OwnerMediaOverlay` (pure,
/// synchronous slot-building) so each stays independently testable.
///
/// LIFETIME CONTRACT (see the user-facing report for the full writeup):
///   A. backend_transfer_complete / B. backend_media_ready -- upstream of
///      this file entirely (`CarMediaItem`/`media-summary`,
///      `OwnerPendingMediaMerge.isMediaProcessing`).
///   C. client_remote_display_ready -- [markRemoteDisplayReadyAndCleanup]'s
///      OWN precondition (a fallback widget already confirmed a real
///      decode/initialization before ever calling it).
///   D. local_optimistic_media_cleanup_allowed -- ONLY once C is true for
///      an item (per-item file delete) / for every expected item (whole
///      record delete). Never derived from A/B alone.
library;

import 'dart:io';

import '../debug/app_log.dart';
import '../prefs/owner_optimistic_media_prefs.dart';
import '../prefs/sell_draft_media_persistence.dart';
import 'owner_media_overlay.dart';

abstract final class OwnerOptimisticMediaCleanup {
  OwnerOptimisticMediaCleanup._();

  /// Real-device acceptance fix ("badge never disappears even once every
  /// item is confirmed ready"): [OwnerOptimisticMediaPrefs.upsert] does a
  /// plain load-all -> modify-one -> save-all cycle with no locking of its
  /// own. [syncFromItems] and [markRemoteDisplayReadyAndCleanup] both read
  /// the SAME per-listing record, modify their own copy, then write it
  /// back -- harmless when calls for one listing are spread out, but once
  /// several items confirm remote-display-readiness within the same
  /// handful of frames (now routine after the overlay-matching fix above
  /// lets every expected item reconcile at once instead of never), their
  /// `unawaited` calls genuinely overlap: a later call's `load()` can run
  /// before an earlier call's `upsert()` has landed, so the earlier call's
  /// change is silently clobbered when the later call saves its own
  /// (stale-based) copy. Confirmed on a real device: all 6 expected items
  /// reached `remote_display_ready=true` in-memory, yet the persisted
  /// record never reached `allRemoteDisplayReady` and was never removed --
  /// the "Processing media" badge stayed visible indefinitely (even across
  /// a fresh navigation/reload) because `serverStillProcessing` is derived
  /// from that still-present record. Serializing every mutating call for
  /// the SAME [String] listingId through this per-listing queue (distinct
  /// listingIds never block each other) makes each call's load-modify-
  /// save cycle atomic with respect to every other call for that listing,
  /// eliminating the lost update.
  static final Map<String, Future<void>> _listingLocks =
      <String, Future<void>>{};

  static Future<T> _withListingLock<T>(
    String listingId,
    Future<T> Function() action,
  ) {
    final previous = _listingLocks[listingId] ?? Future<void>.value();
    final result = previous.then((_) => action());
    // Keep the queue itself advancing even if `action` throws -- the
    // thrown error still propagates to THIS call's caller via `result`
    // below; only the queued continuation must never itself throw.
    _listingLocks[listingId] = result.then((_) {}, onError: (_) {});
    return result;
  }

  static List<OwnerOptimisticMediaItem> itemsFromSlots(
    List<OwnerMediaSlot> slots,
  ) {
    return slots
        .map(
          (s) => OwnerOptimisticMediaItem(
            clientMediaId: s.clientMediaId,
            kind: s.kind == OwnerMediaKind.image ? 'image' : 'video',
            order: s.order,
            localPath: s.localPath,
            remoteUrl: s.remoteUrl,
          ),
        )
        .toList();
  }

  /// Merges [freshItems] (the latest known local/remote shape, from either
  /// a live `OwnerMediaOverlay` build or a `SellSubmissionRecord`
  /// completion-time snapshot) into whatever is already durably persisted
  /// for [listingId], PRESERVING every already-true
  /// `OwnerOptimisticMediaItem.remoteDisplayReady` flag (and that item's
  /// already-cleaned-up `null` localPath) -- never regresses an item from
  /// ready back to not-ready, and never resurrects a deleted local path.
  /// Persists the merge result and returns it.
  ///
  /// Safe to call with an empty [freshItems] list (e.g. the record was
  /// already fully reconciled and the caller has nothing new to add) --
  /// a no-op that just returns the existing record unchanged (or `null`).
  static Future<OwnerOptimisticMediaRecord?> syncFromItems({
    required String listingId,
    required List<OwnerOptimisticMediaItem> freshItems,
    String? draftId,
  }) {
    if (listingId.trim().isEmpty) return Future.value(null);
    return _withListingLock(listingId, () async {
      final existing = await OwnerOptimisticMediaPrefs.load(listingId);
      if (freshItems.isEmpty) return existing;

      final existingById = <String, OwnerOptimisticMediaItem>{
        for (final it
            in existing?.items ?? const <OwnerOptimisticMediaItem>[])
          it.clientMediaId: it,
      };

      final merged = freshItems.map((fresh) {
        final prior = existingById[fresh.clientMediaId];
        if (prior == null) return fresh;
        if (prior.remoteDisplayReady) {
          // Already confirmed + already cleaned up -- never regress.
          return prior.copyWith(
            remoteUrl: fresh.remoteUrl ?? prior.remoteUrl,
          );
        }
        return fresh.copyWith(
          remoteUrl: fresh.remoteUrl ?? prior.remoteUrl,
          localPath: fresh.localPath ?? prior.localPath,
        );
      }).toList();

      final record = OwnerOptimisticMediaRecord(
        listingId: listingId,
        items: merged,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        draftId: draftId ?? existing?.draftId,
      );
      await OwnerOptimisticMediaPrefs.upsert(record);
      return record;
    });
  }

  /// Best-effort whole-directory removal for [record]'s originating Sell
  /// draft (see [OwnerOptimisticMediaRecord.draftId]'s own doc comment) --
  /// catches any untracked sibling file (e.g. a blur-choice preview, a
  /// damage-disclosure photo) this record never had its own item for.
  /// A no-op if [OwnerOptimisticMediaRecord.draftId] is unknown.
  static Future<void> _deleteDraftDirectoryIfKnown(
    OwnerOptimisticMediaRecord record,
  ) async {
    final draftId = record.draftId;
    if (draftId == null || draftId.trim().isEmpty) return;
    try {
      final dir = await SellDraftMediaPersistence.draftDirectory(draftId);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  /// Seeds a `car_details_page_fields.dart`-style in-memory
  /// `clientMediaId -> remoteDisplayReady` map from the persisted record
  /// -- restart-safety: "if remote_display_ready was true previously and
  /// the remote URL is unchanged, it is okay to restore that state on
  /// restart" (user's explicit instruction). Callers that already know
  /// the current live remote URL per slot may pass it via [liveRemoteUrls]
  /// to guard against restoring a stale `true` for an item whose remote
  /// URL has since changed (defensive; in practice a listing's own
  /// attached-media URLs are stable once set).
  static Future<Map<String, bool>> loadRemoteDisplayReadyMap(
    String listingId, {
    Map<String, String>? liveRemoteUrls,
  }) async {
    final record = await OwnerOptimisticMediaPrefs.load(listingId);
    if (record == null) return const <String, bool>{};
    final out = <String, bool>{};
    for (final item in record.items) {
      if (!item.remoteDisplayReady) continue;
      if (liveRemoteUrls != null) {
        final live = liveRemoteUrls[item.clientMediaId];
        if (live != null && item.remoteUrl != null && live != item.remoteUrl) {
          continue; // remote URL changed since confirmation -- don't restore.
        }
      }
      out[item.clientMediaId] = true;
    }
    return out;
  }

  /// A fallback widget just confirmed a successful remote decode/
  /// initialization for [clientMediaId] under [listingId] -- persists
  /// `remoteDisplayReady=true` for that item, deletes ITS local file (safe
  /// per the lifetime contract: this is only ever called after a genuine
  /// successful decode), and -- once every expected item for [listingId]
  /// is remote-display-ready -- removes the whole record too.
  ///
  /// Idempotent: a repeat call for an already-ready item is a harmless
  /// no-op.
  ///
  /// Returns `true` iff [listingId]'s durable record is now fully gone
  /// (either it already didn't exist, or this very call was the one that
  /// just deleted it because every expected item is remote-display-ready)
  /// -- callers use this to refresh any "still processing" UI signal that
  /// was snapshotted from the record's mere existence back when the page
  /// first loaded (see `car_details_page_media.dart`'s
  /// `_showProcessingMedia` doc comment: that snapshot can otherwise stay
  /// stale -- stuck showing "still processing" -- for the rest of the
  /// page's lifetime even after the real work underneath has genuinely
  /// finished, since nothing else ever re-reads the persisted record
  /// again until the next full page load).
  static Future<bool> markRemoteDisplayReadyAndCleanup({
    required String listingId,
    required String clientMediaId,
  }) {
    return _withListingLock(listingId, () async {
      try {
        final record = await OwnerOptimisticMediaPrefs.load(listingId);
        if (record == null) return true;
        final idx = record.items.indexWhere(
          (i) => i.clientMediaId == clientMediaId,
        );
        if (idx == -1) return false;
        final item = record.items[idx];
        if (item.remoteDisplayReady) {
          return record.items.every((i) => i.remoteDisplayReady);
        }

        if ((item.localPath ?? '').trim().isNotEmpty) {
          try {
            final f = File(item.localPath!);
            if (await f.exists()) await f.delete();
          } catch (e, st) {
            logNonFatal(e, st);
          }
        }

        final updatedItems =
            List<OwnerOptimisticMediaItem>.from(record.items);
        updatedItems[idx] = item.copyWith(
          remoteDisplayReady: true,
          clearLocalPath: true,
        );
        final allReady = updatedItems.every((i) => i.remoteDisplayReady);
        if (allReady) {
          await _deleteDraftDirectoryIfKnown(record);
          await OwnerOptimisticMediaPrefs.remove(listingId);
        } else {
          await OwnerOptimisticMediaPrefs.upsert(
            record.copyWith(
              items: updatedItems,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }
        return allReady;
      } catch (e, st) {
        logNonFatal(e, st);
        return false;
      }
    });
  }

  /// `PendingSellSubmissionService`'s own completion-time hook: writes/
  /// merges the initial durable snapshot for [listingId] from [freshItems]
  /// (built from the just-finished `SellSubmissionRecord.carData`, see
  /// `owner_media_overlay.dart`'s `OwnerMediaOverlay.snapshotItemsFromRecord`)
  /// and records [draftId] (see [OwnerOptimisticMediaRecord.draftId]'s own
  /// doc comment) so the record exists (and is restart-safe) EVEN IF the
  /// owner never opened Car Details while the submission was in flight.
  /// Then, ONLY if every item already turns out to be remote-display-ready
  /// (e.g. the owner had Car Details open and already confirmed
  /// everything, or there were zero expected items), deletes the whole
  /// draft directory and removes the record. Otherwise leaves the
  /// directory AND the record alone: "do NOT clear local optimistic media
  /// merely because backend processing is done" -- the SAME per-item/
  /// whole-record cleanup [markRemoteDisplayReadyAndCleanup] performs
  /// later, as real on-device confirmations arrive, takes over from here.
  static Future<void> snapshotAtSubmissionCompleteAndMaybeFinalize({
    required String listingId,
    required List<OwnerOptimisticMediaItem> freshItems,
    required String draftId,
  }) async {
    try {
      if (listingId.trim().isEmpty) return;
      final record = await syncFromItems(
        listingId: listingId,
        freshItems: freshItems,
        draftId: draftId,
      );
      if (record == null || record.isEmpty) return;
      if (record.allRemoteDisplayReady) {
        await _deleteDraftDirectoryIfKnown(record);
        await OwnerOptimisticMediaPrefs.remove(listingId);
      }
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }
}
