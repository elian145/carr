import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'api_service.dart';
import 'config.dart';

class WebSocketService {
  // If false, we attempt to authenticate via headers only (preferred), and do NOT
  // include the token in the URL query string. Keep true by default for backward
  // compatibility with servers that only support ?token=... on the Socket.IO WS upgrade.
  static const bool _tokenInQuery = bool.fromEnvironment(
    'WS_TOKEN_IN_QUERY',
    defaultValue: true,
  );

  static final StreamController<Map<String, dynamic>> _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  static final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  static Stream<Map<String, dynamic>> get messages => _messagesController.stream;
  static Stream<Map<String, dynamic>> get notifications =>
      _notificationsController.stream;
  static Stream<bool> get connectionState => _connectionController.stream;
  static Stream<String> get errors => _errorController.stream;

  static String get baseUrl {
    final base = apiBase();
    if (base.startsWith('https://')) {
      return base.replaceFirst('https://', 'wss://');
    }
    if (base.startsWith('http://')) {
      return base.replaceFirst('http://', 'ws://');
    }
    return 'ws://$base';
  }

  static WebSocketChannel? _channel;
  static bool _isConnected = false;
  static bool _isConnecting = false;
  static String? _currentRoom;
  static int _retries = 0;
  static DateTime? _lastAttemptAt;
  static Timer? _heartbeatTimer;
  static final List<String> _pendingFrames = <String>[];
  static const int _maxPendingFrames = 50;

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

  static void _cleanupChannel() {
    try {
      _channel?.sink.close(status.goingAway);
    } catch (_) {}
    _channel = null;
    _stopHeartbeat();
  }

  static void _flushPending() {
    if (!_isConnected || _channel == null) return;
    if (_pendingFrames.isEmpty) return;
    final frames = List<String>.from(_pendingFrames);
    _pendingFrames.clear();
    for (final frame in frames) {
      try {
        _channel!.sink.add(frame);
      } catch (e) {
        _emitError('Send pending frame failed: $e');
        // Put remaining back (best effort) and stop flushing.
        final idx = frames.indexOf(frame);
        if (idx >= 0 && idx + 1 < frames.length) {
          _pendingFrames.addAll(frames.sublist(idx + 1));
        }
        break;
      }
    }
  }

  // Connect to WebSocket
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

      // Ensure any stale channel is cleaned up before re-connecting
      _cleanupChannel();

      final qp = <String, String>{
        'EIO': '4',
        'transport': 'websocket',
        if (_tokenInQuery) 'token': accessToken,
      };
      final uri = Uri.parse('$baseUrl/socket.io/').replace(queryParameters: qp);

      // Prefer IO channel so we can attach Authorization header.
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {HttpHeaders.authorizationHeader: 'Bearer $accessToken'},
      );

      _channel!.stream.listen(
        (data) {
          _handleMessage(data);
        },
        onError: (error) {
          _isConnected = false;
          _isConnecting = false;
          _cleanupChannel();
          _emitConnected(false);
          _emitError('WebSocket error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          _isConnecting = false;
          _cleanupChannel();
          _emitConnected(false);
          _scheduleReconnect();
        },
      );

      _isConnected = true;
      _isConnecting = false;
      _emitConnected(true);
      _startHeartbeat();
      _flushPending();
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      _cleanupChannel();
      _emitConnected(false);
      _emitError('Connection failed: $e');
      _scheduleReconnect();
    }
  }

  // Disconnect from WebSocket
  static void disconnect() {
    _cleanupChannel();
    _isConnected = false;
    _isConnecting = false;
    _currentRoom = null;
    _retries = 0;
    _lastAttemptAt = null;
    _emitConnected(false);
  }

  static void _scheduleReconnect() {
    if (_isConnected) return;
    final now = DateTime.now();
    if (_lastAttemptAt != null &&
        now.difference(_lastAttemptAt!).inSeconds < 2) {
      return;
    }
    _lastAttemptAt = now;
    _retries = (_retries + 1).clamp(1, 6);
    final delayMs = (500 * _retries);
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!_isConnected) {
        connect();
      }
    });
  }

  static void _startHeartbeat() {
    _stopHeartbeat();
    // Socket.IO ping frame is '2'
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        if (_isConnected && _channel != null) {
          _channel!.sink.add('2');
        }
      } catch (_) {}
    });
  }

  static void _stopHeartbeat() {
    try {
      _heartbeatTimer?.cancel();
    } catch (_) {}
    _heartbeatTimer = null;
  }

  // Handle incoming messages
  static void _handleMessage(dynamic data) {
    try {
      final message = data.toString();

      // Handle Socket.IO protocol messages
      if (message.startsWith('0')) {
        // Connection acknowledgment
        return;
      } else if (message.startsWith('40')) {
        // Connected to namespace
        return;
      } else if (message.startsWith('42')) {
        // Event message
        final eventData = message.substring(2);
        final decoded = json.decode(eventData);

        if (decoded is List && decoded.length >= 2) {
          final eventName = decoded[0];
          final eventPayload = decoded[1];

          switch (eventName) {
            case 'connected':
              _isConnected = true;
              _emitConnected(true);
              break;
            case 'new_message':
              if (eventPayload is Map<String, dynamic>) {
                _messagesController.add(eventPayload);
                onMessage?.call(eventPayload);
              }
              break;
            case 'new_notification':
              if (eventPayload is Map<String, dynamic>) {
                _notificationsController.add(eventPayload);
                onNotification?.call(eventPayload);
              }
              break;
            case 'joined_chat':
              _currentRoom = eventPayload['room'];
              break;
          }
        }
      }
    } catch (e) {
      _emitError('Message parsing error: $e');
    }
  }

  // Send message
  static void sendMessage(String event, Map<String, dynamic> data) {
    try {
      final message = json.encode([event, data]);
      final frame = '42$message';
      if (!_isConnected || _channel == null) {
        // Queue and connect (best-effort) to avoid dropping user actions.
        if (_pendingFrames.length >= _maxPendingFrames) {
          _pendingFrames.removeAt(0);
        }
        _pendingFrames.add(frame);
        // Fire-and-forget connect; once connected we'll flush.
        unawaited(connect());
        return;
      }
      _channel!.sink.add(frame);
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
    if (_currentRoom != null) {
      sendMessage('leave_chat', {'room': _currentRoom});
      _currentRoom = null;
    }
  }

  // Send chat message
  static void sendChatMessage(
    String carId,
    String content, {
    String? receiverId,
  }) {
    final messageData = {'car_id': carId, 'content': content};

    if (receiverId != null) {
      messageData['receiver_id'] = receiverId;
    }

    sendMessage('send_message', messageData);
  }

  // Check connection status
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
    required this.isRead,
    required this.createdAt,
    this.senderName,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      senderId: json['sender_id'],
      receiverId: json['receiver_id'],
      carId: json['car_id'],
      content: json['content'],
      messageType: json['message_type'],
      isRead: json['is_read'],
      createdAt: DateTime.parse(json['created_at']),
      senderName: json['sender_name'],
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
      id: json['id'],
      title: json['title'],
      message: json['message'],
      notificationType: json['notification_type'],
      isRead: json['is_read'],
      data: json['data'],
      createdAt: DateTime.parse(json['created_at']),
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
