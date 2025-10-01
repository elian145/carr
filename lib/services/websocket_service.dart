import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class WebSocketService {
  static String get baseUrl {
    if (Platform.isAndroid) return 'ws://10.0.2.2:5000';
    return 'ws://localhost:5000';
  }
  static WebSocketChannel? _channel;
  static bool _isConnected = false;
  static String? _currentRoom;
  static int _retries = 0;
  static DateTime? _lastAttemptAt;
  static Timer? _heartbeatTimer;
  
  // Callbacks
  static Function(Map<String, dynamic>)? onMessage;
  static Function(Map<String, dynamic>)? onNotification;
  static Function()? onConnected;
  static Function()? onDisconnected;
  static Function(String)? onError;

  // Connect to WebSocket
  static Future<void> connect() async {
    try {
      if (_isConnected) return;

      final accessToken = ApiService.accessToken;
      
      if (accessToken == null) {
        onError?.call('No access token found');
        return;
      }

      final uri = Uri.parse('$baseUrl/socket.io/?EIO=4&transport=websocket&token=$accessToken');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (data) {
          _handleMessage(data);
        },
        onError: (error) {
          _isConnected = false;
          onError?.call('WebSocket error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          onDisconnected?.call();
          _scheduleReconnect();
        },
      );

      _isConnected = true;
      onConnected?.call();
      _startHeartbeat();
      
    } catch (e) {
      _isConnected = false;
      onError?.call('Connection failed: $e');
      _scheduleReconnect();
    }
  }

  // Disconnect from WebSocket
  static void disconnect() {
    _channel?.sink.close(status.goingAway);
    _channel = null;
    _isConnected = false;
    _currentRoom = null;
    _retries = 0;
    _lastAttemptAt = null;
    _stopHeartbeat();
  }

  static void _scheduleReconnect() {
    if (_isConnected) return;
    final now = DateTime.now();
    if (_lastAttemptAt != null && now.difference(_lastAttemptAt!).inSeconds < 2) return;
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
    try { _heartbeatTimer?.cancel(); } catch (_) {}
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
              onConnected?.call();
              break;
            case 'new_message':
              onMessage?.call(eventPayload);
              break;
            case 'new_notification':
              onNotification?.call(eventPayload);
              break;
            case 'joined_chat':
              _currentRoom = eventPayload['room'];
              break;
          }
        }
      }
    } catch (e) {
      onError?.call('Message parsing error: $e');
    }
  }

  // Send message
  static void sendMessage(String event, Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      onError?.call('Not connected to WebSocket');
      return;
    }

    try {
      final message = json.encode([event, data]);
      _channel!.sink.add('42$message');
    } catch (e) {
      onError?.call('Send message error: $e');
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
  static void sendChatMessage(String carId, String content, {String? receiverId}) {
    final messageData = {
      'car_id': carId,
      'content': content,
    };
    
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
