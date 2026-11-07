part of 'websocket_service.dart';

/// The slice of a Socket.IO client the service relies on. A thin adapter so
/// the authentication / conversation logic can be exercised with a fake socket
/// (see `debugSocketFactory`); production wraps `socket_io_client`.
abstract class WsSocket {
  void on(String event, void Function(dynamic data) handler);
  void emit(String event, dynamic data);
  void connect();
  void disconnect();
  void dispose();
}

class _IoWsSocket implements WsSocket {
  _IoWsSocket(this._socket);
  final io.Socket _socket;

  @override
  void on(String event, void Function(dynamic data) handler) {
    _socket.on(event, (dynamic data) => handler(data));
  }

  @override
  void emit(String event, dynamic data) => _socket.emit(event, data);

  @override
  void connect() => _socket.connect();

  @override
  void disconnect() => _socket.disconnect();

  @override
  void dispose() => _socket.dispose();
}

/// The conversation the screen currently shows: (listing, counterpart).
/// A listing seller talks to several buyers about one listing, so the car id
/// alone does not identify a conversation (F-05 / F-25).
class _ChatConversationRef {
  const _ChatConversationRef(this.carId, this.peerId);
  final String carId;
  final String? peerId;

  Map<String, dynamic> toPayload() => <String, dynamic>{
        'car_id': carId,
        if (peerId != null) 'peer_id': peerId,
      };
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
  static final StreamController<Map<String, dynamic>> _messageUpdatesController =
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<Map<String, dynamic>> _messageDeletesController =
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<Map<String, dynamic>> _messageReadsController =
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
  static Stream<Map<String, dynamic>> get messageReads =>
      _messageReadsController.stream;

  static String get baseHttpUrl => effectiveSocketIoBase();

  static WsSocket? _socket;
  static bool _isConnected = false;
  static bool _isConnecting = false;
  static String? _currentRoom;
  static final List<Map<String, dynamic>> _pendingEmits =
      <Map<String, dynamic>>[];

  // F-05/F-25: the conversation to (re)join, and the room the server put us in.
  static _ChatConversationRef? _conversation;
  static String? _serverRoom;

  // F-35: the socket is authenticated as ONE account (the bearer token it was
  // created with) and delivers that account's private chat/notification
  // events. It is therefore bound to the session it was created in and torn
  // down on every authentication transition; a socket from an ended session
  // can never be reused by the next one, and its late events are dropped.
  static AuthSessionSnapshot? _socketSession;
  static bool _accountScopeHooked = false;

  // F-36: the access token a socket authenticated with EXPIRES. The service
  // refreshes it for the same session before that happens and whenever the
  // server reports the token as expired/invalid, then rebuilds the socket with
  // the new token. It never reconnects under another account's credentials and
  // never connects with a token it knows is expired.
  static const Duration _refreshLeadTime = Duration(minutes: 2);
  static const Duration _minRefreshDelay = Duration(seconds: 5);
  static const Duration _connectExpiryMargin = Duration(seconds: 10);
  static const int _maxAuthRecoveries = 3;
  static int _connectGeneration = 0;
  static int _authRecoveries = 0;
  static bool _recoveringAuth = false;
  static Timer? _refreshTimer;

  static WsSocket Function(String base, Map<String, dynamic> options)?
      _socketFactory;
  static DateTime Function() _clock = DateTime.now;

  /// Test hook: build sockets with [factory] instead of `socket_io_client`
  /// (and connect even though a test HTTP client is bound).
  @visibleForTesting
  static set debugSocketFactory(
    WsSocket Function(String base, Map<String, dynamic> options)? factory,
  ) {
    _socketFactory = factory;
  }

  /// Test hook: the clock used for token-expiry decisions.
  @visibleForTesting
  static set debugClock(DateTime Function()? clock) {
    _clock = clock ?? DateTime.now;
  }

