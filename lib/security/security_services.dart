import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../services/preferences.dart';
import '../services/secure_storage_service.dart';

/// Port of `Security/KeyManagementService.cs`.
///
/// Manages cryptographic key material for secure communications: a 30-day
/// rotation of the device entropy value + a stable secure device id. Values are
/// stored via [SecureStorageService] under plain (non-integrity-wrapped) keys —
/// the same keys MAUI used with `SecureStorage.Default` (`KeyRotationDate`,
/// `SecureDeviceId`), so behaviour matches.
class KeyManagementService {
  KeyManagementService(this._storage);
  final SecureStorageService _storage;

  static const _rotationDateKey = 'KeyRotationDate';
  static const _secureDeviceIdKey = 'SecureDeviceId';
  static const _rotationDays = 30; // Rotate keys every 30 days

  bool _initialized = false;

  /// Initializes the service and rotates keys if due. Runs detached (mirrors the
  /// C# `Task.Run`) so it never blocks startup; failures are swallowed.
  void initialize() {
    if (_initialized) return;
    () async {
      try {
        if (await _shouldRotateKeys()) {
          await _rotateKeys();
        }
        _initialized = true;
      } catch (_) {/* non-fatal — continue with existing keys */}
    }();
  }

  Future<bool> _shouldRotateKeys() async {
    try {
      final last = await _storage.secureRetrieve(_rotationDateKey, '');
      if (last.isEmpty) return true; // first-time setup
      final lastDate = DateTime.tryParse(last);
      if (lastDate != null) {
        return DateTime.now().toUtc().isAfter(
            lastDate.toUtc().add(const Duration(days: _rotationDays)));
      }
      return true; // unparseable → rotate
    } catch (_) {
      return true; // error → rotate
    }
  }

  Future<void> _rotateKeys() async {
    try {
      // New device entropy from a cryptographically secure RNG.
      final entropy = base64Encode(_randomBytes(32));
      await _storage.secureStore(_secureDeviceIdKey, entropy);
      await _storage.secureStore(
          _rotationDateKey, DateTime.now().toUtc().toIso8601String());
    } catch (_) {/* non-fatal — keep existing keys */}
  }

  /// Forces an immediate key rotation.
  Future<void> forceKeyRotation() => _rotateKeys();

  List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// Returns the secure device id (entropy), generating + storing one if absent.
  Future<String> getSecureDeviceId() async {
    try {
      var id = await _storage.secureRetrieve(_secureDeviceIdKey, '');
      if (id.isEmpty) {
        id = base64Encode(_randomBytes(32));
        await _storage.secureStore(_secureDeviceIdKey, id);
      }
      return id;
    } catch (_) {
      // Fallback: a temporary id (prevents crashes; less durable).
      return base64Encode(_randomBytes(32));
    }
  }
}

/// Port of `Security/SecurityAuditService.cs`.
///
/// Weekly self-audit of the crypto environment (AES-GCM availability, secure
/// RNG, device integrity, TLS). The audit timestamp lives in [Preferences]
/// (`LastSecurityAudit`), as in MAUI.
class SecurityAuditService {
  static const _lastAuditKey = 'LastSecurityAudit';
  static const _auditIntervalDays = 7; // Weekly audits

  /// Whether an audit is due (first run, or >7 days since the last).
  bool shouldPerformAudit() {
    final last = Preferences.getString(_lastAuditKey, '');
    if (last.isEmpty) return true; // first run
    final lastDate = DateTime.tryParse(last);
    if (lastDate != null) {
      return DateTime.now().toUtc().isAfter(
          lastDate.toUtc().add(const Duration(days: _auditIntervalDays)));
    }
    return true; // unparseable → audit
  }

  /// Runs the audit and returns whether the environment passes all checks.
  Future<bool> performSecurityAudit() async {
    try {
      // Record audit time.
      await Preferences.setString(
          _lastAuditKey, DateTime.now().toUtc().toIso8601String());

      final aesGcmSupported = await _isAesGcmSupported();
      final secureRandomSupported = _isSecureRandomSupported();
      final deviceIntegrityOk = _verifyDeviceIntegrity();
      final tlsVersionOk = _isTls13Supported();

      return aesGcmSupported &&
          secureRandomSupported &&
          deviceIntegrityOk &&
          tlsVersionOk;
    } catch (_) {
      // Default to assuming the environment is secure if checks can't run.
      return true;
    }
  }

  Future<bool> _isAesGcmSupported() async {
    try {
      final algo = AesGcm.with256bits();
      await algo.newSecretKey();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isSecureRandomSupported() {
    try {
      final rng = Random.secure();
      final buffer = List<int>.generate(32, (_) => rng.nextInt(256));
      // All-zero would be astronomically unlikely with a proper RNG.
      return buffer.any((b) => b != 0);
    } catch (_) {
      return false;
    }
  }

  bool _verifyDeviceIntegrity() {
    // Simplistic root/jailbreak heuristic (matches the MAUI checks).
    try {
      if (Platform.isAndroid) {
        return !File('/system/app/Superuser.apk').existsSync() &&
            !File('/system/xbin/su').existsSync() &&
            !File('/system/bin/su').existsSync();
      }
      if (Platform.isIOS) {
        return !File('/Applications/Cydia.app').existsSync() &&
            !File('/Library/MobileSubstrate/MobileSubstrate.dylib').existsSync();
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  bool _isTls13Supported() {
    // Dart's HttpClient negotiates TLS 1.3 wherever the host OS supports it
    // (the BoringSSL-backed SecureSocket); there is no runtime feature flag to
    // probe, so this mirrors the MAUI "Tls13.HasFlag(Tls13)" tautology.
    return true;
  }
}
