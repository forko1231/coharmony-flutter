import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../features/main/partner_page.dart';
import '../models/notification_models.dart';
import '../widgets/app_notification_banner.dart';
import 'api_client.dart';
import 'app_navigation.dart';
import 'secure_storage_service.dart';

/// Notification type — must match the backend NotificationTypes enum.
enum NotificationType {
  messageReceived,
  partnerInviteReceived,
  partnerInviteAccepted,
  partnerInviteDeclined,
  paymentComingUp,
  eventComingUp,
  scheduleReminder,
  courtMessage,
  custodyResponse,
  custodyUpdate,
  incomingCall,
  callEnded,
}

/// Port of `Services/NotificationService.cs`.
///
/// The PORTABLE core is here: server registration/update (`api/notifications/register`
/// + `/update`), notification-type parsing, default titles, installation-id
/// management, and the enabled flag.
///
/// The NATIVE pieces are phase 3 — they map onto Flutter plugins, not literal
/// translations:
///   • APNs/FCM token acquisition + permission prompts → `firebase_messaging` +
///     `permission_handler`. The push layer obtains the token then calls
///     [registerDeviceToken].
///   • local-notification scheduling → `flutter_local_notifications`.
///   • in-app banner + tap navigation → handled in the UI/router layer.
class NotificationService {
  NotificationService(this._api, this._secureStorage);

  final ApiClient _api;
  final SecureStorageService _secureStorage;

  static const _installationIdKey = 'notification_installation_id';
  static const _deviceTokenKey = 'notification_device_token';
  static const _registrationIdKey = 'notification_registration_id';
  static const _notificationEnabledKey = 'notifications_enabled';

  bool _isInitialized = false;
  String _deviceToken = '';
  String _registrationId = '';
  String _installationId = '';

  bool get isInitialized => _isInitialized;

  /// TODO(phase 3): acquire notification permission + APNs/FCM token via
  /// firebase_messaging/permission_handler, then call [registerDeviceToken].
  /// Returns false until the native push layer is wired.
  Future<bool> initialize() async {
    _installationId = await _getInstallationId();
    return false;
  }

