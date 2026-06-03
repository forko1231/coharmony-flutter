import '../models/auth_models.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

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

  /// Attempts to refresh the token using the stored refresh token. Returns the
  /// new token or null. Uses [ApiClient.postWithoutRetry] to avoid recursive
  /// 401 retry storms.
  Future<String?> refreshToken(ApiClient apiService) async {
    final refreshToken = await getRefreshToken();
    if (refreshToken.isEmpty) return null;
    try {
      final json = await apiService.postWithoutRetry(
          'api/auth/refresh-token', RefreshTokenRequest(refreshToken: refreshToken).toJson());
      if (json is Map<String, dynamic>) {
        final response = RefreshTokenResponse.fromJson(json);
        if (response.token != null && response.token!.isNotEmpty) {
          await setToken(
            response.token!,
            DateTime.now().toUtc().add(Duration(minutes: response.expiresInMinutes)),
            response.refreshToken,
          );
          return response.token;
        }
      }
    } catch (_) {
      // fall through to clearing
    }
    // Refresh failed — clear stored tokens to prevent further retry attempts.
    await removeToken();
    return null;
  }
}
