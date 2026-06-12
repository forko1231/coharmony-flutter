import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';

import '../features/calling/call_screen.dart';
import '../models/call_models.dart';
import 'app_navigation.dart';
import 'calling_service.dart';
import 'notification_service.dart';
import 'preferences.dart';

/// Debug-only call logging — emails/room names are personal data and
/// `debugPrint` is NOT stripped in release builds.
void _callLog(String msg) {
  if (kDebugMode) debugPrint(msg);
}

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

  // Rooms already accepted/declined/ended. The server rings BOTH over the
  // WebSocket and via push, so a second (late) ring for the same call can arrive
  // after it's been handled — showing a phantom incoming call that, when
  // dismissed, fires a decline → a spurious /reject that kills the live call.
  // Once a room is handled we suppress any further ring for it. Room names are
  // GUIDs (never reused), so this can never hide a legitimate new call.
  final Set<String> _handledRooms = {};
  final Set<String> _acceptedRooms = {}; // rooms we answered — never reject these
  final Map<String, Timer> _handledTimers = {};

  void _markHandled(String roomName) {
    _handledRooms.add(roomName);
    _handledTimers[roomName]?.cancel();
    _handledTimers[roomName] = Timer(const Duration(seconds: 90), () {
      _handledRooms.remove(roomName);
      _acceptedRooms.remove(roomName);
      _handledTimers.remove(roomName);
    });
  }

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
    // iOS: the incoming CallKit screen is reported NATIVELY from the VoIP push
    // (PushKit, see ios/Runner/AppDelegate.swift) for every call, in all app
    // states. Showing one here from the WebSocket ring too stacks a SECOND CallKit
    // UI — two accept/reject screens. So on iOS the push is the single source of
    // the incoming UI; the WebSocket is used only for accepted/ended/rejected.
    if (Platform.isIOS) {
      _callLog('[CALL] CallKit: skipping WS incoming UI on iOS (VoIP push shows it natively)');
      return Future.value();
    }
    return showIncomingFromData(
      roomName: event.roomName,
      callerEmail: event.callerEmail,
      callerName: (event.callerName?.trim().isNotEmpty ?? false)
          ? event.callerName!.trim()
          : event.callerEmail,
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
    // Suppress a late/duplicate ring for a call that's already been handled — this
    // is what was emitting a phantom decline → spurious /reject that killed calls.
    if (_handledRooms.contains(roomName)) {
      _callLog('[CALL] CallKit: suppressing duplicate/late ring for handled room $roomName');
      return;
    }
    // Busy: already in (or ringing/connecting) a call → auto-decline the new one.
    // Otherwise it would stack a second ring, and accepting it would tear down the
    // live call (a single CallingService holds one room at a time).
    if (_calling.isInCall) {
      _callLog('[CALL] CallKit: busy — auto-declining incoming room $roomName');
      _markHandled(roomName);
      await _calling.rejectCall(roomName);
      return;
    }
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
        _markHandled(pending.roomName);
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
    _callLog('[CALL] CallKit ACCEPT callId=$callId room=${pending.roomName}');
    _acceptedRooms.add(pending.roomName); // never let a leftover ring reject this call
    _markHandled(pending.roomName); // a late duplicate ring for this room is now suppressed
    _byCallId.remove(callId);
    _callIdByRoom.remove(pending.roomName);

    final navigator = AppNavigation.navigatorKey.currentState;
    if (navigator == null) return;

    // Start the join. Permissions are primed after onboarding; we deliberately do
    // NOT re-check/abort here, because an accept-time permission hiccup (common when
    // foregrounding from the lock screen) must never reject and cancel the caller's
    // call. A missing mic degrades to no audio, not a dropped call.
    final connecting = _calling.acceptCall(
      IncomingCallEvent(
        roomName: pending.roomName,
        callerEmail: pending.callerEmail,
        hasVideo: pending.hasVideo,
      ),
      livekitUrl: AppNavigation.livekitUrl,
    );

    // Open the call UI IMMEDIATELY (shows "Connecting…") and let it attach the room
    // when the join completes — the recipient shouldn't stare at the incoming
    // screen during the ~1s join. A failed join closes the screen from inside.
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          roomName: pending.roomName,
          connecting: connecting,
          contactEmail: pending.callerEmail,
          contactName: pending.callerName,
          hasVideo: pending.hasVideo,
        ),
      ),
    );
  }

  Future<void> _decline(String callId, _PendingCall pending) async {
    _byCallId.remove(callId);
    _callIdByRoom.remove(pending.roomName);
    // If this room was already accepted, this decline is a phantom (a leftover
    // duplicate ring being dismissed) — do NOT reject, or it kills the live call.
    if (_acceptedRooms.contains(pending.roomName)) {
      _callLog('[CALL] CallKit: skipping reject for already-accepted room ${pending.roomName}');
      return;
    }
    _markHandled(pending.roomName); // suppress any late duplicate ring for this room
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
