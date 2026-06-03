import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';

import '../models/message_models.dart';
import 'api_client.dart';

/// Port of `Services/WebSocketService.cs`. Real-time transport for messaging.
///
/// Uses `IOWebSocketChannel` (supports the `Authorization: Bearer` header on
/// mobile, like the C# `ClientWebSocket.Options.SetRequestHeader`). The C#
/// `MessageReceived` event is exposed here as a broadcast [Stream] of
/// [WebSocketMessage]. Reconnect logic mirrors the C# (max 5 attempts, 5s delay,
/// fresh token from the API client).
class WebSocketService {
  WebSocketService(this._api) {
    final apiUri = Uri.parse(_api.baseUrl);
    final wsScheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    _serverUrl = '$wsScheme://${apiUri.authority}';
  }

  final ApiClient _api;
  late final String _serverUrl;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _isConnected = false;
  bool _reconnectOnDisconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  final StreamController<WebSocketMessage> _messages =
      StreamController<WebSocketMessage>.broadcast();

  /// Stream of inbound `new_message` / `messages_read` / `typing` messages.
  Stream<WebSocketMessage> get messages => _messages.stream;

  bool get isConnected => _isConnected && _channel != null;

  /// Connect using the current auth token from the API client.
  Future<bool> connect() async {
    final token = _api.getAuthToken();
    if (token.isEmpty) return false;
    return connectWith(token);
  }

  Future<bool> connectWith(String authToken) async {
    if (_isConnected) return true;
    try {
      final uri = Uri.parse('$_serverUrl/ws');
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $authToken'},
      );
      await _channel!.ready.timeout(const Duration(seconds: 10));
      _reconnectAttempts = 0;

      _sub = _channel!.stream.listen(
        _onData,
        onError: (_) => _handleDrop(),
        onDone: _handleDrop,
        cancelOnError: true,
      );
      _isConnected = true;
      await _sendPing();
      return true;
    } catch (_) {
      _isConnected = false;
      return false;
    }
  }

  Future<void> disconnect({bool reconnect = false}) async {
    _reconnectOnDisconnect = reconnect;
    if (!_isConnected && _channel == null) return;

    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {/* ignore */}
    _channel = null;
    _isConnected = false;

    if (reconnect && _reconnectOnDisconnect) {
      await _attemptReconnect();
    }
  }

  /// Called when the socket errors or closes unexpectedly — reconnect.
  void _handleDrop() {
    if (!_isConnected) return;
    disconnect(reconnect: true);
  }

  Future<void> _attemptReconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    _reconnectAttempts++;
    await Future<void>.delayed(_reconnectDelay);

    final freshToken = _api.getAuthToken();
    if (freshToken.isEmpty) return;

    final connected = await connectWith(freshToken);
    if (!connected) {
      await _attemptReconnect();
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return; // only text frames supported
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return;
      final msg = WebSocketMessage.fromJson(decoded);
      switch (msg.type) {
        case 'pong':
          break; // heartbeat ack
        case 'new_message':
        case 'messages_read':
        case 'typing':
          _messages.add(msg);
          break;
        default:
          break;
      }
    } catch (_) {/* ignore malformed frame */}
  }

  Future<void> _sendPing() async {
    _send({'type': 'ping', 'timestamp': DateTime.now().toUtc().toIso8601String()});
  }

  /// Send a typing indicator for relay to [receiverEmail].
  Future<void> sendTyping(String receiverEmail) async {
    if (!isConnected) return;
    _send({
      'type': 'typing',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'data': {'receiver': receiverEmail},
    });
  }

  /// Send an arbitrary message object over the socket (thread-safe enough for
  /// Dart's single-threaded event loop).
  Future<bool> sendMessage(Object message) async {
    if (!isConnected) return false;
    return _send(message);
  }

  bool _send(Object message) {
    final ch = _channel;
    if (ch == null) return false;
    try {
      ch.sink.add(jsonEncode(message));
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    disconnect(reconnect: false);
    _messages.close();
  }
}
