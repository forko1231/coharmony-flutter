import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'callkit_service.dart';
import 'notification_service.dart';
import 'service_locator.dart';

/// True when a push-data `type` denotes an incoming call.
bool _isCallType(String? type) => (type ?? '').toLowerCase() == 'incomingcall';

/// FCM background-isolate handler for call pushes. Must be a top-level,
/// vm:entry-point function. Shows the native full-screen incoming-call UI even
/// when the app is killed (Android data-only high-priority message).
@pragma('vm:entry-point')
Future<void> callFcmBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  if (!_isCallType(data['type']?.toString())) return;
  await Firebase.initializeApp();
  await showNativeIncomingCall(
    callId: const Uuid().v4(),
    roomName: data['roomName']?.toString() ?? '',
    callerEmail: data['callerEmail']?.toString() ?? '',
    callerName: data['callerName']?.toString() ?? '',
    hasVideo: data['hasVideo']?.toString() == 'true',
  );
}

/// Firebase Cloud Messaging — ANDROID ONLY (matches the MAUI app, which never
/// configured iOS push). Every Firebase call is guarded by [Platform.isAndroid], so on
/// iOS this is a no-op and the linked pods stay inert (no `initializeApp`, no crash).
///
/// On Android: init Firebase (config comes from the native google-services.json via the
/// Gradle plugin — no `firebase_options.dart` needed), request the notification
/// permission, then hand the FCM token to [NotificationService.registerDeviceToken]
/// (which needs the user to be signed in, so this is called from the dashboards).
class PushService {
  PushService(this._notifications);
  final NotificationService _notifications;

  bool _started = false;

  // Native bridge for iOS standard APNs (alert) notifications. iOS has no Firebase here,
  // so we register for remote notifications natively and the AppDelegate hands the raw
  // APNs token back over this channel. (Calls use a separate VoIP/PushKit token.)
  static const MethodChannel _iosPush = MethodChannel('coharmony/push');

  Future<void> init() async {
    if (_started) return;
    if (Platform.isIOS) {
      await _initIos();
      return;
    }
    if (!Platform.isAndroid) return;
    _started = true;
    try {
      await Firebase.initializeApp();
      await _notifications.initLocalNotifications();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _notifications.registerDeviceToken(deviceToken: token, platform: 'android');
      }
      messaging.onTokenRefresh.listen((t) {
        _notifications.registerDeviceToken(deviceToken: t, platform: 'android');
      });

      // Background/killed call pushes → native full-screen incoming UI.
      FirebaseMessaging.onBackgroundMessage(callFcmBackgroundHandler);

      // Foreground messages → in-app banner (FCM doesn't show a system
      // notification while the app is open).
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      // Tapping a notification that opened/foregrounded the app → route.
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      // Cold start from a notification tap.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _onMessageOpenedApp(initial);
    } catch (_) {
      // Push is best-effort; failure here must never block the app.
      _started = false;
    }
  }

  // iOS: standard APNs alert notifications (schedule changed, reminders, messages, …).
  // Calls stay on the existing VoIP/PushKit path. The AppDelegate asks the OS for the
  // token and reports it back as 'onApnsToken'; a notification tap arrives as 'onApnsTap'.
  Future<void> _initIos() async {
    _started = true;
    try {
      await _notifications.initLocalNotifications();
      _iosPush.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onApnsToken':
            final token = call.arguments as String?;
            if (token != null && token.isNotEmpty) {
              await _notifications.registerApnsAlertToken(token);
            }
          case 'onApnsTap':
            final data = _stringData(_asMap(call.arguments));
            final type = _notifications.getNotificationType(data);
            _notifications.handleNotificationTapped(type, data);
        }
        return null;
      });
      await _iosPush.invokeMethod('registerForPush');
    } catch (_) {
      _started = false;
    }
  }

  Map<String, dynamic> _asMap(Object? args) {
    if (args is Map) return args.map((k, v) => MapEntry(k.toString(), v));
    return const {};
  }

  void _onForegroundMessage(RemoteMessage message) {
    final data = _stringData(message.data);
    // Incoming call → native CallKit/full-screen UI (not an in-app banner).
    if (_isCallType(data['type'])) {
      ServiceLocator.callKit.showIncomingFromData(
        roomName: data['roomName'] ?? '',
        callerEmail: data['callerEmail'] ?? '',
        callerName: data['callerName'] ?? '',
        hasVideo: data['hasVideo'] == 'true',
      );
      return;
    }
    final type = _notifications.getNotificationType(data);
    final title = message.notification?.title ?? data['title'];
    final body = message.notification?.body ?? data['body'];
    _notifications.handleNotificationReceived(type, title, body, data);
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    final data = _stringData(message.data);
    final type = _notifications.getNotificationType(data);
    _notifications.handleNotificationTapped(type, data);
  }

  Map<String, String> _stringData(Map<String, dynamic> data) =>
      data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
}