  /// Registers a device token with the server (portable core of the C#
  /// RegisterWithAzureNotificationHubAsync). Called by the phase-3 push layer
  /// once it has obtained the platform token.
  Future<bool> registerDeviceToken(
      {required String deviceToken, required String platform}) async {
    try {
      final userEmail = await _secureStorage.getSecureEmail();
      if (userEmail.isEmpty) return false;
      _deviceToken = deviceToken;
      _installationId = await _getInstallationId();
      final plat = platform.toLowerCase();

      final json = await _api.postJson(
        'api/notifications/register',
        NotificationRegisterRequest(
          deviceToken: deviceToken,
          platform: plat,
          userEmail: userEmail,
          installationId: _installationId,
          tags: _tagsFor(userEmail, plat),
        ).toJson(),
      );
      if (json is Map<String, dynamic>) {
        final resp = NotificationRegistrationResponse.fromJson(json);
        if (resp.success) {
          _registrationId = resp.registrationId.toString();
          await _secureStorage.secureStore(_registrationIdKey, _registrationId);
          await _secureStorage.secureStore(_deviceTokenKey, deviceToken);
          _isInitialized = true;
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// iOS STANDARD APNs (alert) token registration. Kept SEPARATE from the VoIP-token
  /// registration (which also uses platform 'ios' but the same base installation id): we
  /// give the alert installation a distinct id ("{base}-apns") so the two don't overwrite
  /// each other in the Notification Hub — VoIP delivers calls, this delivers alerts.
  Future<bool> registerApnsAlertToken(String apnsToken) async {
    try {
      final userEmail = await _secureStorage.getSecureEmail();
      if (userEmail.isEmpty || apnsToken.isEmpty) return false;
      final installationId = '${await _getInstallationId()}-apns';
      const plat = 'ios';
      final json = await _api.postJson(
        'api/notifications/register',
        NotificationRegisterRequest(
          deviceToken: apnsToken,
          platform: plat,
          userEmail: userEmail,
          installationId: installationId,
          tags: _tagsFor(userEmail, plat),
        ).toJson(),
      );
      return json is Map<String, dynamic> &&
          NotificationRegistrationResponse.fromJson(json).success;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateRegistration({List<String>? additionalTags}) async {
    try {
      if (_registrationId.isEmpty) return false;
      final userEmail = await _secureStorage.getSecureEmail();
      final platform = _platform();
      final tags = _tagsFor(userEmail, platform);
      if (additionalTags != null) tags.addAll(additionalTags);

      final json = await _api.postJson(
        'api/notifications/update',
        NotificationUpdateRequest(
          registrationId: int.tryParse(_registrationId) ?? 0,
          deviceToken: _deviceToken,
          installationId: _installationId,
          tags: tags,
        ).toJson(),
      );
      return json is Map<String, dynamic> &&
          NotificationRegistrationResponse.fromJson(json).success;
    } catch (_) {
      return false;
    }
  }

  Future<bool> areNotificationsEnabled() async {
    try {
      final enabled =
          await _secureStorage.secureRetrieve(_notificationEnabledKey, 'true');
      return enabled.toLowerCase() == 'true';
    } catch (_) {
      return true;
    }
  }

  Future<NotificationRegistrationInfo> getRegistrationInfo() async {
    return NotificationRegistrationInfo(
      deviceToken: _deviceToken,
      registrationId: _registrationId,
      isInitialized: _isInitialized,
      platform: _platform(),
      userEmail: await _secureStorage.getSecureEmail(),
      notificationsEnabled: await areNotificationsEnabled(),
    );
  }

  // ---- Local notifications + foreground display ---------------------------

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _localInitialized = false;

  static const _androidChannel = AndroidNotificationChannel(
    'coharmony_default',
    'CoHarmony Notifications',
    description: 'Messages, invites, payments, and schedule reminders',
    importance: Importance.high,
  );

  /// Dedicated max-importance channel for calls (separate sound, heads-up, and
  /// bypasses Do-Not-Disturb where allowed). The native CallKit full-screen UI
  /// is the primary surface; this backs the missed-call / fallback notification.
  static const _callsChannel = AndroidNotificationChannel(
    'coharmony_calls',
    'Calls',
    description: 'Incoming and missed voice/video calls',
    importance: Importance.max,
    playSound: true,
  );

  /// Initialises the local-notifications plugin + Android channel. The tap
  /// callback routes via [handleNotificationTapped] using the payload type.
  Future<void> initLocalNotifications() async {
    if (_localInitialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) {
          handleNotificationTapped(getNotificationType({'type': payload}), const {});
        }
      },
    );
    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_androidChannel);
    await androidImpl?.createNotificationChannel(_callsChannel);
    _localInitialized = true;
  }

  /// Displays a local notification immediately (port of
  /// `ScheduleLocalNotification`; scheduling a future time would additionally
  /// need the `timezone` package, but no caller schedules ahead).
  Future<void> scheduleLocalNotification(
      String title, String body, DateTime scheduledTime,
      {NotificationType type = NotificationType.eventComingUp}) async {
    try {
      await initLocalNotifications();
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      );
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
        payload: type.name,
      );
    } catch (_) {
      // Local notifications are best-effort.
    }
  }

  /// Shows an in-app banner for a received notification (port of
  /// `HandleNotificationReceived`). Message banners are suppressed while a chat
  /// screen is open (real-time delivery covers it).
  void handleNotificationReceived(
      NotificationType type, String? title, String? body, Map<String, String> data) {
    if ((type == NotificationType.messageReceived ||
            type == NotificationType.courtMessage) &&
        AppNavigation.inChat) {
      return;
    }
    AppNotificationBanner.show(
      title: title ?? getDefaultTitle(type),
      body: (body == null || body.isEmpty) ? 'New notification' : body,
      type: type,
      onTapped: () => handleNotificationTapped(type, data),
    );
  }

  /// Routes a notification tap to the relevant surface (port of
  /// `HandleNotificationTapped`). Tab indices: 1 Schedule, 2 Messager, 3 Payments.
  void handleNotificationTapped(NotificationType type, Map<String, String> data) {
    switch (type) {
      case NotificationType.messageReceived:
      case NotificationType.courtMessage:
        AppNavigation.goToTab?.call(2);
        break;
      case NotificationType.partnerInviteReceived:
      case NotificationType.partnerInviteAccepted:
      case NotificationType.partnerInviteDeclined:
        AppNavigation.navigatorKey.currentState
            ?.push(MaterialPageRoute(builder: (_) => const PartnerPage()));
        break;
      case NotificationType.paymentComingUp:
        AppNavigation.goToTab?.call(3);
        break;
      case NotificationType.eventComingUp:
      case NotificationType.scheduleReminder:
      case NotificationType.custodyUpdate:
      case NotificationType.custodyResponse:
        AppNavigation.goToTab?.call(1);
        break;
      case NotificationType.incomingCall:
      case NotificationType.callEnded:
        // Calls are handled natively (CallKit); tapping a missed-call entry
        // just opens the Messager tab where the call history lives.
        AppNavigation.goToTab?.call(2);
        break;
    }
  }

  // ---- Pure helpers -------------------------------------------------------

  /// AOT-safe enum parsing from a push-data map (matches the C# switch).
  NotificationType getNotificationType(Map<String, String> data) {
    switch (data['type']?.toLowerCase()) {
      case 'messagereceived':
        return NotificationType.messageReceived;
      case 'partnerinvitereceived':
        return NotificationType.partnerInviteReceived;
      case 'partnerinviteaccepted':
        return NotificationType.partnerInviteAccepted;
      case 'partnerinvitedeclined':
        return NotificationType.partnerInviteDeclined;
      case 'paymentcomingup':
        return NotificationType.paymentComingUp;
      case 'eventcomingup':
        return NotificationType.eventComingUp;
      case 'schedulereminder':
        return NotificationType.scheduleReminder;
      case 'courtmessage':
        return NotificationType.courtMessage;
      case 'custodyresponse':
        return NotificationType.custodyResponse;
      case 'custodyupdate':
        return NotificationType.custodyUpdate;
      case 'incomingcall':
        return NotificationType.incomingCall;
      case 'callended':
        return NotificationType.callEnded;
      default:
        return NotificationType.messageReceived;
    }
  }

  static String getDefaultTitle(NotificationType type) {
    switch (type) {
      case NotificationType.messageReceived:
        return 'New Message';
      case NotificationType.courtMessage:
        return 'Court Message';
      case NotificationType.partnerInviteReceived:
        return 'Partner Invite';
      case NotificationType.partnerInviteAccepted:
        return 'Invite Accepted';
      case NotificationType.partnerInviteDeclined:
        return 'Invite Declined';
      case NotificationType.paymentComingUp:
        return 'Payment Reminder';
      case NotificationType.eventComingUp:
        return 'Upcoming Event';
      case NotificationType.scheduleReminder:
        return 'Schedule Reminder';
      case NotificationType.custodyUpdate:
        return 'Custody Update';
      case NotificationType.custodyResponse:
        return 'Custody Response';
      case NotificationType.incomingCall:
        return 'Incoming Call';
      case NotificationType.callEnded:
        return 'Missed Call';
    }
  }

  List<String> _tagsFor(String userEmail, String platform) => [
        'user:$userEmail',
        'platform:$platform',
        'message_notifications',
        'partner_notifications',
        'payment_notifications',
        'event_notifications',
      ];

  Future<String> _getInstallationId() async {
    if (_installationId.isNotEmpty) return _installationId;
    final cached = await _secureStorage.secureRetrieve(_installationIdKey);
    if (cached.isNotEmpty) return cached;
    final newId = _newGuid();
    await _secureStorage.secureStore(_installationIdKey, newId);
    return newId;
  }

  /// Platform tag. TODO(phase 3): derive from the real platform at the push
  /// layer; defaults based on the host OS.
  String _platform() => 'flutter';

  static String _newGuid() {
    final rng = Random.secure();
    String hex(int n) =>
        List.generate(n, (_) => rng.nextInt(16).toRadixString(16)).join();
    // v4 UUID layout.
    final b = StringBuffer()
      ..write(hex(8))
      ..write('-')
      ..write(hex(4))
      ..write('-4')
      ..write(hex(3))
      ..write('-')
      ..write((8 + rng.nextInt(4)).toRadixString(16))
      ..write(hex(3))
      ..write('-')
      ..write(hex(12));
    return b.toString();
  }
}
