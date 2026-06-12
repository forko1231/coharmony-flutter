import '../models/auth_models.dart';
import 'api_client.dart';
import 'preferences.dart';
import 'secure_storage_service.dart';
import 'service_locator.dart';
import 'token_service.dart';

/// Current Terms-of-Service version, matching what the backend publishes via
/// `GET api/legal/terms` (`version: "1.0"`). Bump this alongside the legal docs
/// (LegalController) so the server-side acceptance audit trail names the right
/// revision.
const String kTermsOfServiceVersion = '1.0';

/// Port of `Services/AuthService.cs`. Faithful 1:1 reproduction of every
/// endpoint, payload and side-effect. Cross-checked against
/// `SplitServer/Controllers/AuthController.cs`.
class AuthService {
  AuthService(this._api, this._secureStorage, this._tokenService);

  final ApiClient _api;
  final SecureStorageService _secureStorage;
  final TokenService _tokenService;

  // ---- Login / session ----------------------------------------------------

  Future<bool> login(String email, String password) async {
    try {
      final json = await _api.postJson(
          'api/auth/token', LoginRequest(email: email, password: password).toJson());
      if (json is Map<String, dynamic>) {
        final tokenResponse = TokenResponse.fromJson(json);
        if (tokenResponse.token != null && tokenResponse.token!.isNotEmpty) {
          await _tokenService.setToken(
            tokenResponse.token!,
            DateTime.now().toUtc().add(Duration(minutes: tokenResponse.expiresInMinutes)),
            tokenResponse.refreshToken,
          );
          await _secureStorage.storeCredentials(email, password);
          _api.setAuthToken(tokenResponse.token);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Exchanges a Google ID token for our app session. The backend find-or-creates
  /// the account and issues our JWT directly (no email-code MFA — Google already
  /// authenticated). Stores the same tokens as a normal login.
  Future<bool> signInWithGoogle(String idToken) async {
    try {
      final json = await _api.postJson('api/auth/google', {'idToken': idToken});
      if (json is Map<String, dynamic>) {
        final tokenResponse = TokenResponse.fromJson(json);
        if (tokenResponse.token != null && tokenResponse.token!.isNotEmpty) {
          await _tokenService.setToken(
            tokenResponse.token!,
            DateTime.now().toUtc().add(Duration(minutes: tokenResponse.expiresInMinutes)),
            tokenResponse.refreshToken,
          );
          _api.setAuthToken(tokenResponse.token);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Exchanges an Apple identity token for our app session. [firstName]/[lastName]
  /// are only available on the user's first Apple sign-in. No MFA. The email cache
  /// is synced from the server record (never from Apple's relay credential).
  Future<bool> signInWithApple(String identityToken, {String? firstName, String? lastName}) async {
    try {
      final json = await _api.postJson('api/auth/apple', {
        'idToken': identityToken,
        if (firstName != null && firstName.isNotEmpty) 'firstName': firstName,
        if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
      });
      if (json is Map<String, dynamic>) {
        final tr = TokenResponse.fromJson(json);
        if (tr.token != null && tr.token!.isNotEmpty) {
          await _tokenService.setToken(
            tr.token!,
            DateTime.now().toUtc().add(Duration(minutes: tr.expiresInMinutes)),
            tr.refreshToken,
          );
          _api.setAuthToken(tr.token);
          await _syncEmailFromServer();
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Sends a verification code to a proposed real contact email (replacing an Apple
  /// "Hide My Email" relay). Returns true if the code was sent.
  Future<bool> requestContactEmail(String email) async {
    try {
      final json = await _api.postJson('api/auth/email/change/request', {'email': email});
      return json is Map<String, dynamic> && json['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Confirms the code, swaps the account email server-side, and stores the re-issued
  /// token (the old token's subject was the relay email). Returns true on success.
  Future<bool> confirmContactEmail(String code) async {
    try {
      final json = await _api.postJson('api/auth/email/change/confirm', {'code': code});
      if (json is Map<String, dynamic>) {
        final tr = TokenResponse.fromJson(json);
        if (tr.token != null && tr.token!.isNotEmpty) {
          await _tokenService.setToken(
            tr.token!,
            DateTime.now().toUtc().add(Duration(minutes: tr.expiresInMinutes)),
            tr.refreshToken,
          );
          _api.setAuthToken(tr.token);
          await _syncEmailFromServer();
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Caches the signed-in email from the authoritative server record (not from any
  /// SSO credential) for the few screens that still read the local 'email' pref.
  Future<void> _syncEmailFromServer() async {
    try {
      final info = await getUserInfo();
      final email = info?.email;
      if (email != null && email.isNotEmpty) {
        await Preferences.setString('email', email);
      }
    } catch (_) {/* best-effort cache */}
  }

  /// Attempts to restore a session from stored tokens.
  Future<bool> tryRestoreSession() async {
    try {
      final currentToken = await _tokenService.getToken();
      final tokenExpiry = await _tokenService.getTokenExpiry();

      if (currentToken.isNotEmpty && tokenExpiry != null) {
        if (tokenExpiry.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))) {
          _api.setAuthToken(currentToken);
          return true;
        } else {
          final refresh = await _tokenService.refreshToken(_api);
          if (refresh.outcome == RefreshOutcome.refreshed &&
              refresh.token != null &&
              refresh.token!.isNotEmpty) {
            _api.setAuthToken(refresh.token);
            return true;
          }
          if (refresh.outcome == RefreshOutcome.transient) {
            // Couldn't reach the server (e.g. offline cold start) — NOT an
            // auth rejection. Keep the session alive with the existing token;
            // the 401→refresh path retries once connectivity returns, and a
            // genuine rejection then routes back to login via onAuthFailure.
            _api.setAuthToken(currentToken);
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createAccount(String email, String password, String firstName,
      String lastName, String phoneNumber) async {
    try {
      final json = await _api.postJson(
        'api/auth/register',
        RegistrationRequest(
          email: email,
          password: password,
          firstName: firstName,
          lastName: lastName,
          phoneNumber: phoneNumber,
          address: '',
        ).toJson(),
      );
      if (json is Map<String, dynamic>) {
        final response = RegistrationResponse.fromJson(json);
        if (response.success) {
          await _secureStorage.storeCredentials(email, password);
          await _secureStorage.secureStore('firstName', firstName);
          await _secureStorage.secureStore('lastName', lastName);
          await _secureStorage.secureStore('phoneNum', phoneNumber);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Central logout: ALL sign-out paths (main settings, child settings,
  /// subscription paywall, and the session-expired handler in
  /// `ServiceLocator._handleSessionExpired`) funnel through here so the device
  /// is left with no trace of the previous user's session. Every server call
  /// is best-effort — local cleanup ALWAYS runs, even fully offline. Steps,
  /// in order:
  ///   1. disconnect the WebSocket (intentional — no auto-reconnect);
  ///   2. unregister this device's push installation (needs the still-valid
  ///      auth token) and revoke the refresh token server-side;
  ///   3. drop tokens locally and clear the in-flight auth header;
  ///   4. wipe per-conversation message encryption keys (secure storage +
  ///      both in-memory caches — they are server-issued and re-fetched on
  ///      the next sign-in);
  ///   5. remove credentials (unless RememberMe) and cached bank fields;
  ///   6. clear Preferences (matches the previous child/subscription-path
  ///      behaviour — wipes email/AccountType/onboarding flags).
  Future<void> logout() async {
    // 1. Stop real-time traffic so the old user's events stop arriving.
    try {
      await ServiceLocator.webSocket.disconnect();
    } catch (_) {/* best-effort (also unset in unit tests) */}

    // 2. Server-side teardown while the token is still valid. Push first:
    //    the unregister endpoint is [Authorize]d, so it must precede revoke.
    try {
      await ServiceLocator.push.unregister();
    } catch (_) {/* best-effort */}
    try {
      final refreshToken = await _tokenService.getRefreshToken();
      if (refreshToken.isNotEmpty) {
        await _revokeTokensWithServer(refreshToken);
      }
    } catch (_) {/* best-effort */}

    // 3. Local session teardown — always runs.
    try {
      await _tokenService.removeToken();
    } catch (_) {/* keep going: the rest of the cleanup must still run */}
    _api.setAuthToken(null);

    // 4. Per-conversation encryption keys + their in-memory caches.
    try {
      ServiceLocator.messageEncryption.clearKeyCache();
    } catch (_) {/* best-effort (also unset in unit tests) */}
    try {
      await _secureStorage.clearMessageEncryptionKeys();
    } catch (_) {/* best-effort */}

    // 5. Credentials (kept only with RememberMe) and cached bank data.
    try {
      final rememberMe = Preferences.getBool('RememberMe', false);
      if (!rememberMe) {
        await _secureStorage.secureRemove('secure_email');
        await _secureStorage.secureRemove('secure_password');
      }
      await _secureStorage.secureRemove('secure_bank_account');
      await _secureStorage.secureRemove('secure_bank_routing');
    } catch (_) {/* best-effort */}

    // 6. App preferences — AFTER the RememberMe read above. Same wipe the
    //    child/subscription paths always did; now every path gets it.
    try {
      await Preferences.clear();
    } catch (_) {/* best-effort */}
  }

  Future<bool> _revokeTokensWithServer(String? refreshToken) async {
    try {
      final result = await _api.postJson(
          'api/auth/revoke', RevokeTokenRequest(refreshToken: refreshToken).toJson());
      return result is bool ? result : false;
    } catch (_) {
      return false;
    }
  }

  // ---- User info ----------------------------------------------------------

  Future<UserInfo?> getUserInfo() async {
    try {
      final json = await _api.getJson('api/auth/user/info');
      return json is Map<String, dynamic> ? UserInfo.fromJson(json) : null;
    } catch (_) {
      return null;
    }
  }

  /// Persists onboarding completion server-side so the user is never re-onboarded
  /// on a fresh install / new device. Best-effort (fire-and-forget).
  Future<void> markOnboardingComplete() async {
    try {
      await _api.postJson('api/auth/onboarding-complete', <String, dynamic>{});
    } catch (_) {
      // Non-fatal: local completion still stands; backfill will catch it later.
    }
  }

  /// Records the user's Terms-of-Service consent server-side
  /// (`POST api/legal/accept-terms`, [Authorize]d — call only after a token is
  /// set). The backend writes a `TERMS_ACCEPTED` audit-log row (email, version,
  /// UTC timestamp), giving a provable acceptance trail for court-facing
  /// records. Best-effort fire-and-forget: the signup UI already gates on the
  /// consent checkbox, so a network blip here must never block the flow.
  Future<void> recordTermsAcceptance() async {
    try {
      await _api.postJson(
          'api/legal/accept-terms', {'version': kTermsOfServiceVersion});
    } catch (_) {
      // Non-fatal: consent was still given in the UI; nothing to surface.
    }
  }

  /// SECURITY: when changing email or password, [currentPassword] MUST be
  /// supplied or the server rejects the request.
  Future<String> updateUserInfo({
    String newEmail = '',
    String phoneNumber = '',
    String address = '',
    String newPassword = '',
    String currentPassword = '',
  }) async {
    try {
      // NOTE: server exposes this as PUT (`[HttpPut("user/update")]`); the MAUI
      // client POSTed here (a latent 405 mismatch). Using PUT to match the server.
      final result = await _api.putForString(
        'api/auth/user/update',
        UserUpdateRequest(
          newEmail: newEmail,
          phoneNumber: phoneNumber,
          address: address,
          newPassword: newPassword,
          currentPassword: currentPassword,
        ).toJson(),
      );

      if (newEmail.isNotEmpty) {
        await _secureStorage.secureStore('secure_email', newEmail);
      }
      if (newPassword.isNotEmpty) {
        await _secureStorage.secureStore('secure_password', newPassword);
        await _tokenService.removeToken();
        _api.setAuthToken(null);
      }
      if (phoneNumber.isNotEmpty) {
        await _secureStorage.secureStore('phoneNum', phoneNumber);
      }
      return result;
    } catch (_) {
      return 'Error updating user information';
    }
  }

  // ---- Email / SMS verification ------------------------------------------

  Future<bool> sendVerificationCode() async {
    try {
      final r = await _api.postJson('api/auth/verification/send', <String, dynamic>{});
      return r is bool ? r : false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyEmailWithCode(String verificationCode) async {
    try {
      final r = await _api.postJson(
          'api/auth/verification/verify', VerificationCodeRequest(code: verificationCode).toJson());
      return r is bool ? r : false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendSmsVerificationCode(String phoneNumber) async {
    try {
      final formatted = _formatPhoneNumber(phoneNumber);
      final r = await _api.postJson(
          'api/auth/sms/send', SmsVerificationRequest(phoneNumber: formatted).toJson());
      return r is bool ? r : false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifySmsCode(String phoneNumber, String code) async {
    try {
      final formatted = _formatPhoneNumber(phoneNumber);
      final r = await _api.postJson('api/auth/sms/verify',
          SmsVerifyRequest(phoneNumber: formatted, code: code).toJson());
      return r is bool ? r : false;
    } catch (_) {
      return false;
    }
  }

  /// Robust truthiness for a decoded JSON value: a JSON boolean decodes to a Dart
  /// `bool`, but defensively accept the string forms ("true"/"True") too.
  static bool _isTrue(dynamic v) =>
      v == true || (v is String && v.toLowerCase() == 'true');

  static String _formatPhoneNumber(String phoneNumber) {
    final digitsOnly =
        phoneNumber.split('').where((c) => RegExp(r'\d').hasMatch(c)).join();
    if (digitsOnly.length == 10) return '+1$digitsOnly';
    if (digitsOnly.length > 10) return '+$digitsOnly';
    return phoneNumber;
  }

  // ---- Partner invites ----------------------------------------------------

  Future<String> invitePartner(String partnerEmail) async {
    try {
      return await _api.postForString(
          'api/auth/partner/invite', PartnerInviteRequest(partnerEmail: partnerEmail).toJson());
    } catch (_) {
      return 'Error sending invitation';
    }
  }

  Future<PartnerInviteInfo> checkForInvite() async {
    try {
      final json = await _api.getJson('api/auth/partner/check');
      final info = json is Map<String, dynamic> ? PartnerInviteInfo.fromJson(json) : null;
      return info ?? PartnerInviteInfo(valid: false);
    } catch (_) {
      return PartnerInviteInfo(valid: false);
    }
  }

  Future<bool> acceptInvite() async {
    try {
      final json = await _api.postJson('api/auth/partner/accept', <String, dynamic>{});
      return json is Map<String, dynamic> && (json['accepted'] as bool? ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> rejectInvite() async {
    try {
      final json = await _api.postJson('api/auth/partner/reject', <String, dynamic>{});
      return json is Map<String, dynamic> && (json['rejected'] as bool? ?? false);
    } catch (_) {
      return false;
    }
  }

  // ---- User data (export / delete) ---------------------------------------

  Future<Map<String, dynamic>> getUserData([String dataType = 'all']) async {
    try {
      final endpoint =
          'api/auth/user/data?dataType=${Uri.encodeQueryComponent(dataType)}';
      final result = await _api.getJson(endpoint);
      if (result is Map<String, dynamic> && _isTrue(result['success'])) {
        return result;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<bool> deleteUserData(String dataType) async {
    try {
      final endpoint =
          'api/auth/user/data?dataType=${Uri.encodeQueryComponent(dataType)}';
      final result = await _api.deleteJson(endpoint);
      return result is Map<String, dynamic> && _isTrue(result['success']);
    } catch (_) {
      return false;
    }
  }

  // ---- Notification preferences ------------------------------------------

  Future<bool> updateNotificationPreferences(bool enabled) async {
    try {
      final json = await _api.postJson('api/auth/user/notifications',
          NotificationEnabledRequest(enabled: enabled).toJson());
      if (json is Map<String, dynamic>) {
        return NotificationPrefsResponse.fromJson(json).success;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> getNotificationPreferences() async {
    try {
      final json = await _api.getJson('api/auth/user/notifications');
      return json is Map<String, dynamic>
          ? NotificationPrefsResponse.fromJson(json).enabled
          : true;
    } catch (_) {
      return true;
    }
  }

  // ---- Lawyer request management -----------------------------------------

  Future<List<LawyerRequestInfo>> getPendingLawyerRequests() async {
    try {
      final json = await _api.getJson('api/auth/lawyer/check');
      if (json is List) {
        return json
            .map((e) => LawyerRequestInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> acceptLawyerRequest(String lawyerEmail) async {
    try {
      final json = await _api.postJson(
          'api/auth/lawyer/accept', LawyerEmailRequest(lawyerEmail: lawyerEmail).toJson());
      return json is Map<String, dynamic> && (json['accepted'] as bool? ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> rejectLawyerRequest(String lawyerEmail) async {
    try {
      final json = await _api.postJson(
          'api/auth/lawyer/reject', LawyerEmailRequest(lawyerEmail: lawyerEmail).toJson());
      return json is Map<String, dynamic> && (json['rejected'] as bool? ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeLawyer(String lawyerEmail) async {
    try {
      final json = await _api.postJson(
          'api/auth/lawyer/remove', LawyerEmailRequest(lawyerEmail: lawyerEmail).toJson());
      return json is Map<String, dynamic> && (json['removed'] as bool? ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<List<LawyerInfo>> getApprovedLawyers() async {
    try {
      final json = await _api.getJson('api/auth/lawyer/list');
      if (json is List) {
        return json
            .map((e) => LawyerInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ---- Password reset -----------------------------------------------------

  Future<bool> initiatePasswordReset(String email) async {
    try {
      final r = await _api.postJson(
          'api/auth/forgot-password', PasswordResetRequest(email: email).toJson());
      // The server responds `{ sent: true, message }` (always — anti-enumeration),
      // not a bare bool. Treat the object form as success so the reset flow proceeds.
      if (r is bool) return r;
      if (r is Map<String, dynamic>) {
        return r['sent'] == true || r['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyPasswordResetCode(String email, String code) async {
    try {
      final r = await _api.postJson('api/auth/verify-reset-code',
          VerifyResetCodeRequest(email: email, code: code).toJson());
      return r is bool ? r : false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> completePasswordReset(
      String email, String code, String newPassword) async {
    try {
      final r = await _api.postJson(
        'api/auth/reset-password',
        CompletePasswordResetRequest(email: email, code: code, newPassword: newPassword)
            .toJson(),
      );
      return r is bool ? r : false;
    } catch (_) {
      return false;
    }
  }

  // ---- Child account methods ---------------------------------------------

  Future<String> inviteChild(String childEmail) async {
    try {
      return await _api.postForString(
          'api/auth/child/invite', ChildInviteRequest(childEmail: childEmail).toJson());
    } catch (_) {
      return 'Error sending child invitation';
    }
  }

  Future<ChildInviteListResponse> checkChildInvite() async {
    try {
      final json = await _api.getJson('api/auth/child/check');
      final info =
          json is Map<String, dynamic> ? ChildInviteListResponse.fromJson(json) : null;
      return info ?? ChildInviteListResponse(hasInvites: false);
    } catch (_) {
      return ChildInviteListResponse(hasInvites: false);
    }
  }

  Future<bool> acceptChildInvite(String parentEmail) async {
    try {
      final json = await _api.postJson(
          'api/auth/child/accept', ChildInviteActionRequest(parentEmail: parentEmail).toJson());
      return json is Map<String, dynamic> && (json['accepted'] as bool? ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<List<ChildInfo>> getChildren() async {
    try {
      final json = await _api.getJson('api/auth/children');
      if (json is List) {
        return json.map((e) => ChildInfo.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<FamilyInfo?> getFamilyInfo() async {
    try {
      final json = await _api.getJson('api/auth/family');
      return json is Map<String, dynamic> ? FamilyInfo.fromJson(json) : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> declineChildInvite(String parentEmail) async {
    try {
      final json = await _api.postJson(
          'api/auth/child/decline', ChildInviteActionRequest(parentEmail: parentEmail).toJson());
      return json is Map<String, dynamic> && (json['declined'] as bool? ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeChildStatus() async {
    try {
      final json = await _api.postJson('api/auth/child/remove-status', <String, dynamic>{});
      return json is Map<String, dynamic> && (json['success'] as bool? ?? false);
    } catch (_) {
      return false;
    }
  }
}
