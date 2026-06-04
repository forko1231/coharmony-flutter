import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';

import '../features/calling/call_screen.dart';
import '../models/call_models.dart';
import 'app_navigation.dart';
import 'calling_service.dart';
import 'preferences.dart';

/// Drives the NATIVE incoming-call experience (CallKit on iOS, full-screen
/// incoming notification on Android), the way Snapchat/WhatsApp present calls.
///
/// Incoming calls arrive two ways:
///   • Foreground — a `call_incoming` WebSocket event → [showIncoming].
///   • Background / killed — a high-priority call push wakes the app; the FCM
///     handler (Android) or PushKit→CallKit (iOS) calls [showIncomingFromData].
///
/// CallKit button taps come back through [FlutterCallkitIncoming.onEvent]; we
/// translate accept/decline/end into [CallingService] calls and navigation.
class CallKitService {
  CallKitService(this._calling);

  final CallingService _calling;
  final _uuid = const Uuid();

  // Map the CallKit call UUID ↔ our LiveKit room name so events can be correlated.
  final Map<String, _PendingCall> _byCallId = {};
  final Map<String, String> _callIdByRoom = {};

  bool _started = false;

  /// Begins listening for CallKit button events. Call once at app startup.
  void start() {
    if (_started) return;
    _started = true;
    FlutterCallkitIncoming.onEvent.listen(_onEvent);
  }

  /// Shows the native incoming-call UI for a foreground WebSocket ring.
  Future<void> showIncoming(IncomingCallEvent event) {
    return showIncomingFromData(
      roomName: event.roomName,
      callerEmail: event.callerEmail,
      callerName: event.callerEmail,
      hasVideo: event.hasVideo,
    );
  }

  /// Shows the native incoming-call UI from raw push data (background/killed).
  Future<void> showIncomingFromData({
    required String roomName,
    required String callerEmail,
    required String callerName,
    required bool hasVideo,
  }) async {
    // Respect the user's calling preference (optional feature).
    if (!Preferences.getBool('calling_enabled', true)) return;
    // Reuse an existing CallKit id if this room is already ringing (dedupe the
    // WebSocket ring and the push, which can both arrive).
    final callId = _callIdByRoom[roomName] ?? _uuid.v4();
    _byCallId[callId] = _PendingCall(roomName, callerEmail, callerName, hasVideo);
    _callIdByRoom[roomName] = callId;

    await showNativeIncomingCall(
      callId: callId,
      roomName: roomName,
      callerEmail: callerEmail,
      callerName: callerName,
      hasVideo: hasVideo,
    );
  }

  /// Dismisses any native UI for [roomName] (caller cancelled / remote ended).
  Future<void> dismiss(String roomName) async {
    final callId = _callIdByRoom.remove(roomName);
    if (callId == null) return;
    _byCallId.remove(callId);
    await FlutterCallkitIncoming.endCall(callId);
  }

  Future<void> dismissAll() async {
    _byCallId.clear();
    _callIdByRoom.clear();
    await FlutterCallkitIncoming.endAllCalls();
  }

  Future<void> _onEvent(CallEvent? event) async {
    if (event == null) return;
    final body = event.body as Map?;
    final callId = body?['id']?.toString();
    // Prefer the in-memory record; fall back to CallKit's `extra` so a call
    // accepted from a cold start (different isolate) still resolves.
    final pending = (callId != null ? _byCallId[callId] : null) ??
        _fromExtra(body?['extra']);
    if (callId == null || pending == null) return;

    switch (event.event) {
      case Event.actionCallAccept:
        await _accept(callId, pending);
        break;
      case Event.actionCallDecline:
        await _decline(callId, pending);
        break;
      case Event.actionCallEnded:
      case Event.actionCallTimeout:
        _byCallId.remove(callId);
        _callIdByRoom.remove(pending.roomName);
        break;
      default:
        break;
    }
  }

  _PendingCall? _fromExtra(dynamic extra) {
    if (extra is! Map) return null;
    final roomName = extra['roomName']?.toString();
    if (roomName == null || roomName.isEmpty) return null;
    final hasVideo = extra['hasVideo'] == true || extra['hasVideo'] == 'true';
    return _PendingCall(
      roomName,
      extra['callerEmail']?.toString() ?? '',
      extra['callerName']?.toString() ?? '',
      hasVideo,
    );
  }

  Future<void> _accept(String callId, _PendingCall pending) async {
    _byCallId.remove(callId);
    _callIdByRoom.remove(pending.roomName);

    final ok = await _calling.acceptCall(
      IncomingCallEvent(
        roomName: pending.roomName,
        callerEmail: pending.callerEmail,
        hasVideo: pending.hasVideo,
      ),
      livekitUrl: AppNavigation.livekitUrl,
    );
    if (!ok) return;

    final room = _calling.activeRoom;
    final navigator = AppNavigation.navigatorKey.currentState;
    if (room == null || navigator == null) return;

    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          room: room,
          contactEmail: pending.callerEmail,
          hasVideo: pending.hasVideo,
        ),
      ),
    );
  }

  Future<void> _decline(String callId, _PendingCall pending) async {
    _byCallId.remove(callId);
    _callIdByRoom.remove(pending.roomName);
    await _calling.rejectCall(pending.roomName);
  }
}

class _PendingCall {
  _PendingCall(this.roomName, this.callerEmail, this.callerName, this.hasVideo);
  final String roomName;
  final String callerEmail;
  final String callerName;
  final bool hasVideo;
}

/// Builds and shows the native incoming-call UI. Top-level so it can be invoked
/// from the FCM background isolate (which has no [ServiceLocator]) as well as
/// from [CallKitService].
Future<void> showNativeIncomingCall({
  required String callId,
  required String roomName,
  required String callerEmail,
  required String callerName,
  required bool hasVideo,
}) async {
  final params = CallKitParams(
    id: callId,
    nameCaller: callerName.isEmpty ? callerEmail : callerName,
    appName: 'CoHarmony',
    handle: callerEmail,
    type: hasVideo ? 1 : 0, // 1 = video, 0 = audio
    duration: 45000, // auto-dismiss the ring after 45s
    textAccept: 'Accept',
    textDecline: 'Decline',
    // Carried through CallKit so the call can be reconstructed even after a
    // cold start (the in-memory map lives in a different isolate then).
    extra: <String, dynamic>{
      'roomName': roomName,
      'callerEmail': callerEmail,
      'callerName': callerName,
      'hasVideo': hasVideo,
    },
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: 'Missed call',
    ),
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#0A0F1C',
      actionColor: '#2563EB',
      isShowFullLockedScreen: true,
    ),
    ios: const IOSParams(
      iconName: 'CallKitLogo',
      handleType: 'generic',
      supportsVideo: true,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      audioSessionMode: 'default',
      ringtonePath: 'system_ringtone_default',
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}
