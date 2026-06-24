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

  List<_ChatMediaEntry> _chatMediaEntries() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final myId = authService.userId ?? '';
    final myName = authService.userName.trim().isNotEmpty
        ? authService.userName.trim()
        : 'You';

    final entries = <_ChatMediaEntry>[];
    for (final message in _messages) {
      if (message.attachments.isEmpty) continue;
      final senderName = message.senderId == myId
          ? myName
          : ((message.senderName ?? '').trim().isNotEmpty
                ? message.senderName!.trim()
                : (AppLocalizations.of(context)?.unknownSender ?? 'Unknown'));
      for (final attachment in message.attachments) {
        entries.add(
          _ChatMediaEntry(attachment: attachment, senderName: senderName),
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
        _showChatMediaDialog(
          context,
          entries,
          initialIndex: offset + safeIndex,
        );
        return;
      }
      offset += item.attachments.length;
    }

    _showChatMediaDialog(context, entries, initialIndex: 0);
  }
}
