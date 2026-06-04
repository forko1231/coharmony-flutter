import 'dart:async';

import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_models.dart';
import 'api_client.dart';
import 'websocket_service.dart';

class CallingService {
  CallingService({required ApiClient api, required WebSocketService webSocket})
      : _api = api,
        _ws = webSocket {
    _ws.onCallState.listen(_onCallState);
  }

  final ApiClient _api;
  final WebSocketService _ws;

  Room? _room;
  String? _activeRoomName;

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
    if (!await _requestPermissions(video: video)) return false;

    final json = await _api.postJson('/api/calls/initiate', {
      'recipientEmail': recipientEmail,
      'hasVideo': video,
    });
    if (json == null) return false;

    final roomName = json['roomName'] as String;
    final token = json['token'] as String;
    await _connectToRoom(livekitUrl, roomName, token, video: video);
    return true;
  }

  /// Called when the user taps "Accept" on the incoming call overlay.
  Future<bool> acceptCall(
    IncomingCallEvent event, {
    required String livekitUrl,
  }) async {
    if (!await _requestPermissions(video: event.hasVideo)) return false;

    final json = await _api.postJson('/api/calls/join', {'roomName': event.roomName});
    if (json == null) return false;

    final token = json['token'] as String;
    await _connectToRoom(livekitUrl, event.roomName, token, video: event.hasVideo);
    return true;
  }

  /// Rejects an incoming call without answering.
  Future<void> rejectCall(String roomName) async {
    await _api.postJson('/api/calls/reject', {'roomName': roomName});
  }

  /// Ends the active call (hang up).
  Future<void> endCall() async {
    final roomName = _activeRoomName;
    if (roomName == null) return;

    await _room?.disconnect();
    _room?.dispose();
    _room = null;
    _activeRoomName = null;

    await _api.postJson('/api/calls/end', {'roomName': roomName});
  }

  Future<List<CallSession>> getCallHistory(String contactEmail) async {
    final json = await _api.getJson('/api/calls/history');
    if (json == null || json is! List) return [];
    final all = (json as List<dynamic>)
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

  Future<void> _connectToRoom(
    String livekitUrl,
    String roomName,
    String token, {
    required bool video,
  }) async {
    _room = Room();
    await _room!.connect(livekitUrl, token);
    _activeRoomName = roomName;

    await _room!.localParticipant?.setMicrophoneEnabled(true);
    if (video) {
      await _room!.localParticipant?.setCameraEnabled(true);
    }
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
