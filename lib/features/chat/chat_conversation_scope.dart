/// Which realtime events belong to ONE open conversation.
///
/// A conversation is (listing, me, ONE counterpart). A listing seller talks to
/// several buyers about the same listing, so the car id alone is not enough:
/// without the counterpart, buyer B's message, typing indicator or read receipt
/// would show up inside buyer A's thread (F-05 / F-25).
///
/// Pure functions so the rules are unit-testable without a widget tree.
library;

class ChatConversationScope {
  const ChatConversationScope({
    required this.carId,
    required this.myId,
    this.peerId,
  });

  /// Listing the conversation is about.
  final String carId;

  /// The signed-in account (public id), when known.
  final String? myId;

  /// The OTHER participant (public id), when known. `null` only for a buyer
  /// opening a listing without naming the seller: their counterpart is
  /// implicitly the seller, and the server only ever sends them their own
  /// conversation.
  final String? peerId;

  String? get _peer {
    final p = peerId?.trim();
    return (p == null || p.isEmpty) ? null : p;
  }

  String? get _me {
    final m = myId?.trim();
    return (m == null || m.isEmpty) ? null : m;
  }

  static String _s(Object? v) => (v ?? '').toString().trim();

  bool _carMatches(Map<String, dynamic> event) {
    final car = _s(event['car_id']);
    return car.isEmpty || car == carId;
  }

  /// A chat message (new / updated / deleted) of THIS conversation: same
  /// listing AND exchanged between me and the counterpart.
  bool matchesMessage(Map<String, dynamic> message) {
    if (!_carMatches(message)) return false;
    final peer = _peer;
    if (peer == null) return true;
    final sender = _s(message['sender_id']);
    final receiver = _s(message['receiver_id']);
    if (sender.isEmpty && receiver.isEmpty) return true; // legacy payload
    final me = _me;
    if (me != null) {
      return (sender == me && receiver == peer) ||
          (sender == peer && receiver == me);
    }
    return sender == peer || receiver == peer;
  }

  /// A typing indicator of THIS conversation: sent BY the counterpart, for this
  /// listing, and addressed to me.
  bool matchesTyping(Map<String, dynamic> event) {
    if (!_carMatches(event)) return false;
    final from = _s(event['user_id']);
    final peer = _peer;
    final me = _me;
    if (me != null && from == me) return false; // never show my own
    if (peer != null && from != peer) return false;
    final addressedTo = _s(event['peer_id']);
    if (addressedTo.isNotEmpty && me != null && addressedTo != me) return false;
    return true;
  }

  /// A read receipt of THIS conversation: the counterpart read my messages.
  bool matchesRead(Map<String, dynamic> event) {
    if (!_carMatches(event)) return false;
    final peer = _peer;
    if (peer == null) return true;
    final reader = _s(event['reader_id']);
    return reader.isEmpty || reader == peer;
  }
}
