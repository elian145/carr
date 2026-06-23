/// Chat message from REST or WebSocket payloads.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    this.createdAt,
    this.messageType,
    this.mediaUrl,
    this.isRead = false,
    this.raw = const {},
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime? createdAt;
  final String? messageType;
  final String? mediaUrl;
  final bool isRead;
  final Map<String, dynamic> raw;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final id = json['id'] ?? json['message_id'];
    return ChatMessage(
      id: id?.toString() ?? '',
      conversationId: (json['conversation_id'] ?? json['chat_id'] ?? '')
          .toString(),
      senderId: (json['sender_id'] ?? json['user_id'] ?? '').toString(),
      body: (json['body'] ?? json['content'] ?? json['message'] ?? '')
          .toString(),
      createdAt: _parseDate(json['created_at'] ?? json['timestamp']),
      messageType: json['message_type']?.toString(),
      mediaUrl: (json['media_url'] ?? json['attachment_url'])?.toString(),
      isRead: json['is_read'] == true || json['read'] == true,
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'body': body,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (messageType != null) 'message_type': messageType,
    if (mediaUrl != null) 'media_url': mediaUrl,
    'is_read': isRead,
  };

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
