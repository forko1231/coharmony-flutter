import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'notification_service.dart';

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

  Future<void> init() async {
    if (!Platform.isAndroid || _started) return;
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

  void _onForegroundMessage(RemoteMessage message) {
    final data = _stringData(message.data);
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
