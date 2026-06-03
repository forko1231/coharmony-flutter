// DTOs + event payloads for the messaging domain. 1:1 with `MessagingService.cs`
// and `WebSocketService.cs`.
//
// CASING IS MIXED on purpose (matches the C# [JsonPropertyName] attributes):
//  - MessageContentResponse / WebhookSubscriptionResponse -> PascalCase keys
//  - MarkAsRead / UnreadCount / Attachment / DeleteWebhook -> camelCase keys
//  - MessageResponse -> lowercase keys (status/tonescore/suggested/messageId)
//  - WebSocket messages -> camelCase keys
//  - request types -> camelCase keys

/// Parses a server timestamp as UTC and converts to local (mirrors
/// `DateTime.SpecifyKind(..., Utc).ToLocalTime()`).
DateTime _utcToLocal(dynamic v) {
  final parsed = DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
  final utc = parsed.isUtc
      ? parsed
      : DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
          parsed.minute, parsed.second, parsed.millisecond);
  return utc.toLocal();
}

DateTime? _utcToLocalOrNull(dynamic v) => v == null ? null : _utcToLocal(v);

// ---- Message content -----------------------------------------------------

class MessageContent {
  MessageContent({
    this.messageId = 0,
    this.sender = '',
    this.receiver = '',
    this.message = '',
    this.attachment,
    required this.timestamp,
    this.isRead = false,
    this.readAt,
  });
  final int messageId;
  final String sender;
  final String receiver;
  final String message;
  final String? attachment;
  final DateTime timestamp;
  final bool isRead;
  final DateTime? readAt;

  /// From the AOT response type (PascalCase keys); converts UTC -> local.
  factory MessageContent.fromJson(Map<String, dynamic> j) => MessageContent(
        messageId: (j['MessageId'] as num?)?.toInt() ?? 0,
        sender: j['Sender'] as String? ?? '',
        receiver: j['Receiver'] as String? ?? '',
        message: j['Message'] as String? ?? '',
        attachment: j['Attachment'] as String?,
        timestamp: _utcToLocal(j['Timestamp']),
        isRead: j['IsRead'] as bool? ?? false,
        readAt: _utcToLocalOrNull(j['ReadAt']),
      );
}

class AttachmentModel {
  AttachmentModel({this.fileName = '', this.encryptedData = ''});
  final String fileName;
  final String encryptedData;
  factory AttachmentModel.fromJson(Map<String, dynamic> j) => AttachmentModel(
        fileName: j['fileName'] as String? ?? '',
        encryptedData: j['encryptedData'] as String? ?? '',
      );
}

class WebhookSubscription {
  WebhookSubscription({
    this.id = 0,
    this.userEmail = '',
    this.callbackUrl = '',
    this.eventTypes = '',
    this.isActive = false,
    this.createdAt,
    this.lastUsedAt,
  });
  final int id;
  final String userEmail;
  final String callbackUrl;
  final String eventTypes;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  /// PascalCase keys (WebhookSubscriptionResponse).
  factory WebhookSubscription.fromJson(Map<String, dynamic> j) => WebhookSubscription(
        id: (j['Id'] as num?)?.toInt() ?? 0,
        userEmail: j['UserEmail'] as String? ?? '',
        callbackUrl: j['CallbackUrl'] as String? ?? '',
        eventTypes: j['EventTypes'] as String? ?? '',
        isActive: j['IsActive'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['CreatedAt']?.toString() ?? ''),
        lastUsedAt: DateTime.tryParse(j['LastUsedAt']?.toString() ?? ''),
      );
}

class MessageResponse {
  MessageResponse({this.status, this.tonescore, this.suggested, this.messageId = 0});
  final String? status;
  final int? tonescore;
  final String? suggested;
  final int messageId;
  factory MessageResponse.fromJson(Map<String, dynamic> j) => MessageResponse(
        status: j['status'] as String?,
        tonescore: (j['tonescore'] as num?)?.toInt(),
        suggested: j['suggested'] as String?,
        messageId: (j['messageId'] as num?)?.toInt() ?? 0,
      );
}

// ---- Requests ------------------------------------------------------------

class SendMessageRequest {
  SendMessageRequest({
    required this.recipientEmail,
    required this.message,
    this.attachment,
    this.isToneCheck = false,
  });
  final String recipientEmail;
  final String message;
  final String? attachment;
  final bool isToneCheck;
  Map<String, dynamic> toJson() {
    final m = {
      'recipientEmail': recipientEmail,
      'message': message,
      'attachment': attachment,
      'isToneCheck': isToneCheck,
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }
}

class CreateWebhookRequest {
  CreateWebhookRequest({
    required this.callbackUrl,
    required this.secret,
    this.eventTypes = 'new_message',
  });
  final String callbackUrl;
  final String secret;
  final String eventTypes;
  Map<String, dynamic> toJson() =>
      {'callbackUrl': callbackUrl, 'secret': secret, 'eventTypes': eventTypes};
}

// ---- WebSocket message types (camelCase) --------------------------------

class WebSocketMessage {
  WebSocketMessage({required this.type, this.timestamp, this.data});
  final String type;
  final DateTime? timestamp;
  final WebSocketMessageData? data;

  factory WebSocketMessage.fromJson(Map<String, dynamic> j) => WebSocketMessage(
        type: j['type'] as String? ?? '',
        timestamp: DateTime.tryParse(j['timestamp']?.toString() ?? ''),
        data: j['data'] is Map<String, dynamic>
            ? WebSocketMessageData.fromJson(j['data'] as Map<String, dynamic>)
            : null,
      );
}

class WebSocketMessageData {
  WebSocketMessageData({
    this.messageId = 0,
    this.sender,
    this.receiver,
    this.message,
    this.timestamp,
    this.attachment,
    this.readerEmail,
    this.senderEmail,
    this.readAt,
  });
  final int messageId;
  final String? sender;
  final String? receiver;
  final String? message;
  final DateTime? timestamp;
  final String? attachment;
  final String? readerEmail;
  final String? senderEmail;
  final DateTime? readAt;

  factory WebSocketMessageData.fromJson(Map<String, dynamic> j) => WebSocketMessageData(
        messageId: (j['messageId'] as num?)?.toInt() ?? 0,
        sender: j['sender'] as String?,
        receiver: j['receiver'] as String?,
        message: j['message'] as String?,
        timestamp: DateTime.tryParse(j['timestamp']?.toString() ?? ''),
        attachment: j['attachment'] as String?,
        readerEmail: j['readerEmail'] as String?,
        senderEmail: j['senderEmail'] as String?,
        readAt: DateTime.tryParse(j['readAt']?.toString() ?? ''),
      );
}

// ---- Event payloads (Dart Streams replace C# events) --------------------

class MessageReceivedEvent {
  MessageReceivedEvent({
    required this.messageId,
    required this.sender,
    required this.receiver,
    required this.message,
    this.attachment,
    required this.timestamp,
  });
  final int messageId;
  final String sender;
  final String receiver;
  final String message;
  final String? attachment;
  final DateTime timestamp;
}

class MessagesReadEvent {
  MessagesReadEvent(this.readerEmail, this.senderEmail, this.readAt);
  final String readerEmail;
  final String senderEmail;
  final DateTime readAt;
}

class PartnerTypingEvent {
  PartnerTypingEvent(this.senderEmail);
  final String senderEmail;
}
