part of 'websocket_service.dart';

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
  static final StreamController<Map<String, dynamic>> _messageUpdatesController =
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<Map<String, dynamic>> _messageDeletesController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get messages => _messagesController.stream;
  static Stream<Map<String, dynamic>> get notifications =>
      _notificationsController.stream;
  static Stream<bool> get connectionState => _connectionController.stream;
  static Stream<String> get errors => _errorController.stream;
  static Stream<Map<String, dynamic>> get typingEvents => _typingController.stream;
  static Stream<Map<String, dynamic>> get messageUpdates =>
      _messageUpdatesController.stream;
  static Stream<Map<String, dynamic>> get messageDeletes =>
      _messageDeletesController.stream;

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
    } catch (e, st) { logNonFatal(e, st); }
    onError?.call(message);
  }

  static void _emitConnected(bool connected) {
    try {
      _connectionController.add(connected);
    } catch (e, st) { logNonFatal(e, st); }
    if (connected) {
      onConnected?.call();
    } else {
      onDisconnected?.call();
    }
  }

  static void _cleanupSocket() {
    try {
      _socket?.dispose();
    } catch (e, st) { logNonFatal(e, st); }
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
      } catch (e, st) { logNonFatal(e, st); }
    }
  }

  // Connect to Socket.IO (with polling fallback)
  static Future<void> connect() async {
    // Widget/integration tests stub HTTP via [ApiService.testHttpClient]; skip real sockets.
    if (ApiService.isTestHttpClientBound) return;

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
          final m = Map<String, dynamic>.from(payload);
          _messagesController.add(m);
          onMessage?.call(m);
        }
      });

      _socket!.on('message_updated', (payload) {
        if (payload is Map) {
          _messageUpdatesController.add(Map<String, dynamic>.from(payload));
        }
      });

      _socket!.on('message_deleted', (payload) {
        if (payload is Map) {
          _messageDeletesController.add(Map<String, dynamic>.from(payload));
        }
      });

      _socket!.on('new_notification', (payload) {
        if (payload is Map) {
          final n = Map<String, dynamic>.from(payload);
          _notificationsController.add(n);
          onNotification?.call(n);
        }
      });

      _socket!.on('typing', (payload) {
        if (payload is Map) {
          final t = Map<String, dynamic>.from(payload);
          _typingController.add(t);
        }
      });

      _socket!.on('joined_chat', (payload) {
        try {
          if (payload is Map && payload['car_id'] != null) {
            _currentRoom = payload['car_id'].toString();
          }
        } catch (e, st) { logNonFatal(e, st); }
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
    } catch (e, st) { logNonFatal(e, st); }
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
    String? replyToMessageId,
  }) {
    final messageData = <String, dynamic>{'car_id': carId, 'content': content};

    if (receiverId != null) {
      messageData['receiver_id'] = receiverId;
    }
    if (listingPreview != null && listingPreview.isNotEmpty) {
      messageData['listing_preview'] = listingPreview;
    }
    if (replyToMessageId != null && replyToMessageId.trim().isNotEmpty) {
      messageData['reply_to_message_id'] = replyToMessageId.trim();
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