  /// Test hook: forget every piece of static state.
  @visibleForTesting
  static void debugReset() {
    disconnect();
    _socketFactory = null;
    _clock = DateTime.now;
    _authRecoveries = 0;
    _recoveringAuth = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  static void _hookAccountScope() {
    if (_accountScopeHooked) return;
    _accountScopeHooked = true;
    AccountScope.addSessionChangedListener(disconnect);
  }

  /// True when [session] is still the session the app is signed in under.
  static bool _isLive(AuthSessionSnapshot session, WsSocket? socket) =>
      identical(_socket, socket) && ApiService.isSessionCurrent(session);

  /// Still the same session AND the same account that [session] captured.
  static bool _sameAccount(AuthSessionSnapshot session) =>
      ApiService.isSessionCurrent(session) &&
      ApiService.currentAccountId == session.accountId;

  @visibleForTesting
  static int get debugPendingEmitCount => _pendingEmits.length;

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

  static WsSocket _defaultSocketFactory(
    String base,
    Map<String, dynamic> options,
  ) =>
      _IoWsSocket(io.io(base, options));

  /// True when [token] is a JWT that has expired (or will within [margin]).
  /// A token without a readable expiry (opaque / legacy) is NOT treated as
  /// expired: the server stays the authority and answers with `auth_expired`.
  static bool _isExpiredOrExpiring(String? token, Duration margin) {
    final exp = jwtExpiry(token);
    if (exp == null) return false;
    return !exp.isAfter(_clock().toUtc().add(margin));
  }

  /// Does a server / transport error mean "your token is no good"?
  static bool _isAuthFailure(Object? err) {
    final text = (err is Map ? (err['message'] ?? err['data'] ?? err) : err)
        .toString()
        .toLowerCase();
    return text.contains('token_expired') ||
        text.contains('invalid_token') ||
        text.contains('token_revoked') ||
        text.contains('unauthorized') ||
        text.contains('expired');
  }

  // Connect to Socket.IO (with polling fallback)
  static Future<void> connect() async {
    // Widget/integration tests stub HTTP via [ApiService.testHttpClient]; skip real sockets.
    _hookAccountScope();
    if (_socketFactory == null && ApiService.isTestHttpClientBound) return;

    try {
      // A socket (connected or still connecting) that belongs to an ended
      // session must never be kept: tear it down and build a fresh one for
      // the current credentials.
      final existing = _socketSession;
      if ((_socket != null || _isConnected || _isConnecting) &&
          (existing == null || !ApiService.isSessionCurrent(existing))) {
        disconnect();
      }
      if (_isConnected) return;
      if (_isConnecting) return;
      _isConnecting = true;
      final generation = ++_connectGeneration;

      final session = ApiService.captureSession();
      var accessToken = ApiService.accessToken;

      if (accessToken == null) {
        _emitError('No access token found');
        _isConnecting = false;
        return;
      }

      // F-36: never open a socket with a token that is already expired (the
      // server would refuse it, and an old server would have silently demoted
      // it to a guest). Refresh it for THIS session first.
      if (_isExpiredOrExpiring(accessToken, _connectExpiryMargin)) {
        final refreshed = await ApiService.refreshAccessTokenForSession(session);
        if (generation != _connectGeneration) return; // superseded / torn down
        accessToken = ApiService.accessToken;
        if (!refreshed ||
            !_sameAccount(session) ||
            accessToken == null ||
            _isExpiredOrExpiring(accessToken, Duration.zero)) {
          _isConnecting = false;
          _emitConnected(false);
          _emitError('Session expired');
          return;
        }
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
        // WebSocket ONLY. On dart:io `socket_io_client` ships a single
        // transport implementation (IOWebSocketTransport): asked for
        // ['polling', 'websocket'] it opens a WebSocket handshake that is
        // labelled `transport=polling`, which the Engine.IO server answers as
        // a plain polling request (HTTP 200, no upgrade) -- the socket then
        // fails to connect over and over and never reaches the server, so no
        // realtime event that depends on a joined room (typing, read
        // receipts) is ever delivered. HTTP polling stays the app-level
        // fallback (see `shouldHttpPollChatMessages`).
        'transports': ['websocket'],
        // A FRESH Manager for every socket. socket_io_client otherwise
        // reuses a cached Manager for the same host together with the
        // extraHeaders (the bearer token) it was created with, so after an
        // account switch the new socket would authenticate as the PREVIOUS
        // account and be refused ('Socket account mismatch').
        'forceNew': true,
        'path': '/socket.io/',
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': 10,
        'reconnectionDelay': 500,
        'reconnectionDelayMax': 3000,
        'timeout': 10000,
        'extraHeaders': {HttpHeaders.authorizationHeader: 'Bearer $accessToken'},
      };

      final socket = (_socketFactory ?? _defaultSocketFactory)(base, opts);
      _socket = socket;
      _socketSession = session;

      socket.on('connect', (_) {
        if (!_isLive(session, socket)) return;
        _isConnected = true;
        _isConnecting = false;
        _emitConnected(true);
        // A queued join_chat (the usual first-connect case) is flushed below;
        // only re-join explicitly when none is waiting (a reconnect).
        final joinQueued =
            _pendingEmits.any((e) => e['event'] == 'join_chat');
        _flushPendingEmits();
        // Re-join the conversation we were in (car AND counterpart).
        final conversation = _conversation;
        if (conversation != null && !joinQueued) {
          sendMessage('join_chat', conversation.toPayload());
        }
      });

      // The server tells us who it authenticated us as and until when. A
      // socket that is NOT authenticated although we presented a token, or
      // that is authenticated as somebody else, must never be kept.
      socket.on('connected', (payload) {
        if (!_isLive(session, socket)) return;
        if (payload is! Map) return;
        if (payload['authenticated'] != true) {
          unawaited(_recoverAuth(session, socket));
          return;
        }
        final serverUser = payload['user_id']?.toString();
        final expected = session.accountId;
        if (expected != null && serverUser != null && serverUser != expected) {
          _emitError('Socket account mismatch');
          disconnect();
          return;
        }
        _authRecoveries = 0;
        _scheduleTokenRefresh(session, socket, payload['expires_at']);
      });

      socket.on('auth_expired', (_) {
        if (!_isLive(session, socket)) return;
        unawaited(_recoverAuth(session, socket));
      });

      socket.on('disconnect', (_) {
        if (!_isLive(session, socket)) return;
        _isConnected = false;
        _isConnecting = false;
        _emitConnected(false);
      });

      socket.on('connect_error', (err) {
        if (!_isLive(session, socket)) return;
        _isConnected = false;
        _isConnecting = false;
        _emitConnected(false);
        if (_isAuthFailure(err) ||
            _isExpiredOrExpiring(ApiService.accessToken, Duration.zero)) {
          // The (re)connect was refused because of OUR token: refresh and
          // rebuild instead of letting the transport retry with the same,
          // stale `Authorization` header.
          unawaited(_recoverAuth(session, socket));
          return;
        }
        _emitError('Socket connect error: $err');
      });

      socket.on('error', (err) {
        if (!_isLive(session, socket)) return;
        final msg = (err is Map && err['message'] != null) ? err['message'].toString() : err.toString();
        if (_isAuthFailure(msg)) {
          unawaited(_recoverAuth(session, socket));
          return;
        }
        _emitError(msg);
      });

      socket.on('new_message', (payload) {
        if (!_isLive(session, socket)) return;
        if (payload is Map) {
          final m = Map<String, dynamic>.from(payload);
          _messagesController.add(m);
          onMessage?.call(m);
        }
      });

      socket.on('message_updated', (payload) {
        if (!_isLive(session, socket)) return;
        if (payload is Map) {
          _messageUpdatesController.add(Map<String, dynamic>.from(payload));
        }
      });

      socket.on('message_deleted', (payload) {
        if (!_isLive(session, socket)) return;
        if (payload is Map) {
          _messageDeletesController.add(Map<String, dynamic>.from(payload));
        }
      });

      socket.on('messages_read', (payload) {
        if (!_isLive(session, socket)) return;
        if (payload is Map) {
          _messageReadsController.add(Map<String, dynamic>.from(payload));
        }
      });

      socket.on('new_notification', (payload) {
        if (!_isLive(session, socket)) return;
        if (payload is Map) {
          final n = Map<String, dynamic>.from(payload);
          _notificationsController.add(n);
          onNotification?.call(n);
        }
      });

      socket.on('typing', (payload) {
        if (!_isLive(session, socket)) return;
        if (payload is Map) {
          final t = Map<String, dynamic>.from(payload);
          _typingController.add(t);
        }
      });

      socket.on('joined_chat', (payload) {
        if (!_isLive(session, socket)) return;
        try {
          if (payload is Map) {
            final map = Map<String, dynamic>.from(payload);
            // Server may soft-deny first-time buyers until they send a message.
            if (map['ok'] == false) {
              return;
            }
            if (map['car_id'] != null) {
              _currentRoom = map['car_id'].toString();
            }
            final room = (map['room'] ?? '').toString();
            if (room.isNotEmpty) _serverRoom = room;
          }
        } catch (e, st) { logNonFatal(e, st); }
      });

      socket.connect();
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      _cleanupSocket();
      _emitConnected(false);
      _emitError('Connection failed');
    }
  }

  /// Schedules the refresh of the token this socket authenticated with, a
  /// little before it expires.
  static void _scheduleTokenRefresh(
    AuthSessionSnapshot session,
    WsSocket socket,
    Object? serverExpiresAt,
  ) {
    _refreshTimer?.cancel();
    DateTime? exp;
    if (serverExpiresAt is num) {
      exp = DateTime.fromMillisecondsSinceEpoch(
        serverExpiresAt.toInt() * 1000,
        isUtc: true,
      );
    }
    exp ??= jwtExpiry(ApiService.accessToken);
    if (exp == null) return;
    var delay = exp.difference(_clock().toUtc()) - _refreshLeadTime;
    if (delay < _minRefreshDelay) delay = _minRefreshDelay;
    _refreshTimer = Timer(delay, () {
      if (!_isLive(session, socket)) return;
      unawaited(_recoverAuth(session, socket));
    });
  }

  /// Refreshes the access token for [session] and rebuilds the socket with it.
  /// Abandons everything if the session ended or the account changed meanwhile.
  static Future<void> _recoverAuth(
    AuthSessionSnapshot session,
    WsSocket socket,
  ) async {
    if (!_isLive(session, socket)) return;
    if (_recoveringAuth) return;
    if (_authRecoveries >= _maxAuthRecoveries) {
      _stopSocketKeepingState();
      _emitError('Authentication failed');
      return;
    }
    _recoveringAuth = true;
    _authRecoveries++;
    _refreshTimer?.cancel();
    try {
      final ok = await ApiService.refreshAccessTokenForSession(session);
      // A logout / account switch while the refresh was in flight has already
      // torn this socket down (AccountScope); never act for a later session.
      if (!_isLive(session, socket) || !_sameAccount(session)) return;
      if (!ok) {
        _stopSocketKeepingState();
        _emitError('Session expired');
        return;
      }
      // [_teardownSocket] keeps the conversation and the queued emits (only
      // [disconnect] clears them), so every queued event is flushed exactly
      // once by the rebuilt socket -- never re-added here.
      _teardownSocket();
      await connect();
    } finally {
      _recoveringAuth = false;
    }
  }

  /// Closes the transport and forgets the socket but keeps the conversation
  /// and queued emits, so a later [connect] resumes where we were.
  static void _teardownSocket() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _connectGeneration++;
    try {
      _socket?.disconnect();
    } catch (e, st) { logNonFatal(e, st); }
    _cleanupSocket();
    _socketSession = null;
    _isConnected = false;
    _isConnecting = false;
    _emitConnected(false);
  }

