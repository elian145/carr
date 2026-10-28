import 'package:car_listing_app/services/websocket_service.dart';

/// In-memory Socket.IO client for tests (see `WebSocketService.debugSocketFactory`).
class FakeWsSocket implements WsSocket {
  FakeWsSocket(this.options);
  final Map<String, dynamic> options;
  final Map<String, void Function(dynamic)> handlers = {};
  final List<MapEntry<String, dynamic>> emitted = [];
  bool connectCalled = false;
  bool disconnected = false;
  bool disposed = false;

  String get bearer =>
      (options['extraHeaders'] as Map)['authorization']?.toString() ??
      (options['extraHeaders'] as Map)['Authorization'].toString();

  String get token => bearer.substring('Bearer '.length);

  @override
  void on(String event, void Function(dynamic data) handler) =>
      handlers[event] = handler;

  @override
  void emit(String event, dynamic data) => emitted.add(MapEntry(event, data));

  @override
  void connect() => connectCalled = true;

  @override
  void disconnect() => disconnected = true;

  @override
  void dispose() => disposed = true;

  void fire(String event, [dynamic data]) => handlers[event]?.call(data);

  List<Map<String, dynamic>> emits(String event) => [
        for (final e in emitted)
          if (e.key == event) Map<String, dynamic>.from(e.value as Map),
      ];
}
