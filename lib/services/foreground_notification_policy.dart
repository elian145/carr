/// Foreground push-notification policy (chat banners).
///
/// Two independent pieces, both pure/testable without Firebase or a widget
/// tree:
///
/// 1. [decideForegroundNotification] -- should a push that arrived while the
///    app is in the foreground be shown as a banner, or is the user already
///    looking at that very conversation?
/// 2. [ChatConversationPresence] -- the registry the conversation screen uses
///    to say "this conversation is open", so (1) can tell.
///
/// Design rule: a banner is suppressed ONLY when every signal positively says
/// the user is looking at the matching conversation right now. Anything
/// missing, stale or ambiguous shows the banner (a duplicate banner is a minor
/// annoyance; a swallowed message notification is a defect).
library;

import 'package:flutter/widgets.dart';

/// iOS foreground presentation of a remote (FCM) notification handled by the
/// OS itself. Deliberately NONE: Dart receives every foreground push through
/// `FirebaseMessaging.onMessage` and shows exactly one local notification
/// (or none, see [decideForegroundNotification]). With the OS also presenting
/// it (the old `alert: true`), iOS showed two identical banners. Android never
/// presents `notification` pushes of a foreground app, so it was already
/// single. Background / terminated pushes are presented by the OS regardless
/// of these options.
const ({bool alert, bool badge, bool sound}) kIosNativeForegroundPresentation =
    (alert: false, badge: false, sound: false);

/// Why [decideForegroundNotification] chose what it chose (for logs/tests).
enum ForegroundNotificationReason {
  /// Not a chat message: always shown.
  notChatMessage,

  /// App is not `resumed` (inactive/paused/hidden/unknown): always shown.
  appNotResumed,

  /// The push does not carry a usable `car_id` and `sender_id`: shown.
  missingIdentity,

  /// No conversation screen is registered.
  noConversation,

  /// A conversation for this listing exists but not with this sender.
  otherConversation,

  /// The matching conversation is open but covered by another route/dialog,
  /// or no longer mounted.
  conversationHidden,

  /// The open conversation's counterpart is not known, so the sender cannot
  /// be matched with certainty.
  peerUnknown,

  /// The screen belongs to a different account than the signed-in one.
  accountMismatch,

  /// The realtime socket is down, so the message would not appear on screen
  /// promptly; the banner is the user's only signal.
  realtimeDown,

  /// The user is actively viewing the matching conversation.
  activeConversation,
}

class ForegroundNotificationDecision {
  const ForegroundNotificationDecision(this.reason, {required this.suppress});

  /// True only for [ForegroundNotificationReason.activeConversation].
  final bool suppress;
  final ForegroundNotificationReason reason;

  bool get show => !suppress;

  @override
  String toString() =>
      'ForegroundNotificationDecision(${suppress ? 'suppress' : 'show'}, $reason)';
}

/// FCM data values are strings (`str(v)` on the server), so a missing id
/// arrives as "None"/"null" rather than being absent.
String _id(Object? v) {
  final s = (v ?? '').toString().trim();
  final lower = s.toLowerCase();
  if (lower == 'none' || lower == 'null') return '';
  return s;
}

/// Point-in-time view of one registered conversation screen.
class ChatConversationSnapshot {
  const ChatConversationSnapshot({
    required this.carId,
    required this.peerId,
    required this.ownerId,
    required this.visible,
    required this.realtimeLive,
  });

  final String carId;

  /// The counterpart's public id, or empty/null when unknown.
  final String? peerId;

  /// Account the screen was opened for.
  final String? ownerId;

  /// The route is the top, active route of a mounted screen.
  final bool visible;

  /// The realtime socket is connected (messages appear on screen on their own).
  final bool realtimeLive;
}

