// DTOs for the auth domain. 1:1 with the C# classes in `AppJsonContext.cs`
// (and the inline response types in `AuthService.cs`). JSON keys are camelCase
// to match the client's `JsonKnownNamingPolicy.CamelCase` serialization.

DateTime? _parseDate(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString());

// ---- Requests --------------------------------------------------------------

class LoginRequest {
  LoginRequest({required this.email, required this.password});
  final String email;
  final String password;
  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}

class RegistrationRequest {
  RegistrationRequest({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    this.address = '',
  });
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String address;
  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
        'phoneNumber': phoneNumber,
        'address': address,
      };
}

class RefreshTokenRequest {
  RefreshTokenRequest({required this.refreshToken});
  final String refreshToken;
  Map<String, dynamic> toJson() => {'refreshToken': refreshToken};
}

class RevokeTokenRequest {
  RevokeTokenRequest({this.refreshToken});
  final String? refreshToken;
  Map<String, dynamic> toJson() => {'refreshToken': refreshToken};
}

class UserUpdateRequest {
  UserUpdateRequest({
    this.newEmail = '',
    this.phoneNumber = '',
    this.address = '',
    this.newPassword = '',
    this.currentPassword = '',
  });
  final String newEmail;
  final String phoneNumber;
  final String address;
  final String newPassword;
  final String currentPassword;
  Map<String, dynamic> toJson() => {
        'newEmail': newEmail,
        'phoneNumber': phoneNumber,
        'address': address,
        'newPassword': newPassword,
        'currentPassword': currentPassword,
      };
}

class VerificationCodeRequest {
  VerificationCodeRequest({required this.code});
  final String code;
  Map<String, dynamic> toJson() => {'code': code};
}

class SmsVerificationRequest {
  SmsVerificationRequest({required this.phoneNumber});
  final String phoneNumber;
  Map<String, dynamic> toJson() => {'phoneNumber': phoneNumber};
}

class SmsVerifyRequest {
  SmsVerifyRequest({required this.phoneNumber, required this.code});
  final String phoneNumber;
  final String code;
  Map<String, dynamic> toJson() => {'phoneNumber': phoneNumber, 'code': code};
}

class PartnerInviteRequest {
  PartnerInviteRequest({required this.partnerEmail});
  final String partnerEmail;
  Map<String, dynamic> toJson() => {'partnerEmail': partnerEmail};
}

class NotificationEnabledRequest {
  NotificationEnabledRequest({required this.enabled, this.type});
  final bool enabled;
  final String? type;
  Map<String, dynamic> toJson() => {'enabled': enabled, 'type': type};
}

class LawyerEmailRequest {
  LawyerEmailRequest({required this.lawyerEmail});
  final String lawyerEmail;
  Map<String, dynamic> toJson() => {'lawyerEmail': lawyerEmail};
}

class PasswordResetRequest {
  PasswordResetRequest({required this.email});
  final String email;
  Map<String, dynamic> toJson() => {'email': email};
}

class VerifyResetCodeRequest {
  VerifyResetCodeRequest({required this.email, required this.code});
  final String email;
  final String code;
  Map<String, dynamic> toJson() => {'email': email, 'code': code};
}

class CompletePasswordResetRequest {
  CompletePasswordResetRequest({
    required this.email,
    required this.code,
    required this.newPassword,
  });
  final String email;
  final String code;
  final String newPassword;
  Map<String, dynamic> toJson() =>
      {'email': email, 'code': code, 'newPassword': newPassword};
}

class ChildInviteRequest {
  ChildInviteRequest({required this.childEmail});
  final String childEmail;
  Map<String, dynamic> toJson() => {'childEmail': childEmail};
}

class ChildInviteActionRequest {
  ChildInviteActionRequest({required this.parentEmail});
  final String parentEmail;
  Map<String, dynamic> toJson() => {'parentEmail': parentEmail};
}

// ---- Responses -------------------------------------------------------------

class TokenResponse {
  TokenResponse({this.token, this.refreshToken, this.expiresInMinutes = 0});
  final String? token;
  final String? refreshToken;
  final int expiresInMinutes;
  factory TokenResponse.fromJson(Map<String, dynamic> j) => TokenResponse(
        token: j['token'] as String?,
        refreshToken: j['refreshToken'] as String?,
        expiresInMinutes: (j['expiresInMinutes'] as num?)?.toInt() ?? 0,
      );
}

