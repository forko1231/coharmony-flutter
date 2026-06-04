import 'dart:async';

import '../models/message_models.dart';
import 'api_client.dart';
import 'websocket_service.dart';

/// Port of `Services/MessagingService.cs`. HTTP message operations plus the
/// real-time WebSocket layer. The C# `MessageReceived` / `MessagesRead` /
/// `PartnerTyping` events are exposed here as broadcast [Stream]s.
///
/// NOTE: message text is sent/received as plaintext through the API — the
/// SERVER (`MessageEncryptionService.cs`) handles encryption at rest, so there
/// is no client-side message E2E to reproduce here.
class MessagingService {
  MessagingService(this._api, this._ws) {
    _wsSub = _ws.messages.listen(_onWsMessage);
  }

  final ApiClient _api;
  final WebSocketService _ws;
  StreamSubscription<WebSocketMessage>? _wsSub;
  bool _isWebSocketInitialized = false;

  final _messageReceived = StreamController<MessageReceivedEvent>.broadcast();
  final _messagesRead = StreamController<MessagesReadEvent>.broadcast();
  final _partnerTyping = StreamController<PartnerTypingEvent>.broadcast();

  Stream<MessageReceivedEvent> get onMessageReceived => _messageReceived.stream;
  Stream<MessagesReadEvent> get onMessagesRead => _messagesRead.stream;
  Stream<PartnerTypingEvent> get onPartnerTyping => _partnerTyping.stream;

  bool get isWebSocketInitialized => _isWebSocketInitialized;
  bool get isWebSocketConnected => _ws.isConnected;

  // ---- WebSocket lifecycle ------------------------------------------------

  Future<bool> initializeWebSocket() async {
    if (_isWebSocketInitialized && _ws.isConnected) return true;
    final connected = await _ws.connect();
    _isWebSocketInitialized = connected;
    return connected;
  }

  Future<void> closeWebSocket() async {
    if (_isWebSocketInitialized) {
      await _ws.disconnect(reconnect: false);
      _isWebSocketInitialized = false;
    }
  }

  Future<void> sendTypingNotification(String receiverEmail) async {
    if (_isWebSocketInitialized && _ws.isConnected) {
      await _ws.sendTyping(receiverEmail);
    }
  }

  void _onWsMessage(WebSocketMessage m) {
    switch (m.type) {
      case 'typing':
        _partnerTyping.add(PartnerTypingEvent(m.data?.sender ?? ''));
        break;
      case 'messages_read':
        final raw = m.data?.readAt ?? m.timestamp ?? DateTime.now();
        _messagesRead.add(MessagesReadEvent(
          m.data?.readerEmail ?? '',
          m.data?.senderEmail ?? '',
          _asUtcToLocal(raw),
        ));
        break;
      case 'new_message':
        final d = m.data;
        if (d == null) return;
        _messageReceived.add(MessageReceivedEvent(
          messageId: d.messageId,
          sender: d.sender ?? '',
          receiver: d.receiver ?? '',
          message: d.message ?? '',
          attachment: d.attachment,
          timestamp: d.timestamp ?? DateTime.now(),
        ));
        break;
    }
  }

  // ---- HTTP operations ----------------------------------------------------

  Future<MessageResponse> sendMessage(String receiverEmail, String messageText,
      {String? attachmentBase64, bool isToneCheck = false}) async {
    final json = await _api.postJson(
      'api/messages/send',
      SendMessageRequest(
        recipientEmail: receiverEmail,
        message: messageText,
        attachment: attachmentBase64,
        isToneCheck: isToneCheck,
      ).toJson(),
    );
    return json is Map<String, dynamic> ? MessageResponse.fromJson(json) : MessageResponse();
  }

  Future<List<MessageContent>> getMessages({int page = 1, int pageSize = 50}) async {
    final json = await _api.getJson('/api/messages?page=$page&pageSize=$pageSize');
    return _parseMessages(json);
  }

  Future<List<MessageContent>> getContactMessages(String contactEmail,
      {int page = 1, int pageSize = 50}) async {
    final json = await _api.getJson(
        '/api/messages/contact/${Uri.encodeComponent(contactEmail)}?page=$page&pageSize=$pageSize');
    return _parseMessages(json);
  }

  Future<List<MessageContent>> getLatestMessagesPerContact({int maxContacts = 50}) async {
    final json = await _api.getJson('/api/messages/latest?maxContacts=$maxContacts');
    return _parseMessages(json);
  }

  /// Fetches one attachment's payload (client decrypts). [index] selects which
  /// file when a message carries several (server defaults to 0).
  Future<AttachmentModel?> getAttachment(int messageId, {int index = 0}) async {
    final json = await _api.getJson('api/messages/attachment/$messageId?index=$index');
    return json is Map<String, dynamic> ? AttachmentModel.fromJson(json) : null;
  }

  Future<int> markMessagesAsRead(String contactEmail) async {
    final json = await _api.postJson(
        'api/messages/read/${Uri.encodeComponent(contactEmail)}', <String, dynamic>{});
    if (json is Map<String, dynamic>) {
      return (json['markedAsRead'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<int> getUnreadCount() async {
    final json = await _api.getJson('api/messages/unread/count');
    if (json is Map<String, dynamic>) {
      return (json['unreadCount'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<String> getConversationEncryptionKey(String receiverEmail,
      {String? senderEmail}) async {
    var endpoint = 'api/messages/key?receiverEmail=${Uri.encodeQueryComponent(receiverEmail)}';
    if (senderEmail != null && senderEmail.isNotEmpty) {
      endpoint += '&senderEmail=${Uri.encodeQueryComponent(senderEmail)}';
    }
    final json = await _api.getJson(endpoint);
    if (json is Map<String, dynamic> && json['key'] is String) {
      return json['key'] as String;
    }
    return '';
  }

  // ---- Webhooks -----------------------------------------------------------

  Future<WebhookSubscription?> createWebhook(String callbackUrl, String secret,
      {String eventTypes = 'new_message'}) async {
    final json = await _api.postJson(
      'api/messages/webhooks',
      CreateWebhookRequest(callbackUrl: callbackUrl, secret: secret, eventTypes: eventTypes)
          .toJson(),
    );
    return json is Map<String, dynamic> ? WebhookSubscription.fromJson(json) : null;
  }

  Future<List<WebhookSubscription>> getWebhooks() async {
    final json = await _api.getJson('api/messages/webhooks');
    if (json is List) {
      return json
          .map((e) => WebhookSubscription.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<bool> deleteWebhook(int webhookId) async {
    final json = await _api.deleteJson('api/messages/webhooks/$webhookId');
    return json is Map<String, dynamic> && (json['success'] as bool? ?? false);
  }

  void dispose() {
    _wsSub?.cancel();
    _messageReceived.close();
    _messagesRead.close();
    _partnerTyping.close();
  }

  List<MessageContent> _parseMessages(dynamic json) {
    if (json is List) {
      return json
          .map((e) => MessageContent.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Reinterpret a DateTime as UTC and convert to local (mirrors the C#
  /// `DateTime.SpecifyKind(..., Utc).ToLocalTime()` on the read receipt).
  static DateTime _asUtcToLocal(DateTime dt) {
    final utc = dt.isUtc
        ? dt
        : DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second,
            dt.millisecond);
    return utc.toLocal();
  }
}
