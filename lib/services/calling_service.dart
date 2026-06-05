import 'dart:async';

import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_models.dart';
import 'api_client.dart';
import 'websocket_service.dart';

class CallingService {
  CallingService({required ApiClient api, required WebSocketService webSocket})
      // public named params map to private fields, so a formal can't apply
      // ignore: prefer_initializing_formals
      : _api = api,
        _ws = webSocket {
    _ws.onCallState.listen(_onCallState);
  }

  final ApiClient _api;
  final WebSocketService _ws;

  Room? _room;
  String? _activeRoomName;

  /// The last LiveKit connection error (for surfacing why a call wouldn't connect).
  String? lastConnectError;

  final StreamController<CallStateEvent> _callStateChanged =
      StreamController<CallStateEvent>.broadcast();

  /// Fires for call state changes: accepted, rejected, ended.
  Stream<CallStateEvent> get onCallStateChanged => _callStateChanged.stream;

  /// Incoming call notifications come directly from the WebSocketService.
  Stream<IncomingCallEvent> get onIncomingCall => _ws.onCallIncoming;

  Room? get activeRoom => _room;
  String? get activeRoomName => _activeRoomName;
  bool get isInCall => _room != null;

  /// Requests mic (and camera if video) permissions, creates the call, returns false on failure.
  Future<bool> initiateCall(
    String recipientEmail, {
    bool video = false,
    required String livekitUrl,
  }) async {
    if (isInCall) return false; // one call at a time
    if (!await _requestPermissions(video: video)) return false;

    final json = await _api.postJson('/api/calls/initiate', {
      'recipientEmail': recipientEmail,
      'hasVideo': video,
    });
    if (json is! Map) return false;

    final roomName = json['roomName'] as String?;
    final token = json['token'] as String?;
    if (roomName == null || roomName.isEmpty || token == null || token.isEmpty) {
      return false;
    }
    return _connectToRoom(livekitUrl, roomName, token, video: video);
  }

  /// Called when the user taps "Accept" on the incoming call overlay.
  Future<bool> acceptCall(
    IncomingCallEvent event, {
    required String livekitUrl,
  }) async {
    // Best-effort permission request only. Permissions are primed after onboarding;
    // do NOT gate the join on a fresh request here. At CallKit-accept time (the app
    // foregrounding from the lock screen) request() can spuriously report denied,
    // which previously aborted the answer and rejected the caller. Join regardless;
    // a missing mic just means no audio capture until the user enables it.
    try {
      await _requestPermissions(video: event.hasVideo);
    } catch (_) {/* best-effort */}

    final json = await _api.postJson('/api/calls/join', {'roomName': event.roomName});
    if (json is! Map) return false;

    final token = json['token'] as String?;
    if (token == null || token.isEmpty) return false;
    return _connectToRoom(livekitUrl, event.roomName, token, video: event.hasVideo);
  }

  /// Rejects an incoming call without answering.
  Future<void> rejectCall(String roomName) async {
    await _api.postJson('/api/calls/reject', {'roomName': roomName});
  }

  /// Ends the active call (hang up). Idempotent: safe to call from multiple
  /// termination paths — the room name is captured and cleared atomically so a
  /// second call is a no-op rather than a duplicate /end.
  Future<void> endCall() async {
    final roomName = _activeRoomName;
    await _disposeRoom();
    if (roomName == null) return;
    try {
      await _api.postJson('/api/calls/end', {'roomName': roomName});
    } catch (_) {/* best-effort: local teardown already done */}
  }

  Future<List<CallSession>> getCallHistory(String contactEmail) async {
    final json = await _api.getJson('/api/calls/history');
    if (json == null || json is! List) return [];
    final all = json
        .map((e) => CallSession.fromJson(e as Map<String, dynamic>))
        .toList();
    return all
        .where((s) => s.initiatorEmail == contactEmail || s.recipientEmail == contactEmail)
        .toList();
  }

  void toggleMicrophone() {
    final local = _room?.localParticipant;
    if (local == null) return;
    local.setMicrophoneEnabled(!local.isMicrophoneEnabled());
  }

  void toggleCamera() {
    final local = _room?.localParticipant;
    if (local == null) return;
    local.setCameraEnabled(!local.isCameraEnabled());
  }

  void _onCallState(CallStateEvent event) {
    _callStateChanged.add(event);
  }

  /// Connects to the LiveKit room. Returns true on success; on any failure it
  /// tears down the partial room and returns false — it never throws to callers,
  /// so initiate/accept can report failure deterministically (and clean up the
  /// native call UI) instead of leaking an exception.
  Future<bool> _connectToRoom(
    String livekitUrl,
    String roomName,
    String token, {
    required bool video,
  }) async {
    await _disposeRoom(); // one call at a time — never overwrite a live room
    final room = Room();
    try {
      await room.connect(livekitUrl, token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (video) {
        await room.localParticipant?.setCameraEnabled(true);
      }
    } catch (e) {
      // Surface WHY (bad wss URL / rejected token / network) instead of failing
      // silently — this is the difference between "couldn't start" and a real cause.
      lastConnectError = '$e';
      try {
        await room.disconnect();
      } catch (_) {/* ignore */}
      room.dispose();
      return false;
    }
    lastConnectError = null;
    _room = room;
    _activeRoomName = roomName;
    return true;
  }

  /// Disconnects + disposes the active room and clears state. The name/room are
  /// cleared before the async disconnect so concurrent callers see "no call".
  Future<void> _disposeRoom() async {
    final room = _room;
    _room = null;
    _activeRoomName = null;
    if (room == null) return;
    try {
      await room.disconnect();
    } catch (_) {/* ignore */}
    room.dispose();
  }

  Future<bool> _requestPermissions({required bool video}) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;
    if (video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return false;
    }
    return true;
  }

  void dispose() {
    _room?.disconnect();
    _room?.dispose();
    _callStateChanged.close();
  }
}