  static void _stopSocketKeepingState() => _teardownSocket();

  // Disconnect
  static void disconnect() {
    _teardownSocket();
    _currentRoom = null;
    _serverRoom = null;
    _conversation = null;
    _pendingEmits.clear();
    _authRecoveries = 0;
  }

  static void sendMessage(String event, Map<String, dynamic> data) {
    _hookAccountScope();
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
      _emitError('Send message error');
    }
  }

  /// Join the conversation about [carId] with [peerId].
  ///
  /// [peerId] (F-05/F-25) is the public id of the OTHER participant. A listing
  /// seller must pass it: one seller talks to several buyers about one listing
  /// and every (listing, buyer) pair is its own isolated conversation. For a
  /// buyer it may be omitted (the counterpart is the seller).
  static void joinChat(String carId, {String? peerId}) {
    final peer = peerId?.trim();
    final conversation = _ChatConversationRef(
      carId,
      (peer == null || peer.isEmpty) ? null : peer,
    );
    _conversation = conversation;
    sendMessage('join_chat', conversation.toPayload());
  }

  // Leave current chat room
  static void leaveChat() {
    final room = _serverRoom;
    _conversation = null;
    _serverRoom = null;
    _currentRoom = null;
    if (room != null && room.isNotEmpty) {
      // The server told us which (per-conversation) room we joined.
      sendMessage('leave_chat', {'room': room});
    }
  }

  /// Legacy Socket.IO text emit — **do not use for composer sends** (CHAT-2).
  /// Text goes through [OutgoingChatSendService] (REST + pending/retry).
  /// Kept for rare low-level callers / tests; no ACK or durable recovery.
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

  /// [peerId] names the conversation the typing indicator belongs to; the
  /// server delivers it ONLY to that counterpart (F-25).
  static void sendTypingStart(String carId, {String? peerId}) {
    sendMessage('typing_start', _typingPayload(carId, peerId));
  }

  static void sendTypingStop(String carId, {String? peerId}) {
    sendMessage('typing_stop', _typingPayload(carId, peerId));
  }

  static Map<String, dynamic> _typingPayload(String carId, String? peerId) {
    final peer = peerId?.trim();
    return <String, dynamic>{
      'car_id': carId,
      if (peer != null && peer.isNotEmpty) 'peer_id': peer,
    };
  }

  static bool get isConnected => _isConnected;

  // Get current room
  static String? get currentRoom => _currentRoom;
}

// Chat message model
