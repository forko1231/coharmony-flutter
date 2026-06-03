import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../services/messaging_service.dart';

/// Faithful port of `Security/MessageEncryptionService.cs`.
///
/// Messages travel as AES-256-GCM ciphertext. This is NOT end-to-end: the
/// per-conversation base key is fetched FROM the server
/// ([MessagingService.getConversationEncryptionKey]) and cached for 15 minutes,
/// so the server holds the keys. The wire format matches the C# implementation
/// byte-for-byte:
///
///   base64( NONCE[12] + TAG[16] + CIPHERTEXT )
///
/// The cache key is normalized (alphabetical) so both directions of a
/// conversation resolve to the same entry.
class MessageEncryptionService {
  MessageEncryptionService(this._messaging);

  final MessagingService _messaging;

  static const int _nonceSize = 12; // 96-bit nonce (recommended for GCM)
  static const int _tagSize = 16; // 128-bit auth tag

  final AesGcm _algorithm = AesGcm.with256bits();

  // Conversation-level base-key cache (key -> (base64Key, expiry)).
  final Map<String, ({String key, DateTime expires})> _keyCache = {};
  static const Duration _keyCacheDuration = Duration(minutes: 15);

  /// Encrypts [message] for the sender→receiver conversation. Returns
  /// `base64(NONCE+TAG+CIPHERTEXT)`, or '' for an empty input.
  Future<String> encryptMessage(String message, String senderEmail, String receiverEmail) async {
    if (message.isEmpty) return '';
    final base64Key = await _getEncryptionKey(receiverEmail, senderEmail);
    final keyBytes = base64Decode(base64Key);
    if (keyBytes.length != 32) {
      throw StateError('Invalid key size: ${keyBytes.length} bytes, expected 32');
    }
    final secretKey = SecretKey(keyBytes);
    final nonce = _algorithm.newNonce(); // 12 bytes
    final box = await _algorithm.encrypt(
      utf8.encode(message),
      secretKey: secretKey,
      nonce: nonce,
    );
    final tag = box.mac.bytes; // 16 bytes
    final cipher = box.cipherText;
    final result = Uint8List(_nonceSize + _tagSize + cipher.length)
      ..setRange(0, _nonceSize, nonce)
      ..setRange(_nonceSize, _nonceSize + _tagSize, tag)
      ..setRange(_nonceSize + _tagSize, _nonceSize + _tagSize + cipher.length, cipher);
    return base64Encode(result);
  }

  /// Decrypts a `base64(NONCE+TAG+CIPHERTEXT)` payload. Returns the plaintext,
  /// '' for empty input, or '[Encrypted message]' if decryption/auth fails
  /// (mirrors the C# fallback).
  Future<String> decryptMessage(String encryptedMessage, String senderEmail, String receiverEmail) async {
    if (encryptedMessage.isEmpty) return '';
    try {
      final data = base64Decode(encryptedMessage);
      if (data.length < _nonceSize + _tagSize + 1) {
        throw const FormatException('Invalid encrypted message format');
      }
      final base64Key = await _getEncryptionKey(receiverEmail, senderEmail);
      final keyBytes = base64Decode(base64Key);
      if (keyBytes.length != 32) {
        throw StateError('Invalid key size: ${keyBytes.length} bytes, expected 32');
      }
      final nonce = data.sublist(0, _nonceSize);
      final tag = data.sublist(_nonceSize, _nonceSize + _tagSize);
      final cipher = data.sublist(_nonceSize + _tagSize);
      final clear = await _algorithm.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
        secretKey: SecretKey(keyBytes),
      );
      return utf8.decode(clear);
    } catch (_) {
      // Authentication failed or invalid ciphertext.
      return '[Encrypted message]';
    }
  }

  /// Attachments use the same AES-GCM scheme as messages.
  Future<String> encryptAttachment(String data, String senderEmail, String receiverEmail) =>
      encryptMessage(data, senderEmail, receiverEmail);

  Future<String> decryptAttachment(String data, String senderEmail, String receiverEmail) =>
      decryptMessage(data, senderEmail, receiverEmail);

  /// Fetches (and caches, 15 min) the conversation base key. The cache key is
  /// normalized alphabetically so both directions share one entry.
  Future<String> _getEncryptionKey(String recipientEmail, String senderEmail) async {
    final cacheKey = senderEmail.compareTo(recipientEmail) < 0
        ? '$senderEmail:$recipientEmail'
        : '$recipientEmail:$senderEmail';

    final cached = _keyCache[cacheKey];
    if (cached != null && cached.expires.isAfter(DateTime.now().toUtc())) {
      return cached.key;
    }

    final key = await _messaging.getConversationEncryptionKey(recipientEmail, senderEmail: senderEmail);
    _keyCache[cacheKey] = (key: key, expires: DateTime.now().toUtc().add(_keyCacheDuration));

    // Periodic cleanup of expired entries.
    if (_keyCache.length > 50) {
      final now = DateTime.now().toUtc();
      _keyCache.removeWhere((_, v) => v.expires.isBefore(now));
    }
    return key;
  }

  void clearKeyCache() => _keyCache.clear();
}
