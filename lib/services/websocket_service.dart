import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';
import 'config.dart';

// Sideload build flag to allow LAN HTTP Socket.IO on iOS release builds.
const bool kSideloadBuild = bool.fromEnvironment(
  'SIDELOAD_BUILD',
  defaultValue: false,
);

DateTime parseApiDateTime(dynamic raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return DateTime.now();
  try {
    final parsed = DateTime.parse(text);
    final hasTimezone =
        text.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(text);
    if (hasTimezone) {
      return parsed.toLocal();
    }
    // Backend stores naive UTC timestamps; interpret them as UTC.
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).toLocal();
  } catch (_) {
    return DateTime.now();
  }
}

class WebSocketService {
  static final StreamController<Map<String, dynamic>> _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  static final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  static final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get messages => _messagesController.stream;
  static Stream<Map<String, dynamic>> get notifications =>
      _notificationsController.stream;
  static Stream<bool> get connectionState => _connectionController.stream;
  static Stream<String> get errors => _errorController.stream;
  static Stream<Map<String, dynamic>> get typingEvents => _typingController.stream;

  static String get baseHttpUrl => effectiveSocketIoBase();

  static io.Socket? _socket;
  static bool _isConnected = false;
  static bool _isConnecting = false;
  static String? _currentRoom;
  static final List<Map<String, dynamic>> _pendingEmits =
      <Map<String, dynamic>>[];

  // Callbacks
  static Function(Map<String, dynamic>)? onMessage;
  static Function(Map<String, dynamic>)? onNotification;
  static Function()? onConnected;
  static Function()? onDisconnected;
  static Function(String)? onError;

  static void _emitError(String message) {
    try {
      _errorController.add(message);
    } catch (_) {}
    onError?.call(message);
  }

  static void _emitConnected(bool connected) {
    try {
      _connectionController.add(connected);
    } catch (_) {}
    if (connected) {
      onConnected?.call();
    } else {
      onDisconnected?.call();
    }
  }

  static void _cleanupSocket() {
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }

  static void _flushPendingEmits() {
    if (_socket == null || !_isConnected) return;
    if (_pendingEmits.isEmpty) return;
    final pending = List<Map<String, dynamic>>.from(_pendingEmits);
    _pendingEmits.clear();
    for (final item in pending) {
      try {
        final event = (item['event'] ?? '').toString();
        final data = item['data'];
        if (event.isEmpty || data is! Map<String, dynamic>) continue;
        _socket!.emit(event, data);
      } catch (_) {}
    }
  }

  // Connect to Socket.IO (with polling fallback)
  static Future<void> connect() async {
    try {
      if (_isConnected) return;
      if (_isConnecting) return;
      _isConnecting = true;

      final accessToken = ApiService.accessToken;

      if (accessToken == null) {
        _emitError('No access token found');
        _isConnecting = false;
        return;
      }

      _cleanupSocket();

      final base = baseHttpUrl;
      if (kReleaseMode && !base.startsWith('https://')) {
        if (!(kSideloadBuild && Platform.isIOS && base.startsWith('http://'))) {
          throw StateError(
            'Release builds require HTTPS/WSS. Refusing insecure Socket.IO.',
          );
        }
      }

      final opts = <String, dynamic>{
        // Start with polling (universally compatible with any WSGI server),
        // then allow Engine.IO to probe for a websocket upgrade.  If the
        // server's async worker supports it (eventlet/gevent), future
        // messages will flow over a persistent websocket.  If the server
        // does NOT support it (gthread/sync), the upgrade probe silently
        // fails and the connection stays on polling — no crash, no error.
        'transports': ['polling', 'websocket'],
        'upgrade': true,
        'rememberUpgrade': true,
        'path': '/socket.io/',
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': 10,
        'reconnectionDelay': 500,
        'reconnectionDelayMax': 3000,
        'timeout': 10000,
        'extraHeaders': {HttpHeaders.authorizationHeader: 'Bearer $accessToken'},
      };

      _socket = io.io(base, opts);

      _socket!.on('connect', (_) {
        _isConnected = true;
        _isConnecting = false;
        _emitConnected(true);
        _flushPendingEmits();
        // Re-join room if we had one.
        final roomCar = _currentRoom;
        if (roomCar != null && roomCar.isNotEmpty) {
          joinChat(roomCar);
        }
      });

      _socket!.on('disconnect', (_) {
        _isConnected = false;
        _isConnecting = false;
        _emitConnected(false);
      });

      _socket!.on('connect_error', (err) {
        _isConnected = false;
        _isConnecting = false;
        _emitConnected(false);
        _emitError('Socket connect error: $err');
      });

      _socket!.on('error', (err) {
        final msg = (err is Map && err['message'] != null) ? err['message'].toString() : err.toString();
        _emitError(msg);
      });

      _socket!.on('new_message', (payload) {
        if (payload is Map) {
          final m = Map<String, dynamic>.from(payload as Map);
          _messagesController.add(m);
          onMessage?.call(m);
        }
      });

      _socket!.on('new_notification', (payload) {
        if (payload is Map) {
          final n = Map<String, dynamic>.from(payload as Map);
          _notificationsController.add(n);
          onNotification?.call(n);
        }
      });

      _socket!.on('typing', (payload) {
        if (payload is Map) {
          final t = Map<String, dynamic>.from(payload as Map);
          _typingController.add(t);
        }
      });

      _socket!.on('joined_chat', (payload) {
        try {
          if (payload is Map && payload['car_id'] != null) {
            _currentRoom = payload['car_id'].toString();
          }
        } catch (_) {}
      });

      _socket!.connect();
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      _cleanupSocket();
      _emitConnected(false);
      _emitError('Connection failed: $e');
    }
  }