class RefreshTokenResponse {
  RefreshTokenResponse({this.token, this.refreshToken, this.expiresInMinutes = 0});
  final String? token;
  final String? refreshToken;
  final int expiresInMinutes;
  factory RefreshTokenResponse.fromJson(Map<String, dynamic> j) =>
      RefreshTokenResponse(
        token: j['token'] as String?,
        refreshToken: j['refreshToken'] as String?,
        expiresInMinutes: (j['expiresInMinutes'] as num?)?.toInt() ?? 0,
      );
}

class RegistrationResponse {
  RegistrationResponse({this.success = false, this.message, this.userId});
  final bool success;
  final String? message;
  final String? userId;
  factory RegistrationResponse.fromJson(Map<String, dynamic> j) =>
      RegistrationResponse(
        success: j['success'] as bool? ?? false,
        message: j['message'] as String?,
        userId: j['userId'] as String?,
      );
}

class UserInfo {
  UserInfo({
    this.email,
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.address,
    this.inviteStatus,
    this.partnerEmail,
    this.emailConfirmed = false,
    this.phoneNumConfirmed = false,
    this.courtLocked = false,
    this.hasBankAccount = false,
    this.bankName,
    this.accountNumberPreview,
    this.accountType,
    this.onboardingComplete = false,
  });
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;
  final String? address;
  final String? inviteStatus;
  final String? partnerEmail;
  final bool emailConfirmed;
  final bool phoneNumConfirmed;
  final bool courtLocked;
  final bool hasBankAccount;
  final String? bankName;
  final String? accountNumberPreview;
  final String? accountType;
  final bool onboardingComplete;
  factory UserInfo.fromJson(Map<String, dynamic> j) {
    // CRITICAL: the server builds this response with `JsonSerializer.Serialize(userInfo)`
    // on a plain class with NO [JsonPropertyName] attributes, so the keys come back
    // **PascalCase** ("PartnerEmail", "InviteStatus", "AccountType", "EmailConfirmed"),
    // unlike every other (camelCase) endpoint. MAUI's deserializer is case-insensitive;
    // our map access is not. Read case-insensitively so partner-link / account-type /
    // email-verified detection actually works (this was the onboarding loop).
    final m = <String, dynamic>{
      for (final e in j.entries) e.key.toLowerCase(): e.value,
    };
    bool boolOf(String k) {
      final v = m[k.toLowerCase()];
      return v == true || (v is String && v.toLowerCase() == 'true');
    }
    return UserInfo(
      email: m['email'] as String?,
      firstName: m['firstname'] as String?,
      lastName: m['lastname'] as String?,
      phoneNumber: m['phonenumber'] as String?,
      address: m['address'] as String?,
      inviteStatus: m['invitestatus'] as String?,
      partnerEmail: m['partneremail'] as String?,
      emailConfirmed: boolOf('emailconfirmed'),
      phoneNumConfirmed: boolOf('phonenumconfirmed'),
      courtLocked: boolOf('courtlocked'),
      hasBankAccount: boolOf('hasbankaccount'),
      bankName: m['bankname'] as String?,
      accountNumberPreview: m['accountnumberpreview'] as String?,
      accountType: m['accounttype'] as String?,
      onboardingComplete: boolOf('onboardingcomplete'),
    );
  }
}

class PartnerInviteInfo {
  PartnerInviteInfo({
    this.valid = false,
    this.inviterName,
    this.inviterEmail,
    this.synced = false,
    this.status,
    this.partnerHasAccount = false,
    this.partnerSubscribed = false,
  });
  final bool valid;
  final String? inviterName;
  final String? inviterEmail;
  final bool synced;
  final String? status;
  /// Whether the invited/inviting partner has a CoHarmony account yet.
  final bool partnerHasAccount;
  /// Whether that partner currently has an active subscription.
  final bool partnerSubscribed;
  factory PartnerInviteInfo.fromJson(Map<String, dynamic> j) => PartnerInviteInfo(
        valid: j['valid'] as bool? ?? false,
        inviterName: j['inviterName'] as String?,
        inviterEmail: j['inviterEmail'] as String?,
        synced: j['synced'] as bool? ?? false,
        status: j['status'] as String?,
        partnerHasAccount: j['partnerHasAccount'] as bool? ?? false,
        partnerSubscribed: j['partnerSubscribed'] as bool? ?? false,
      );
}

