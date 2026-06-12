import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_models.dart';
import 'api_client.dart';
import 'websocket_service.dart';

/// Debug-only call logging — emails/room names are personal data and
/// `debugPrint` is NOT stripped in release builds.
void _callLog(String msg) {
  if (kDebugMode) debugPrint(msg);
}

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
  Future<Room?> initiateCall(
    String recipientEmail, {
    bool video = false,
    required String livekitUrl,
  }) async {
    // No "already in a call" guard here: a stale room from a previously-broken call
    // would otherwise block every future call. _connectToRoom disposes any prior
    // room before connecting, so this is safe.
    _callLog('[CALL] initiate → $recipientEmail video=$video');
    if (!await _requestPermissions(video: video)) {
      _callLog('[CALL] initiate ABORT: permissions denied');
      return null;
    }

    final json = await _api.postJson('/api/calls/initiate', {
      'recipientEmail': recipientEmail,
      'hasVideo': video,
    });
    if (json is! Map) {
      _callLog('[CALL] initiate ABORT: bad /initiate response ($json)');
      return null;
    }

    final roomName = json['roomName'] as String?;
    final token = json['token'] as String?;
    if (roomName == null || roomName.isEmpty || token == null || token.isEmpty) {
      _callLog('[CALL] initiate ABORT: missing roomName/token');
      return null;
    }
    _callLog('[CALL] initiate room=$roomName tokenLen=${token.length} → connecting');
    return _connectToRoom(livekitUrl, roomName, token, video: video);
  }

  /// Called when the user taps "Accept" on the incoming call overlay.
  Future<Room?> acceptCall(
    IncomingCallEvent event, {
    required String livekitUrl,
  }) async {
    // Best-effort permission request only. Permissions are primed after onboarding;
    // do NOT gate the join on a fresh request here. At CallKit-accept time (the app
    // foregrounding from the lock screen) request() can spuriously report denied,
    // which previously aborted the answer and rejected the caller. Join regardless;
    // a missing mic just means no audio capture until the user enables it.
    _callLog('[CALL] accept room=${event.roomName} from=${event.callerEmail} video=${event.hasVideo}');
    try {
      await _requestPermissions(video: event.hasVideo);
    } catch (_) {/* best-effort */}

    final json = await _api.postJson('/api/calls/join', {'roomName': event.roomName});
    if (json is! Map) {
      _callLog('[CALL] accept ABORT: bad /join response ($json) — call may be over');
      return null;
    }

    final token = json['token'] as String?;
    if (token == null || token.isEmpty) {
      _callLog('[CALL] accept ABORT: no join token');
      return null;
    }
    _callLog('[CALL] accept room=${event.roomName} tokenLen=${token.length} → connecting');
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
    _callLog('[CALL] endCall room=$roomName  ${StackTrace.current.toString().split('\n').take(4).join(' | ')}');
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
    _callLog('[CALL] WS callState=${event.type} room=${event.roomName} (activeRoom=$_activeRoomName)');
    _callStateChanged.add(event);
  }

  /// Connects to the LiveKit room. Returns true on success; on any failure it
  /// tears down the partial room and returns false — it never throws to callers,
  /// so initiate/accept can report failure deterministically (and clean up the
  /// native call UI) instead of leaking an exception.
  Future<Room?> _connectToRoom(
    String livekitUrl,
    String roomName,
    String token, {
    required bool video,
  }) async {
    await _disposeRoom(); // one call at a time — never overwrite a live room
    final room = Room();
    try {
      _callLog('[CALL] room.connect url=$livekitUrl room=$roomName …');
      await room.connect(livekitUrl, token);
      _callLog('[CALL] room.connect OK room=$roomName sid=${room.localParticipant?.sid} '
          'identity=${room.localParticipant?.identity} remotes=${room.remoteParticipants.length}');
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (video) {
        await room.localParticipant?.setCameraEnabled(true);
      }
    } catch (e) {
      // Surface WHY (bad wss URL / rejected token / network) instead of failing
      // silently — this is the difference between "couldn't start" and a real cause.
      lastConnectError = '$e';
      _callLog('[CALL] room.connect FAILED room=$roomName: $e');
      try {
        await room.disconnect();
      } catch (_) {/* ignore */}
      room.dispose();
      return null;
    }
    lastConnectError = null;
    _room = room;
    _activeRoomName = roomName;
    return room;
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