  // Disconnect
  static void disconnect() {
    try {
      _socket?.disconnect();
    } catch (_) {}
    _cleanupSocket();
    _isConnected = false;
    _isConnecting = false;
    _currentRoom = null;
    _pendingEmits.clear();
    _emitConnected(false);
  }

  static void sendMessage(String event, Map<String, dynamic> data) {
    try {
      if (_socket == null || !_isConnected) {
        _pendingEmits.add(<String, dynamic>{
          'event': event,
          'data': Map<String, dynamic>.from(data),
        });
        unawaited(connect());
        return;
      }
      _socket!.emit(event, data);
    } catch (e) {
      _emitError('Send message error: $e');
    }
  }

  // Join chat room
  static void joinChat(String carId) {
    sendMessage('join_chat', {'car_id': carId});
  }

  // Leave current chat room
  static void leaveChat() {
    final carId = _currentRoom;
    if (carId != null && carId.isNotEmpty) {
      // Best-effort: server will handle missing room, but we can compute it.
      sendMessage('leave_chat', {'room': 'chat:$carId'});
      _currentRoom = null;
    }
  }

  // Send chat message
  static void sendChatMessage(
    String carId,
    String content, {
    String? receiverId,
    Map<String, dynamic>? listingPreview,
  }) {
    final messageData = <String, dynamic>{'car_id': carId, 'content': content};

    if (receiverId != null) {
      messageData['receiver_id'] = receiverId;
    }
    if (listingPreview != null && listingPreview.isNotEmpty) {
      messageData['listing_preview'] = listingPreview;
    }

    sendMessage('send_message', messageData);
  }

  static void sendTypingStart(String carId) {
    sendMessage('typing_start', {'car_id': carId});
  }

  static void sendTypingStop(String carId) {
    sendMessage('typing_stop', {'car_id': carId});
  }

  static bool get isConnected => _isConnected;

  // Get current room
  static String? get currentRoom => _currentRoom;
}

// Chat message model
class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String? carId;
  final String content;
  final String messageType;
  final String? attachmentUrl;
  final Map<String, dynamic>? listingPreview;
  final bool isRead;
  final DateTime createdAt;
  final String? senderName;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.carId,
    required this.content,
    required this.messageType,
    this.attachmentUrl,
    this.listingPreview,
    required this.isRead,
    required this.createdAt,
    this.senderName,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] ?? json['public_id'] ?? '').toString(),
      senderId: (json['sender_id'] ?? '').toString(),
      receiverId: (json['receiver_id'] ?? '').toString(),
      carId: json['car_id']?.toString(),
      content: (json['content'] ?? '').toString(),
      messageType: (json['message_type'] ?? 'text').toString(),
      attachmentUrl: json['attachment_url']?.toString(),
      listingPreview: json['listing_preview'] is Map
          ? Map<String, dynamic>.from(
              (json['listing_preview'] as Map).cast<String, dynamic>(),
            )
          : null,
      isRead: json['is_read'] == true,
      createdAt: parseApiDateTime(json['created_at']),
      senderName: json['sender_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'car_id': carId,
      'content': content,
      'message_type': messageType,
      'attachment_url': attachmentUrl,
      'listing_preview': listingPreview,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
      'sender_name': senderName,
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