/// Decides what to do with a push received while the app process is in the
/// foreground. Pure: all state is passed in.
ForegroundNotificationDecision decideForegroundNotification({
  required Map<String, dynamic> data,
  required AppLifecycleState? lifecycle,
  required String? currentAccountId,
  required Iterable<ChatConversationSnapshot> conversations,
}) {
  ForegroundNotificationDecision show(ForegroundNotificationReason r) =>
      ForegroundNotificationDecision(r, suppress: false);

  // Only an explicit chat message can ever be suppressed. Legacy payloads
  // without `type`, saved-search/price-drop alerts, dealer updates, ... are
  // never swallowed.
  if ((data['type'] ?? '').toString().trim() != 'chat_message') {
    return show(ForegroundNotificationReason.notChatMessage);
  }
  // `inactive` (notification shade, app switcher, call) and null (unknown)
  // are not "actively viewing".
  if (lifecycle != AppLifecycleState.resumed) {
    return show(ForegroundNotificationReason.appNotResumed);
  }
  final car = _id(data['car_id']);
  final sender = _id(data['sender_id']);
  if (car.isEmpty || sender.isEmpty) {
    return show(ForegroundNotificationReason.missingIdentity);
  }
  final me = _id(currentAccountId);

  var best = ForegroundNotificationReason.noConversation;
  for (final c in conversations) {
    if (_id(c.carId) != car) {
      continue; // different listing: irrelevant, keep looking
    }
    final peer = _id(c.peerId);
    if (peer.isNotEmpty && peer != sender) {
      best = ForegroundNotificationReason.otherConversation;
      continue;
    }
    if (!c.visible) {
      best = ForegroundNotificationReason.conversationHidden;
      continue;
    }
    if (peer.isEmpty) {
      best = ForegroundNotificationReason.peerUnknown;
      continue;
    }
    final owner = _id(c.ownerId);
    if (owner.isEmpty || me.isEmpty || owner != me) {
      best = ForegroundNotificationReason.accountMismatch;
      continue;
    }
    if (!c.realtimeLive) {
      best = ForegroundNotificationReason.realtimeDown;
      continue;
    }
    return const ForegroundNotificationDecision(
      ForegroundNotificationReason.activeConversation,
      suppress: true,
    );
  }
  return show(best);
}

/// Handle returned by [ChatConversationPresence.register]. Unregistering is
/// idempotent.
class ChatConversationPresenceHandle {
  ChatConversationPresenceHandle._(this._owner, this._entry);

  final ChatConversationPresence? _owner;
  final _PresenceEntry _entry;
  bool _released = false;

  bool get isRegistered => !_released;

  void unregister() {
    if (_released) return;
    _released = true;
    _owner?._remove(_entry);
  }
}

class _PresenceEntry {
  _PresenceEntry({
    required this.carId,
    required this.peerId,
    required this.ownerId,
    required this.isVisible,
    required this.isRealtimeLive,
  });

  final String Function() carId;
  final String? Function() peerId;
  final String? Function() ownerId;
  final bool Function() isVisible;
  final bool Function() isRealtimeLive;
}

/// Registry of the conversation screens that are currently mounted.
///
/// Entries hold closures that are evaluated lazily, WHEN a push arrives, so
/// there are no listeners to leak and nothing can go stale between route or
/// lifecycle changes: visibility is read at decision time. A screen registers
/// in `initState` and unregisters in `dispose`; a screen that is mounted but
/// covered (another page, dialog, sheet on top) reports `visible: false`.
class ChatConversationPresence {
  ChatConversationPresence();

  /// Process-wide registry used by the app.
  static final ChatConversationPresence instance = ChatConversationPresence();

  final List<_PresenceEntry> _entries = <_PresenceEntry>[];

  /// Number of registered screens (tests / leak checks).
  int get registeredCount => _entries.length;

  ChatConversationPresenceHandle register({
    required String Function() carId,
    required String? Function() peerId,
    required String? Function() ownerId,
    required bool Function() isVisible,
    required bool Function() isRealtimeLive,
  }) {
    final entry = _PresenceEntry(
      carId: carId,
      peerId: peerId,
      ownerId: ownerId,
      isVisible: isVisible,
      isRealtimeLive: isRealtimeLive,
    );
    _entries.add(entry);
    return ChatConversationPresenceHandle._(this, entry);
  }

  void _remove(_PresenceEntry entry) => _entries.remove(entry);

  /// Evaluates every registered screen now. A closure that throws (e.g. an
  /// element that is being torn down) is treated as "not visible".
  List<ChatConversationSnapshot> snapshots() {
    final out = <ChatConversationSnapshot>[];
    for (final e in List<_PresenceEntry>.of(_entries)) {
      try {
        out.add(
          ChatConversationSnapshot(
            carId: e.carId(),
            peerId: e.peerId(),
            ownerId: e.ownerId(),
            visible: e.isVisible(),
            realtimeLive: e.isRealtimeLive(),
          ),
        );
      } catch (_) {
        out.add(
          const ChatConversationSnapshot(
            carId: '',
            peerId: null,
            ownerId: null,
            visible: false,
            realtimeLive: false,
          ),
        );
      }
    }
    return out;
  }

  @visibleForTesting
  void debugClear() => _entries.clear();
}
