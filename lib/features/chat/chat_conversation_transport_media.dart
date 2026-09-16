part of 'chat_pages.dart';

mixin _ChatConversationTransportMedia on _ChatConversationTransportListing {
  void _mergeInFlightMediaPending() {
    final inFlight = OutgoingChatSendService.instance
        .inFlightMediaForConversation(widget.carId);
    if (inFlight.isEmpty) return;
    var added = false;
    for (final r in inFlight) {
      if (_messages.any((m) => m.id == r.tempMessageId)) continue;
      _messages.add(_pendingMessageFromInFlight(r));
      added = true;
    }
    if (added) {
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
  }

  /// F-11: reload durable pending sends for this conversation (persisted on
  /// a retryable REST-send failure — see `OutgoingChatSendService`) and
  /// merge any not already represented in [_messages] as pending bubbles,
  /// so a failed send that outlived the page/app is visible again instead
  /// of silently vanishing. Call inside a `setState` after awaiting
  /// [ChatPendingSendPrefs.loadForConversation] separately (this method
  /// itself is synchronous so it can be used directly inside `setState`).
  void _mergePersistedPendingSends(List<ChatPendingSendRecord> records) {
    if (records.isEmpty) return;
    var added = false;
    for (final record in records) {
      if (_discardedOutgoingIds.contains(record.id)) continue;
      if (_messages.any((m) => m.id == record.id)) continue;
      _messages.add(_pendingMessageFromPersistedRecord(record));
      added = true;
    }
    if (added) {
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
  }

  List<ChatMediaEntry> _chatMediaEntries() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final myId = authService.userId ?? '';
    final myName = authService.userName.trim().isNotEmpty
        ? authService.userName.trim()
        : 'You';

    final entries = <ChatMediaEntry>[];
    for (final message in _messages) {
      if (message.attachments.isEmpty) continue;
      final senderName = message.senderId == myId
          ? myName
          : ((message.senderName ?? '').trim().isNotEmpty
                ? message.senderName!.trim()
                : (AppLocalizations.of(context)?.unknownSender ?? 'Unknown'));
      for (final attachment in message.attachments) {
        entries.add(
          ChatMediaEntry(attachment: attachment, senderName: senderName),
        );
      }
    }
    return entries;
  }

  void _openChatMediaViewer(
    ChatMessage message, {
    int initialAttachmentIndex = 0,
  }) {
    final entries = _chatMediaEntries();
    if (entries.isEmpty) return;

    var offset = 0;
    for (final item in _messages) {
      if (item.id == message.id) {
        final safeIndex = initialAttachmentIndex.clamp(
          0,
          item.attachments.isEmpty ? 0 : item.attachments.length - 1,
        );
        showChatMediaDialog(
          context,
          entries,
          initialIndex: offset + safeIndex,
        );
        return;
      }
      offset += item.attachments.length;
    }

    showChatMediaDialog(context, entries, initialIndex: 0);
  }
}
