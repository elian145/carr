import '../../shared/prefs/sell_submission_state_prefs.dart';

/// Single source of truth for "is this durable submission record
/// represented as a visible entry in the owner's UI?" and, by the same
/// token, "may the ordinary editable draft with the same id be hidden?".
///
/// Regression this exists for ("listing disappears after backgrounding"):
/// `SellDraftGatePage` hid a draft whenever ANY record existed for it
/// (including `needsAttention` / not-yet-created ones) while My Listings
/// rendered no entry for a record at all -- so the draft vanished and
/// nothing replaced it. The invariant is now: a draft is hidden if and only
/// if the record that supersedes it is shown as a pending entry.
///
/// Records that are NOT shown as an entry:
///  * `completed` -- the listing exists server-side and is rendered by the
///    normal listings feed;
///  * edit submissions -- the listing already exists, nothing new to show;
///  * records owned by a DIFFERENT signed-in account on a shared device.
bool sellSubmissionShowsPendingEntry(
  SellSubmissionRecord record, {
  String currentOwnerId = '',
}) {
  if (record.status == SellSubmissionStatus.completed) return false;
  if (record.isEdit) return false;
  final owner = (record.ownerUserId ?? '').trim();
  if (owner.isEmpty || currentOwnerId.isEmpty) return true;
  return owner == currentOwnerId;
}

/// The ordinary draft sharing this record's id may be hidden only when the
/// record is shown as a pending entry (never hide without replacing) AND the
/// draft is not the user's way to fix the problem.
///
/// A `needsAttention` record whose listing was never created (no `carId`)
/// is blocked on something only the user can change -- typically replacing
/// photos that are no longer readable. Retry alone just re-reads the same
/// missing files, so the editable draft stays visible next to the entry;
/// re-submitting it reuses the record (same idempotency key, frozen media
/// mapping). Once a listing exists the draft was already consumed.
bool sellSubmissionHidesDraft(
  SellSubmissionRecord record, {
  String currentOwnerId = '',
}) {
  if (!sellSubmissionShowsPendingEntry(record, currentOwnerId: currentOwnerId)) {
    return false;
  }
  if (record.status == SellSubmissionStatus.needsAttention &&
      (record.carId ?? '').trim().isEmpty) {
    return false;
  }
  return true;
}

/// Records to render as pending entries, newest first. A record whose
/// listing already appears in the loaded server listings
/// ([serverListingIds]) is skipped: the real card (with its own
/// "processing media" badge) is then the representation.
List<SellSubmissionRecord> sellSubmissionPendingEntries(
  Iterable<SellSubmissionRecord> records, {
  String currentOwnerId = '',
  Set<String> serverListingIds = const <String>{},
}) {
  final out = <SellSubmissionRecord>[
    for (final r in records)
      if (sellSubmissionShowsPendingEntry(r, currentOwnerId: currentOwnerId))
        if ((r.carId ?? '').isEmpty || !serverListingIds.contains(r.carId))
          r,
  ];
  out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return out;
}
