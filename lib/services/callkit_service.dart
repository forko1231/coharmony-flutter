import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../features/calling/call_screen.dart';
import '../models/call_models.dart';
import '../widgets/app_notification_banner.dart';
import 'app_navigation.dart';
import 'calling_service.dart';
import 'notification_service.dart';
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
  CallKitService(this._calling, this._notifications);

  final CallingService _calling;
  final NotificationService _notifications;
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

  /// Fetches the current iOS VoIP push token and registers it with the server
  /// (Azure Notification Hub) so call pushes can reach this device. Call after
  /// login. No-op on Android (which uses FCM instead).
  Future<void> registerVoipToken() async {
    if (!Platform.isIOS) return;
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token is String && token.isNotEmpty) {
        await _notifications.registerDeviceToken(deviceToken: token, platform: 'ios');
      }
    } catch (_) {/* best-effort */}
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

    // iOS VoIP token refresh → (re)register with the server.
    if (event.event == Event.actionDidUpdateDevicePushTokenVoip) {
      await _onTokenEvent(event);
      return;
    }

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

  /// Handles the iOS VoIP token push event separately (no call id/extra here).
  Future<void> _onTokenEvent(CallEvent event) async {
    final token = (event.body as Map?)?['deviceTokenVoIP']?.toString();
    if (token != null && token.isNotEmpty) {
      await _notifications.registerDeviceToken(deviceToken: token, platform: 'ios');
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

    // Mic (and camera for video) are required to join. Check up front: if the
    // recipient hasn't granted them, an accepted CallKit call would otherwise
    // become a ghost — we never join, the caller keeps ringing, and the native
    // call UI lingers as "connected". Abort cleanly instead.
    final micOk = await _ensureCallPermission(Permission.microphone, 'Microphone');
    final camOk = !pending.hasVideo || await _ensureCallPermission(Permission.camera, 'Camera');
    if (!micOk || !camOk) {
      await _abortAccept(callId, pending);
      return;
    }

    final ok = await _calling.acceptCall(
      IncomingCallEvent(
        roomName: pending.roomName,
        callerEmail: pending.callerEmail,
        hasVideo: pending.hasVideo,
      ),
      livekitUrl: AppNavigation.livekitUrl,
    );
    if (!ok) {
      // Couldn't join (server/LiveKit) — don't leave a ghost call either.
      await _abortAccept(callId, pending);
      return;
    }

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

  /// Requests a call permission, surfacing an in-app banner (which works even
  /// when accepting from the lock screen, with no Scaffold) on denial.
  Future<bool> _ensureCallPermission(Permission permission, String label) async {
    final status = await permission.request();
    if (status.isGranted || status.isLimited) return true;
    AppNotificationBanner.show(
      title: '$label access needed',
      body: 'Turn on $label for CoHarmony in Settings to answer calls.',
      type: NotificationType.incomingCall,
      onTapped: openAppSettings,
    );
    return false;
  }

  /// Tears down a call that couldn't be answered: clears the native CallKit UI
  /// for this id and rejects so the caller stops ringing.
  Future<void> _abortAccept(String callId, _PendingCall pending) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (_) {/* best-effort */}
    try {
      await _calling.rejectCall(pending.roomName);
    } catch (_) {/* best-effort */}
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
