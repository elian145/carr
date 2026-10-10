/// Live chat transport strategy (P-10 / CHAT-2).
///
/// **Receive:** Socket.IO realtime (`WebSocketService`) for new messages, typing,
/// edits, deletes, and read receipts while connected.
///
/// **Send (text):** always REST via `OutgoingChatSendService` (pending bubble,
/// idempotency, retry). Never WebSocket emit — a stale connected flag would
/// clear the composer with no ACK and silently drop the message (CHAT-2).
///
/// **Fallback poll:** HTTP history poll only when the socket is disconnected
/// (or on app resume while offline from the socket).
///
/// Engine.IO may still negotiate `polling` ↔ `websocket` under the hood; that is
/// separate from the app-level REST poll gated here.
library;

/// Whether the conversation should run periodic REST polls for new messages.
bool shouldHttpPollChatMessages({required bool socketConnected}) =>
    !socketConnected;

/// Interval for the HTTP fallback poll (socket down only).
const Duration kChatHttpFallbackPollInterval = Duration(seconds: 12);

/// CHAT-2 policy lock: text send must not use Socket.IO emit, even when the
/// socket reports connected. Media/audio already used REST; text joins them.
bool chatTextSendUsesWebSocket({required bool socketConnected}) => false;

String normalizeChatMessageType(String? raw) {
  final t = (raw ?? '').trim().toLowerCase();
  return t.isEmpty ? 'text' : t;
}

/// Collapse a local pending bubble when the server message arrives (REST
/// response and/or Socket.IO `new_message`) so the UI never shows duplicates.
///
/// Matching is by stable id, or FIFO among pending rows with the same sender
/// and message type — **not** by text content — so two intentional identical
/// messages remain two bubbles.
bool shouldCollapsePendingChatBubble({
  required bool incomingIsPending,
  required String incomingId,
  required String incomingSenderId,
  required String incomingMessageType,
  required String pendingId,
  required bool pendingIsPending,
  required String pendingSenderId,
  required String pendingMessageType,
}) {
  if (incomingIsPending) return false;
  if (incomingId.isNotEmpty && incomingId == pendingId) return true;
  if (!pendingIsPending) return false;
  if (incomingSenderId.isEmpty || incomingSenderId != pendingSenderId) {
    return false;
  }
  return normalizeChatMessageType(incomingMessageType) ==
      normalizeChatMessageType(pendingMessageType);
}

/// Apply [incoming] onto [ids] / parallel pending flags (test helper for FIFO).
///
/// Each entry is `(id, senderId, messageType, isPending)`. Returns updated list.
List<(String id, String senderId, String type, bool pending)>
    mergeChatMessageAvoidingPendingDup(
  List<(String id, String senderId, String type, bool pending)> rows,
  (String id, String senderId, String type, bool pending) incoming,
) {
  final out = List<(String, String, String, bool)>.from(rows);
  final byId = out.indexWhere((r) => r.$1 == incoming.$1);
  if (byId != -1) {
    out[byId] = incoming;
    return out;
  }
  if (!incoming.$4) {
    final pendingIdx = out.indexWhere(
      (r) => shouldCollapsePendingChatBubble(
        incomingIsPending: incoming.$4,
        incomingId: incoming.$1,
        incomingSenderId: incoming.$2,
        incomingMessageType: incoming.$3,
        pendingId: r.$1,
        pendingIsPending: r.$4,
        pendingSenderId: r.$2,
        pendingMessageType: r.$3,
      ),
    );
    if (pendingIdx != -1) {
      out[pendingIdx] = incoming;
      return out;
    }
  }
  out.add(incoming);
  return out;
}
