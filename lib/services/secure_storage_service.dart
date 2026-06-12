import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Port of `Services/SecureStorageService.cs`.
///
/// Backs onto [FlutterSecureStorage] (Keychain on iOS, EncryptedSharedPreferences
/// on Android) — the equivalent of MAUI's `SecureStorage.Default`. Key names and
/// the integrity-wrap format are preserved so stored values remain readable.
///
/// NOTE: the MAUI "enhanced security" path for bank fields uses device-specific
/// entropy + AES; that is platform-specific and deferred (TODO(phase 3)). As in
/// the C#, it falls back to the regular protected-storage path, so behaviour for
/// every key the auth/foundation layer touches is identical.
class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // Key names — identical to the C# service.
  static const _emailKey = 'secure_email';
  static const _passwordKey = 'secure_password';
  static const _bankAccountKey = 'secure_bank_account';
  static const _bankRoutingKey = 'secure_bank_routing';
  static const _rememberMeKey = 'secure_remember_me';
  static const _saltKey = 'secure_salt_key';
  static const authTokenKey = 'secure_auth_token';
  static const _tokenExpiryKey = 'secure_token_expiry';
  static const _refreshTokenKey = 'secure_refresh_token';
  static const _messagingKeyPrefix = 'secure_messaging_key_';

  static const _secureKeys = <String>{
    _emailKey,
    _passwordKey,
    _bankAccountKey,
    _bankRoutingKey,
    _rememberMeKey,
    _saltKey,
    authTokenKey,
    _tokenExpiryKey,
    _refreshTokenKey,
  };

  final Map<String, String> _encryptionKeyCache = {};

  bool _isSecureKey(String key) => _secureKeys.contains(key);

  // ---- Salt ---------------------------------------------------------------

  Future<Uint8List> _getSecureSalt() async {
    final stored = await _storage.read(key: _saltKey);
    if (stored != null && stored.isNotEmpty) {
      return base64Decode(stored);
    }
    final salt = _randomBytes(32);
    await _storage.write(key: _saltKey, value: base64Encode(salt));
    return salt;
  }

  Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => rng.nextInt(256)));
  }

  // ---- Integrity wrap (matches ProtectSensitiveData / ExtractProtectedData)

  /// Appends a salted SHA-256 verifier: `"<data>|<base64(sha256(data+salt))>"`.
  Future<String> _protect(String data) async {
    final salt = await _getSecureSalt();
    final bytes = utf8.encode(data);
    final salted = Uint8List(bytes.length + salt.length)
      ..setRange(0, bytes.length, bytes)
      ..setRange(bytes.length, bytes.length + salt.length, salt);
    final hash = sha256.convert(salted).bytes;
    return '$data|${base64Encode(hash)}';
  }

  /// Verifies and unwraps a value produced by [_protect].
  Future<String> _extract(String protectedData) async {
    if (protectedData.isEmpty || !protectedData.contains('|')) {
      return protectedData;
    }
    final parts = protectedData.split('|');
    if (parts.length != 2) return protectedData;

    final originalData = parts[0];
    final storedHash = parts[1];
    final salt = await _getSecureSalt();
    final bytes = utf8.encode(originalData);
    final salted = Uint8List(bytes.length + salt.length)
      ..setRange(0, bytes.length, bytes)
      ..setRange(bytes.length, bytes.length + salt.length, salt);
    final computedHash = base64Encode(sha256.convert(salted).bytes);

    if (storedHash != computedHash) {
      // Integrity check failed — possible tampering. Fail closed.
      throw const SecurityException('Data integrity verification failed.');
    }
    return originalData;
  }

  // ---- Core store / retrieve / remove ------------------------------------

  Future<void> secureStore(String key, String value) async {
    if (key.isEmpty || value.isEmpty) return;
    if (_isSecureKey(key)) {
      final protectedValue = await _protect(value);
      await _storage.write(key: key, value: protectedValue);
      await _storage.write(
          key: '${key}_timestamp', value: DateTime.now().toUtc().toIso8601String());
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  Future<String> secureRetrieve(String key, [String fallback = '']) async {
    try {
      final value = await _storage.read(key: key);
      if (value == null || value.isEmpty) return fallback;
      if (_isSecureKey(key)) {
        return await _extract(value);
      }
      return value;
    } on SecurityException {
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> secureRemove(String key) async {
    await _storage.delete(key: key);
    if (_isSecureKey(key)) {
      await _storage.delete(key: '${key}_timestamp');
    }
  }

  /// Clears all secure storage except the salt (matches `SecureClearAll`).
  Future<void> secureClearAll() async {
    final saltValue = await _storage.read(key: _saltKey);
    await _storage.deleteAll();
    if (saltValue != null && saltValue.isNotEmpty) {
      await _storage.write(key: _saltKey, value: saltValue);
    }
  }

  // ---- Credentials --------------------------------------------------------

  Future<void> storeCredentials(String email, String password) async {
    await secureStore(_emailKey, email);
    final verifier = await _generatePasswordVerifier(password);
    await secureStore(_passwordKey, verifier);
  }

  /// Format: `"<iterations>:<base64(salt)>:<base64(pbkdf2-sha256 hash)>"`.
  /// Mirrors `Rfc2898DeriveBytes(password, salt, 10000, SHA256).GetBytes(32)`.
  Future<String> _generatePasswordVerifier(String password) async {
    final salt = await _getSecureSalt();
    final hash = _pbkdf2(utf8.encode(password), salt, 10000, 32);
    return '10000:${base64Encode(salt)}:${base64Encode(hash)}';
  }

  Future<String> getSecureEmail() => secureRetrieve(_emailKey, '');
  Future<String> getSecurePassword() => secureRetrieve(_passwordKey, '');

  // ---- Per-conversation message encryption keys (order-sensitive) --------

  Future<String> getMessageEncryptionKey(String user1, String user2) async {
    if (user1.isEmpty || user2.isEmpty) return '';
    final keyId = '$user1:$user2';
    final cached = _encryptionKeyCache[keyId];
    if (cached != null) return cached;

    final key = await secureRetrieve('$_messagingKeyPrefix$keyId', '');
    if (key.isEmpty) return '';
    _encryptionKeyCache[keyId] = key;
    return key;
  }

  Future<bool> storeMessageEncryptionKey(
      String user1, String user2, String encryptionKey) async {
    if (user1.isEmpty || user2.isEmpty || encryptionKey.isEmpty) return false;
    final keyId = '$user1:$user2';
    await secureStore('$_messagingKeyPrefix$keyId', encryptionKey);
    _encryptionKeyCache[keyId] = encryptionKey;
    return true;
  }

  /// Removes every per-conversation message encryption key — all stored
  /// `secure_messaging_key_*` entries plus the in-memory cache. Called on
  /// logout so a later sign-in (possibly a different account) cannot read the
  /// previous user's conversation keys. Safe to clear: conversation keys are
  /// server-issued and re-fetched on demand after the next sign-in. Touches
  /// ONLY messaging keys — credentials, tokens, and the salt are untouched.
  Future<void> clearMessageEncryptionKeys() async {
    _encryptionKeyCache.clear();
    try {
      final all = await _storage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_messagingKeyPrefix)) {
          await _storage.delete(key: key);
        }
      }
    } catch (_) {
      // Best-effort: the in-memory cache is already cleared.
    }
  }
}

/// PBKDF2-HMAC-SHA256, equivalent to .NET `Rfc2898DeriveBytes` with SHA256.
Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations, int keyLen) {
  final hmac = Hmac(sha256, password);
  const hLen = 32; // SHA-256 output
  final blockCount = (keyLen + hLen - 1) ~/ hLen;
  final output = BytesBuilder();

  for (var block = 1; block <= blockCount; block++) {
    // INT_32_BE(block)
    final blockIndex = Uint8List(4)
      ..[0] = (block >> 24) & 0xff
      ..[1] = (block >> 16) & 0xff
      ..[2] = (block >> 8) & 0xff
      ..[3] = block & 0xff;

    var u = hmac.convert([...salt, ...blockIndex]).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    output.add(t);
  }
  return output.toBytes().sublist(0, keyLen);
}

/// Raised when stored data fails its integrity check (analogue of .NET
/// `SecurityException` use in `SecureStorageService`).
class SecurityException implements Exception {
  const SecurityException(this.message);
  final String message;
  @override
  String toString() => 'SecurityException: $message';
}
