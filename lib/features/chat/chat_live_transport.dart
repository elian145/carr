/// Live chat transport strategy (P-10).
///
/// **Primary:** Socket.IO realtime (`WebSocketService`) for new messages, typing,
/// edits, deletes, and read receipts while connected.
///
/// **Fallback:** HTTP history poll only when the socket is disconnected (or on
/// app resume while offline from the socket). This avoids dual transport
/// battery drain from polling every few seconds on top of an active socket.
///
/// Engine.IO may still negotiate `polling` ↔ `websocket` under the hood; that is
/// separate from the app-level REST poll gated here.
library;

/// Whether the conversation should run periodic REST polls for new messages.
bool shouldHttpPollChatMessages({required bool socketConnected}) =>
    !socketConnected;

/// Interval for the HTTP fallback poll (socket down only).
const Duration kChatHttpFallbackPollInterval = Duration(seconds: 12);
