part of 'websocket_service.dart';

class ChatAttachment {
  final String type;
  final String url;
  final bool isLocal;

  const ChatAttachment({
    required this.type,
    required this.url,
    this.isLocal = false,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      type: (json['type'] ?? 'image').toString(),
      url: (json['url'] ?? '').toString(),
      isLocal: json['is_local'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'url': url,
      'is_local': isLocal,
    };
  }
}

class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String? carId;
  final String? replyToMessageId;
  final ChatReplyPreview? replyToMessage;
  final String content;
  final String messageType;
  final String? attachmentUrl;
  final List<ChatAttachment> attachments;
  final Map<String, dynamic>? listingPreview;
  final bool isRead;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime? editedAt;
  final String? senderName;
  final bool isPending;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.carId,
    this.replyToMessageId,
    this.replyToMessage,
    required this.content,
    required this.messageType,
    this.attachmentUrl,
    this.attachments = const [],
    this.listingPreview,
    required this.isRead,
    this.isDeleted = false,
    required this.createdAt,
    this.editedAt,
    this.senderName,
    this.isPending = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final messageType = (json['message_type'] ?? 'text').toString();
    final attachmentUrl = json['attachment_url']?.toString();
    final attachments = json['attachments'] is List
        ? (json['attachments'] as List)
            .whereType<Map>()
            .map((item) => ChatAttachment.fromJson(
                  Map<String, dynamic>.from(item.cast<String, dynamic>()),
                ))
            .where((item) => item.url.isNotEmpty)
            .toList()
        : <ChatAttachment>[];
    if (attachments.isEmpty &&
        attachmentUrl != null &&
        attachmentUrl.isNotEmpty &&
        (messageType == 'image' ||
            messageType == 'video' ||
            messageType == 'audio')) {
      attachments.add(ChatAttachment(type: messageType, url: attachmentUrl));
    }
    return ChatMessage(
      id: (json['id'] ?? json['public_id'] ?? '').toString(),
      senderId: (json['sender_id'] ?? '').toString(),
      receiverId: (json['receiver_id'] ?? '').toString(),
      carId: json['car_id']?.toString(),
      replyToMessageId: json['reply_to_message_id']?.toString(),
      replyToMessage: json['reply_to_message'] is Map
          ? ChatReplyPreview.fromJson(
              Map<String, dynamic>.from(
                (json['reply_to_message'] as Map).cast<String, dynamic>(),
              ),
            )
          : null,
      content: (json['content'] ?? '').toString(),
      messageType: messageType,
      attachmentUrl: attachmentUrl,
      attachments: attachments,
      listingPreview: json['listing_preview'] is Map
          ? Map<String, dynamic>.from(
              (json['listing_preview'] as Map).cast<String, dynamic>(),
            )
          : null,
      isRead: json['is_read'] == true,
      isDeleted: json['is_deleted'] == true,
      createdAt: parseApiDateTime(json['created_at']),
      editedAt: json['edited_at'] == null
          ? null
          : parseApiDateTime(json['edited_at']),
      senderName: json['sender_name']?.toString(),
      isPending: json['is_pending'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'car_id': carId,
      'reply_to_message_id': replyToMessageId,
      'reply_to_message': replyToMessage?.toJson(),
      'content': content,
      'message_type': messageType,
      'attachment_url': attachmentUrl,
      'attachments': attachments.map((item) => item.toJson()).toList(),
      'listing_preview': listingPreview,
      'is_read': isRead,
      'is_deleted': isDeleted,
      'created_at': createdAt.toIso8601String(),
      'edited_at': editedAt?.toIso8601String(),
      'sender_name': senderName,
      'is_pending': isPending,
    };
  }

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? carId,
    String? replyToMessageId,
    ChatReplyPreview? replyToMessage,
    bool clearReplyToMessage = false,
    String? content,
    String? messageType,
    String? attachmentUrl,
    List<ChatAttachment>? attachments,
    Map<String, dynamic>? listingPreview,
    bool clearListingPreview = false,
    bool? isRead,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? editedAt,
    bool clearEditedAt = false,
    String? senderName,
    bool? isPending,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      carId: carId ?? this.carId,
      replyToMessageId: clearReplyToMessage
          ? null
          : replyToMessageId ?? this.replyToMessageId,
      replyToMessage: clearReplyToMessage
          ? null
          : replyToMessage ?? this.replyToMessage,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      attachments: attachments ?? this.attachments,
      listingPreview: clearListingPreview
          ? null
          : listingPreview ?? this.listingPreview,
      isRead: isRead ?? this.isRead,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      editedAt: clearEditedAt ? null : editedAt ?? this.editedAt,
      senderName: senderName ?? this.senderName,
      isPending: isPending ?? this.isPending,
    );
  }
}

class ChatReplyPreview {
  final String id;
  final String? senderId;
  final String? senderName;
  final String content;
  final String messageType;
  final bool isDeleted;

  ChatReplyPreview({
    required this.id,
    this.senderId,
    this.senderName,
    required this.content,
    required this.messageType,
    this.isDeleted = false,
  });

  factory ChatReplyPreview.fromJson(Map<String, dynamic> json) {
    return ChatReplyPreview(
      id: (json['id'] ?? '').toString(),
      senderId: json['sender_id']?.toString(),
      senderName: json['sender_name']?.toString(),
      content: (json['content'] ?? '').toString(),
      messageType: (json['message_type'] ?? 'text').toString(),
      isDeleted: json['is_deleted'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'message_type': messageType,
      'is_deleted': isDeleted,
    };
  }
}

// Notification model
class AppNotification {
  final String id;
  final String title;
  final String message;
  final String notificationType;
  final bool isRead;
  final Map<String, dynamic>? data;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.notificationType,
    required this.isRead,
    this.data,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      notificationType: (json['notification_type'] ?? 'message').toString(),
      isRead: json['is_read'] == true,
      data: json['data'] is Map<String, dynamic> ? json['data'] : null,
      createdAt: parseApiDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'notification_type': notificationType,
      'is_read': isRead,
      'data': data,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