class LawyerRequestInfo {
  LawyerRequestInfo({
    this.lawyerEmail,
    this.lawyerName,
    this.lawyerFirm,
    this.lawyerBarNumber,
    this.requestedAt,
    this.notes,
  });
  final String? lawyerEmail;
  final String? lawyerName;
  final String? lawyerFirm;
  final String? lawyerBarNumber;
  final DateTime? requestedAt;
  final String? notes;
  factory LawyerRequestInfo.fromJson(Map<String, dynamic> j) => LawyerRequestInfo(
        lawyerEmail: j['lawyerEmail'] as String?,
        lawyerName: j['lawyerName'] as String?,
        lawyerFirm: j['lawyerFirm'] as String?,
        lawyerBarNumber: j['lawyerBarNumber'] as String?,
        requestedAt: _parseDate(j['requestedAt']),
        notes: j['notes'] as String?,
      );
}

class LawyerInfo {
  LawyerInfo({
    this.lawyerEmail,
    this.lawyerName,
    this.lawyerFirm,
    this.lawyerBarNumber,
    this.approvedAt,
  });
  final String? lawyerEmail;
  final String? lawyerName;
  final String? lawyerFirm;
  final String? lawyerBarNumber;
  final DateTime? approvedAt;
  factory LawyerInfo.fromJson(Map<String, dynamic> j) => LawyerInfo(
        lawyerEmail: j['lawyerEmail'] as String?,
        lawyerName: j['lawyerName'] as String?,
        lawyerFirm: j['lawyerFirm'] as String?,
        lawyerBarNumber: j['lawyerBarNumber'] as String?,
        approvedAt: _parseDate(j['approvedAt']),
      );
}

/// Inline response type from `AuthService.cs` (distinct from
/// `NotificationPreferencesResponse` in AppJsonContext).
class NotificationPrefsResponse {
  NotificationPrefsResponse({this.success = false, this.enabled = true});
  final bool success;
  final bool enabled;
  factory NotificationPrefsResponse.fromJson(Map<String, dynamic> j) =>
      NotificationPrefsResponse(
        success: j['success'] as bool? ?? false,
        enabled: j['enabled'] as bool? ?? true,
      );
}

class ChildInviteInfo {
  ChildInviteInfo({
    this.parentEmail,
    this.parentName,
    this.otherParentEmail,
    this.otherParentName,
  });
  final String? parentEmail;
  final String? parentName;
  final String? otherParentEmail;
  final String? otherParentName;
  factory ChildInviteInfo.fromJson(Map<String, dynamic> j) => ChildInviteInfo(
        parentEmail: j['parentEmail'] as String?,
        parentName: j['parentName'] as String?,
        otherParentEmail: j['otherParentEmail'] as String?,
        otherParentName: j['otherParentName'] as String?,
      );
}

class ChildInviteListResponse {
  ChildInviteListResponse({
    this.hasInvites = false,
    this.isAccepted = false,
    this.acceptedParentEmail,
    this.invites = const [],
  });
  final bool hasInvites;
  final bool isAccepted;
  final String? acceptedParentEmail;
  final List<ChildInviteInfo> invites;
  factory ChildInviteListResponse.fromJson(Map<String, dynamic> j) =>
      ChildInviteListResponse(
        hasInvites: j['hasInvites'] as bool? ?? false,
        isAccepted: j['isAccepted'] as bool? ?? false,
        acceptedParentEmail: j['acceptedParentEmail'] as String?,
        invites: (j['invites'] as List<dynamic>? ?? [])
            .map((e) => ChildInviteInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ChildInfo {
  ChildInfo({this.email, this.firstName, this.lastName, this.isAccepted = false});
  final String? email;
  final String? firstName;
  final String? lastName;
  final bool isAccepted;
  factory ChildInfo.fromJson(Map<String, dynamic> j) => ChildInfo(
        email: j['email'] as String?,
        firstName: j['firstName'] as String?,
        lastName: j['lastName'] as String?,
        isAccepted: j['isAccepted'] as bool? ?? false,
      );
}

class FamilyInfo {
  FamilyInfo({
    this.parent1Email,
    this.parent1Name,
    this.parent2Email,
    this.parent2Name,
    this.siblings = const [],
  });
  final String? parent1Email;
  final String? parent1Name;
  final String? parent2Email;
  final String? parent2Name;
  final List<ChildInfo> siblings;
  factory FamilyInfo.fromJson(Map<String, dynamic> j) => FamilyInfo(
        parent1Email: j['parent1Email'] as String?,
        parent1Name: j['parent1Name'] as String?,
        parent2Email: j['parent2Email'] as String?,
        parent2Name: j['parent2Name'] as String?,
        siblings: (j['siblings'] as List<dynamic>? ?? [])
            .map((e) => ChildInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
