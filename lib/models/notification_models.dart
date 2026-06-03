// DTOs for the notifications domain. 1:1 with the request types in
// AppJsonContext.cs + the response/info types in `NotificationService.cs`.
// Default camelCase naming.

class NotificationRegisterRequest {
  NotificationRegisterRequest({
    required this.deviceToken,
    required this.platform,
    required this.userEmail,
    required this.installationId,
    required this.tags,
  });
  final String deviceToken;
  final String platform;
  final String userEmail;
  final String installationId;
  final List<String> tags;
  Map<String, dynamic> toJson() => {
        'deviceToken': deviceToken,
        'platform': platform,
        'userEmail': userEmail,
        'installationId': installationId,
        'tags': tags,
      };
}

class NotificationUpdateRequest {
  NotificationUpdateRequest({
    required this.registrationId,
    required this.deviceToken,
    required this.installationId,
    required this.tags,
  });
  final int registrationId;
  final String deviceToken;
  final String installationId;
  final List<String> tags;
  Map<String, dynamic> toJson() => {
        'registrationId': registrationId,
        'deviceToken': deviceToken,
        'installationId': installationId,
        'tags': tags,
      };
}

class NotificationRegistrationResponse {
  NotificationRegistrationResponse({
    this.success = false,
    this.registrationId = 0,
    this.message,
    this.tags = const [],
  });
  final bool success;
  final int registrationId;
  final String? message;
  final List<String> tags;
  factory NotificationRegistrationResponse.fromJson(Map<String, dynamic> j) =>
      NotificationRegistrationResponse(
        success: j['success'] as bool? ?? false,
        registrationId: (j['registrationId'] as num?)?.toInt() ?? 0,
        message: j['message'] as String?,
        tags: (j['tags'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      );
}

class NotificationRegistrationInfo {
  NotificationRegistrationInfo({
    this.deviceToken = '',
    this.registrationId = '',
    this.isInitialized = false,
    this.platform = '',
    this.userEmail = '',
    this.notificationsEnabled = true,
  });
  final String deviceToken;
  final String registrationId;
  final bool isInitialized;
  final String platform;
  final String userEmail;
  final bool notificationsEnabled;
}
