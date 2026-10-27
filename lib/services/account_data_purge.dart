import '../shared/debug/app_log.dart';
import '../shared/prefs/account_local_data.dart';
import '../shared/prefs/chat_pending_send_prefs.dart';
import '../shared/prefs/favorites_cache_prefs.dart';
import '../shared/prefs/sell_submission_state_prefs.dart';
import 'saved_search_service.dart';

/// Removes every piece of on-device private data that belongs to one account.
///
/// Used ONLY after the server has confirmed that the account was deleted
/// (see `AuthService.deleteAccount`). Plain logout never calls this: it keeps
/// the account's owner-scoped data on disk for when that account signs in
/// again, relying on per-owner scoping to keep it invisible to everyone else.
class AccountDataPurge {
  AccountDataPurge._();

  static Future<void> purgeOwner(String ownerId) async {
    if (ownerId.isEmpty) return;
    final steps = <String, Future<void> Function()>{
      'saved_searches': () => SavedSearchService.purgeOwner(ownerId),
      'chat_pending': () => ChatPendingSendPrefs.removeAllForOwner(ownerId),
      'favorites_cache': () => FavoritesCachePrefs.purgeOwner(ownerId),
      'sell_submissions': () async {
        final all = await SellSubmissionStatePrefs.loadAll();
        for (final r in all) {
          if (r.ownerUserId == ownerId) {
            await SellSubmissionStatePrefs.remove(r.draftId);
          }
        }
      },
      'scoped_local_data': () => AccountLocalData.purgeOwner(ownerId),
    };
    for (final entry in steps.entries) {
      try {
        await entry.value();
      } catch (e, st) {
        // One failing store must not leave the others undeleted.
        logNonFatal(e, st, 'AccountDataPurge.${entry.key}');
      }
    }
  }
}
