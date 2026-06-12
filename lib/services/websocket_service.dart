import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import '../models/call_models.dart';
import '../models/message_models.dart';
import 'api_client.dart';
import 'token_service.dart';

/// Debug-only logging — payloads can contain personal data (caller emails,
/// room names), so nothing is ever printed in release builds.
void _wsLog(String msg) {
  if (kDebugMode) debugPrint(msg);
}

/// Port of `Services/WebSocketService.cs`. Real-time transport for messaging.
///
/// Uses `IOWebSocketChannel` (supports the `Authorization: Bearer` header on
/// mobile, like the C# `ClientWebSocket.Options.SetRequestHeader`). The C#
/// `MessageReceived` event is exposed here as a broadcast [Stream] of
/// [WebSocketMessage].
///
/// Reconnect: unlimited attempts with exponential backoff + jitter (2s, 4s,
/// 8s … capped at 60s), reset on a successful connect. Only an INTENTIONAL
/// disconnect (logout/dispose) stops the loop. After the first failed attempt
/// each retry refreshes the auth token first — an expired-while-backgrounded
/// token would otherwise 401 every attempt and leave the socket dead forever.
/// A periodic ping (~30s) keeps NAT/proxy idle timeouts from silently killing
/// the connection; two unanswered pings force a reconnect.
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
  bool _intentionalDisconnect = false; // logout/dispose — stop reconnecting
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _missedPongs = 0;
  final Random _random = Random();
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const int _maxBackoffSeconds = 60;

  final StreamController<WebSocketMessage> _messages =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<IncomingCallEvent> _callIncoming =
      StreamController<IncomingCallEvent>.broadcast();
  final StreamController<CallStateEvent> _callState =
      StreamController<CallStateEvent>.broadcast();
  final StreamController<int> _liveSchedule =
      StreamController<int>.broadcast();

  /// Stream of inbound `new_message` / `messages_read` / `typing` messages.
  Stream<WebSocketMessage> get messages => _messages.stream;

  /// Fires when the partner changes the live custody schedule (emits the new
  /// version). The live editor refetches on this for live updates / lock visuals.
  Stream<int> get onLiveScheduleChanged => _liveSchedule.stream;

  /// Fires when the server pushes a `call_incoming` notification.
  Stream<IncomingCallEvent> get onCallIncoming => _callIncoming.stream;

  /// Fires for `call_accepted`, `call_rejected`, and `call_ended` events.
  Stream<CallStateEvent> get onCallState => _callState.stream;

  bool get isConnected => _isConnected && _channel != null;

  /// Live connection state for pages that want to show online/offline UI.
  /// Kept accurate across connect / drop / reconnect; disposed with the service.
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);

  void _setConnected(bool value) {
    _isConnected = value;
    if (isConnectedNotifier.value != value) isConnectedNotifier.value = value;
  }

  /// Connect using the current auth token from the API client. A failure here
  /// (server briefly down at app start) kicks off the backoff loop too.
  Future<bool> connect() async {
    _intentionalDisconnect = false;
    final token = _api.getAuthToken();
    if (token.isEmpty) return false;
    final connected = await connectWith(token);
    if (!connected) _scheduleReconnect();
    return connected;
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
      if (_intentionalDisconnect) {
        // Logout/dispose raced the connect — drop the socket, stay down.
        try {
          await _channel?.sink.close();
        } catch (_) {/* ignore */}
        _channel = null;
        return false;
      }
      _reconnectAttempts = 0;

      _sub = _channel!.stream.listen(
        _onData,
        onError: (_) => _handleDrop(),
        onDone: _handleDrop,
        cancelOnError: true,
      );
      _setConnected(true);
      _startHeartbeat();
      await _sendPing();
      return true;
    } catch (_) {
      _channel = null; // never leave a half-open channel behind
      _setConnected(false);
      return false;
    }
  }

  Future<void> disconnect({bool reconnect = false}) async {
    _intentionalDisconnect = !reconnect;
    _stopHeartbeat();
    if (!reconnect) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
    if (!_isConnected && _channel == null) return;
    _setConnected(false);

    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {/* ignore */}
    _channel = null;

    if (reconnect) _scheduleReconnect();
  }

  /// Called when the socket errors or closes unexpectedly — reconnect.
  void _handleDrop() {
    if (!_isConnected) return;
    disconnect(reconnect: true);
  }

  /// Schedules the next reconnect attempt with exponential backoff + jitter:
  /// 2s, 4s, 8s … capped at [_maxBackoffSeconds], plus 0–1s of random jitter.
  /// Unlimited attempts — only [_intentionalDisconnect] stops the loop.
  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final base = min(_maxBackoffSeconds, 2 << min(_reconnectAttempts - 1, 5));
    final delay = Duration(seconds: base, milliseconds: _random.nextInt(1000));
    _wsLog('[WS] reconnect attempt $_reconnectAttempts in ${delay.inMilliseconds}ms');
    _reconnectTimer = Timer(delay, _tryReconnect);
  }

  Future<void> _tryReconnect() async {
    if (_intentionalDisconnect || _isConnected) return;

    var token = _api.getAuthToken();
    // The first attempt reuses the in-memory token (cheap, usually fine). If
    // that failed — or there is no token — the token may have expired while
    // backgrounded, so refresh before retrying instead of 401ing forever.
    if (_reconnectAttempts > 1 || token.isEmpty) {
      final refresh = await _api.tokenService.refreshToken(_api);
      switch (refresh.outcome) {
        case RefreshOutcome.refreshed:
          token = refresh.token!;
          _api.setAuthToken(token);
          break;
        case RefreshOutcome.rejected:
        case RefreshOutcome.noSession:
          // Session is definitively dead — stop reconnecting. The global
          // onAuthFailure path (next 401'd HTTP call) handles navigation.
          _wsLog('[WS] reconnect stopped: session dead (${refresh.outcome.name})');
          return;
        case RefreshOutcome.transient:
          break; // offline/5xx — keep backing off with the existing token
      }
    }
    if (token.isEmpty) {
      _scheduleReconnect();
      return;
    }
    final connected = await connectWith(token);
    if (!connected && !_intentionalDisconnect) _scheduleReconnect();
  }

  /// Periodic ping: keeps NAT/proxy idle timeouts from killing the connection
  /// and surfaces dead sockets. The server echoes a `pong` for every ping
  /// (`WebSocketHandler.cs`); two unanswered pings mean the connection is dead
  /// even though the socket never reported a close — force a reconnect.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _missedPongs = 0;
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (!_isConnected) return;
      if (_missedPongs >= 2) {
        _wsLog('[WS] $_missedPongs missed pongs → force reconnect');
        _handleDrop();
        return;
      }
      _missedPongs++;
      _sendPing();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _missedPongs = 0;
  }

  void _onData(dynamic data) {
    if (data is! String) return; // only text frames supported
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'] as String? ?? '';
      final rawData = decoded['data'] as Map<String, dynamic>? ?? {};

      switch (type) {
        case 'pong':
          _missedPongs = 0; // heartbeat ack — connection is alive
          break;
        case 'new_message':
        case 'messages_read':
        case 'typing':
          _messages.add(WebSocketMessage.fromJson(decoded));
          break;
        case 'call_incoming':
          _wsLog('[CALL] WS<- call_incoming $rawData');
          _callIncoming.add(IncomingCallEvent.fromJson(rawData));
          break;
        case 'call_accepted':
        case 'call_rejected':
        case 'call_ended':
          _wsLog('[CALL] WS<- $type $rawData');
          _callState.add(CallStateEvent.fromJson(type, rawData));
          break;
        case 'live_schedule':
          // version is sent flat on the frame (SendNotificationToUserAsync serializes
          // the object directly), not nested under 'data'.
          _liveSchedule.add((decoded['version'] as num?)?.toInt() ?? 0);
          break;
        default:
          break;
      }
    } catch (_) {/* ignore malformed frame */}
  }

  Future<void> _sendPing() async {
    final sent =
        _send({'type': 'ping', 'timestamp': DateTime.now().toUtc().toIso8601String()});
    // A failed send means the socket is already broken even if no close/error
    // event fired — treat it as a drop so the reconnect loop takes over.
    if (!sent && _isConnected) _handleDrop();
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
    // disconnect()'s synchronous prefix cancels the heartbeat + reconnect
    // timers and clears the connected flag/notifier before anything below runs.
    disconnect(reconnect: false);
    _messages.close();
    _callIncoming.close();
    _callState.close();
    _liveSchedule.close();
    isConnectedNotifier.dispose();
  }
}
