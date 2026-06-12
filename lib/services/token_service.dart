import '../models/auth_models.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

/// Outcome of a [TokenService.refreshToken] attempt. Distinguishes an explicit
/// server rejection (session dead — tokens wiped) from a transport failure
/// (offline/timeout/5xx — tokens kept so a later attempt can retry).
enum RefreshOutcome {
  /// A new token was issued and stored.
  refreshed,

  /// The server explicitly rejected the refresh token — stored tokens have
  /// been wiped; the session is definitively dead.
  rejected,

  /// No refresh token is stored — there is no session to refresh.
  noSession,

  /// Couldn't reach the server (offline/timeout) or it errored (5xx) — stored
  /// tokens are KEPT; callers should treat this as retryable, not as logout.
  transient,
}

/// Port of `Services/TokenService.cs`. Stores/retrieves/refreshes auth tokens
/// using the same secure-storage keys as the MAUI app.
class TokenService {
  TokenService(this._secureStorage);

  final SecureStorageService _secureStorage;

  static const _authTokenKey = 'secure_auth_token';
  static const _refreshTokenKey = 'secure_refresh_token';
  static const _tokenExpiryKey = 'secure_token_expiry';

  Future<String> getToken() => _secureStorage.secureRetrieve(_authTokenKey);

  Future<void> setToken(String token, DateTime expiry,
      [String? refreshToken]) async {
    await _secureStorage.secureStore(_authTokenKey, token);
    // DateTime "o" round-trip format == ISO-8601 with offset; toIso8601String matches.
    await _secureStorage.secureStore(_tokenExpiryKey, expiry.toIso8601String());
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _secureStorage.secureStore(_refreshTokenKey, refreshToken);
    }
  }

  Future<String> getRefreshToken() =>
      _secureStorage.secureRetrieve(_refreshTokenKey);

  Future<DateTime?> getTokenExpiry() async {
    final expiryStr = await _secureStorage.secureRetrieve(_tokenExpiryKey);
    return expiryStr.isEmpty ? null : DateTime.tryParse(expiryStr);
  }

  Future<void> removeToken() async {
    await _secureStorage.secureRemove(_authTokenKey);
    await _secureStorage.secureRemove(_refreshTokenKey);
    await _secureStorage.secureRemove(_tokenExpiryKey);
  }

  /// Attempts to refresh the token using the stored refresh token. Uses
  /// [ApiClient.postWithoutRetry] to avoid recursive 401 retry storms.
  ///
  /// Stored tokens are only wiped when the server EXPLICITLY rejects the
  /// refresh token (400/401/403). A transport failure (offline cold start,
  /// flaky network, server 5xx) returns [RefreshOutcome.transient] and keeps
  /// the tokens, so a later attempt can succeed — it must not log the user out.
  Future<({RefreshOutcome outcome, String? token})> refreshToken(
      ApiClient apiService) async {
    final refreshToken = await getRefreshToken();
    if (refreshToken.isEmpty) {
      return (outcome: RefreshOutcome.noSession, token: null);
    }
    try {
      final result = await apiService.postWithoutRetry(
          'api/auth/refresh-token', RefreshTokenRequest(refreshToken: refreshToken).toJson());
      if (result.status >= 200 && result.status < 300) {
        final json = result.body;
        if (json is Map<String, dynamic>) {
          final response = RefreshTokenResponse.fromJson(json);
          if (response.token != null && response.token!.isNotEmpty) {
            await setToken(
              response.token!,
              DateTime.now().toUtc().add(Duration(minutes: response.expiresInMinutes)),
              response.refreshToken,
            );
            return (outcome: RefreshOutcome.refreshed, token: response.token);
          }
        }
        // 2xx but no usable token — the server answered and issued nothing.
        await removeToken();
        return (outcome: RefreshOutcome.rejected, token: null);
      }
      if (result.status == 400 || result.status == 401 || result.status == 403) {
        // Explicit rejection — clear stored tokens to prevent further attempts.
        await removeToken();
        return (outcome: RefreshOutcome.rejected, token: null);
      }
    } catch (_) {
      // fall through to the transient outcome
    }
    // Transport failure (status 0) or server error (5xx) — keep the tokens.
    return (outcome: RefreshOutcome.transient, token: null);
  }
}
