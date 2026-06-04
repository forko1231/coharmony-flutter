import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/message_models.dart';
import '../../services/app_navigation.dart';
import '../filevault/file_vault_page.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';

/// Encrypted chat thread — faithful port of `Views/Messaging/ChatInterface.xaml(.cs)`.
///
/// On open it marks the contact's messages read and loads the conversation
/// (HTTP, paginated) — those rows are AES-GCM ciphertext, so each is decrypted
/// via [MessageEncryptionService]. Sending encrypts the text first. Live updates
/// arrive on the messaging streams: `onMessageReceived` payloads are already
/// plaintext (the server decrypts before pushing — NOT decrypted again),
/// `onMessagesRead` drives the Delivered→Read status, and `onPartnerTyping` shows
/// the typing bubble. Typing notifications are throttled to once per 3s. A
/// `bad_tone` send response surfaces the AI's suggested revision.
///
/// Attachments: the compose paperclip picks a photo/file → base64 → AES-GCM
/// `encryptAttachment` → sent as a `{FileName, EncryptedData}` transport. Received
/// attachments render as a tappable chip → View / Save to Files / Save to Camera
/// Roll / Save to Vault (download → `decryptAttachment` → bytes).
class ChatInterfacePage extends StatefulWidget {
  final String contactEmail; // may be the "partner" sentinel
  final String contactName;
  final String? draftMessage;
  const ChatInterfacePage({
    super.key,
    required this.contactEmail,
    required this.contactName,
    this.draftMessage,
  });

  @override
  State<ChatInterfacePage> createState() => _ChatInterfacePageState();
}

class _Msg {
  _Msg({
    required this.messageId,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.receiver = '',
    this.attachment,
    this.isRead = false,
    this.readAt,
    this.sending = false,
  });
  // Mutable so an optimistic message can be reconciled in place once the server
  // confirms it (temp id → real id, placeholder → real attachment payload).
  int messageId;
  final String sender;
  final String receiver;
  String text;
  final DateTime timestamp;
  /// Raw AttachmentMetadata/Transport JSON (FileName + EncryptedData) or null.
  String? attachment;
  bool isRead;
  DateTime? readAt;

  /// True while the message has been shown optimistically but not yet confirmed
  /// sent by the server. Drives the "Sending…" status line.
  bool sending;

  bool get hasAttachment => attachment != null && attachment!.trim().isNotEmpty;
}

class _ChatInterfacePageState extends State<ChatInterfacePage> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  final List<_Msg> _messages = [];
  final Set<int> _displayedIds = {};

  // Temporary (negative) ids for optimistic messages, before the server assigns
  // the real one — kept distinct from real ids so reconciliation can't collide.
  int _nextTempId = -1;

  // Decrypted attachment bytes cached by "messageId:index" for the lifetime of
  // the open thread, so re-tapping an attachment doesn't refetch + redecrypt.
  final Map<String, List<int>> _attachmentBytesCache = {};

  late final String _me;
  late final String _recipient;

  bool _loading = true;
  bool _sending = false;
  // Pending attachments selected for the next outgoing message (now multiple).
  // `bytes` is decoded ONCE at pick time and reused as a stable image provider
  // for the compose preview (re-decoding base64 every build made thumbnails
  // flicker / blank on first frame).
  final List<({String base64, String fileName, Uint8List bytes})> _pendingAttachments = [];
  int _page = 1;
  static const _pageSize = 20;
  bool _hasMore = true;
  bool _loadingOlder = false;

  String? _deliveryStatus; // shown under the last outgoing message
  bool _partnerTyping = false;
  Timer? _typingHideTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  static const _typingThrottle = Duration(seconds: 3);

  String? _suggestion; // AI tone-check suggested revision
  int? _toneScore; // AI tone score (0–10) accompanying a suggested revision

  StreamSubscription<MessageReceivedEvent>? _recvSub;
  StreamSubscription<MessagesReadEvent>? _readSub;
  StreamSubscription<PartnerTypingEvent>? _typingSub;

  @override
  void initState() {
    super.initState();
    AppNavigation.inChat = true; // suppress message banners while chatting
    _me = Preferences.getString('email');
    _recipient = widget.contactEmail == 'partner'
        ? Preferences.getString('partnerEmail')
        : widget.contactEmail;
    if (widget.draftMessage?.isNotEmpty ?? false) _controller.text = widget.draftMessage!;
    _controller.addListener(_onTextChanged);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeMetrics() {
    // When the keyboard opens (or its height changes), keep the latest messages
    // visible by scrolling to the bottom as the list shrinks above the keyboard.
    final inset = WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;
    if (inset > 0) _scrollToBottom();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The socket may have dropped while backgrounded (and reconnect attempts can
    // exhaust). On resume, re-establish it and pull anything that arrived offline.
    if (state == AppLifecycleState.resumed) _resync();
  }

  Future<void> _resync() async {
    await ServiceLocator.messaging.initializeWebSocket();
    if (!mounted) return;
    unawaited(ServiceLocator.messaging.markMessagesAsRead(_recipient).catchError((_) => 0));
    await _mergeLatest();
  }

  /// Fetches the newest page and appends only messages we aren't already showing
  /// — non-destructive (keeps pagination + any in-flight optimistic bubble).
  Future<void> _mergeLatest() async {
    try {
      final raw = await ServiceLocator.messaging.getContactMessages(_recipient, page: 1, pageSize: _pageSize);
      final fresh = raw.where((m) => !_displayedIds.contains(m.messageId)).toList();
      if (fresh.isEmpty) return;
      final add = <_Msg>[];
      for (final m in fresh) {
        add.add(_Msg(
          messageId: m.messageId,
          sender: m.sender,
          receiver: m.receiver,
          attachment: m.attachment,
          text: m.message.isEmpty ? '' : await _decrypt(m),
          timestamp: m.timestamp,
          isRead: m.isRead,
          readAt: m.readAt,
        ));
      }
      if (!mounted) return;
      setState(() {
        _messages.addAll(add);
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _displayedIds.addAll(add.map((m) => m.messageId));
        _recomputeDeliveryStatus();
      });
      _scrollToBottom();
    } catch (_) {/* non-fatal */}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppNavigation.inChat = false;
    _recvSub?.cancel();
    _readSub?.cancel();
    _typingSub?.cancel();
    _typingHideTimer?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await ServiceLocator.messaging.initializeWebSocket();
    _recvSub = ServiceLocator.messaging.onMessageReceived.listen(_onMessageReceived);
    _readSub = ServiceLocator.messaging.onMessagesRead.listen(_onMessagesRead);
    _typingSub = ServiceLocator.messaging.onPartnerTyping.listen(_onPartnerTyping);
    // Mark this contact's messages read (best-effort).
    unawaited(ServiceLocator.messaging.markMessagesAsRead(_recipient).catchError((_) => 0));
    await _loadMessages();
  }

  // ── Loading ──────────────────────────────────────────────────────────────────
  Future<void> _loadMessages() async {
    try {
      final raw = await ServiceLocator.messaging.getContactMessages(_recipient, page: 1, pageSize: _pageSize);
      _hasMore = raw.length >= _pageSize;
      final msgs = <_Msg>[];
      for (final m in raw) {
        msgs.add(_Msg(
          messageId: m.messageId,
          sender: m.sender,
          receiver: m.receiver,
          attachment: m.attachment,
          text: m.message.isEmpty ? '' : await _decrypt(m),
          timestamp: m.timestamp,
          isRead: m.isRead,
          readAt: m.readAt,
        ));
      }
      msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        _displayedIds
          ..clear()
          ..addAll(msgs.map((m) => m.messageId));
        _recomputeDeliveryStatus();
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await _alert('Error', 'Failed to load messages: $e');
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _loading) return;
    // Flip synchronously so re-entrant scroll events bail, and show the top
    // loading indicator while we fetch.
    setState(() => _loadingOlder = true);
    try {
      final next = _page + 1;
      final raw = await ServiceLocator.messaging.getContactMessages(_recipient, page: next, pageSize: _pageSize);
      final fresh = raw.where((m) => !_displayedIds.contains(m.messageId)).toList();
      if (fresh.isEmpty) {
        _hasMore = false;
        return;
      }
      if (raw.length < _pageSize) _hasMore = false;
      _page = next;
      final older = <_Msg>[];
      for (final m in fresh) {
        older.add(_Msg(
          messageId: m.messageId,
          sender: m.sender,
          receiver: m.receiver,
          attachment: m.attachment,
          text: m.message.isEmpty ? '' : await _decrypt(m),
          timestamp: m.timestamp,
          isRead: m.isRead,
          readAt: m.readAt,
        ));
      }
      older.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (!mounted) return;
      // With reverse:true the list is anchored at the bottom, so prepending
      // older messages (they render at the visual top / far end) does NOT move
      // the current viewport — no manual scroll anchoring needed.
      setState(() {
        _messages.insertAll(0, older);
        _displayedIds.addAll(older.map((m) => m.messageId));
      });
    } catch (_) {
      // non-fatal
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<String> _decrypt(MessageContent m) =>
      ServiceLocator.messageEncryption.decryptMessage(m.message, m.sender, m.receiver);

  // ── Realtime streams ─────────────────────────────────────────────────────────
  void _onMessageReceived(MessageReceivedEvent e) {
    final between = (e.sender == _recipient && e.receiver == _me) ||
        (e.sender == _me && e.receiver == _recipient);
    if (!between || _displayedIds.contains(e.messageId)) return;

    // The server echoes our OWN sent message over the socket too, and that echo
    // can beat the HTTP send response. Reconcile it against the still-optimistic
    // bubble (temp negative id, "sending") instead of appending a duplicate.
    if (e.sender == _me) {
      final idx = _messages.indexWhere(
          (m) => m.sending && m.messageId < 0 && m.text == e.message);
      if (idx >= 0) {
        setState(() {
          _messages[idx].messageId = e.messageId;
          _messages[idx].sending = false;
          if (e.attachment != null) _messages[idx].attachment = e.attachment;
          _displayedIds.add(e.messageId);
          _recomputeDeliveryStatus();
        });
        return;
      }
    }
    // WebSocket payloads are already plaintext (server-decrypted) — do NOT decrypt.
    setState(() {
      _messages.add(_Msg(
        messageId: e.messageId,
        sender: e.sender,
        receiver: e.receiver,
        attachment: e.attachment,
        text: e.message,
        timestamp: e.timestamp,
      ));
      _displayedIds.add(e.messageId);
      if (e.sender != _me) {
        _partnerTyping = false; // their message arrived
        _typingHideTimer?.cancel();
      }
      _recomputeDeliveryStatus();
    });
    if (e.sender != _me) {
      unawaited(ServiceLocator.messaging.markMessagesAsRead(_recipient).catchError((_) => 0));
    }
    _scrollToBottom();
  }

  void _onMessagesRead(MessagesReadEvent e) {
    if (e.readerEmail.toLowerCase() != _recipient.toLowerCase()) return;
    setState(() => _deliveryStatus = 'Read ${_fmtDateTime(e.readAt)}');
  }

  void _onPartnerTyping(PartnerTypingEvent e) {
    if (e.senderEmail.toLowerCase() != _recipient.toLowerCase()) return;
    setState(() => _partnerTyping = true);
    _typingHideTimer?.cancel();
    _typingHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _partnerTyping = false);
    });
  }

  void _onTextChanged() {
    if (_controller.text.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) < _typingThrottle) return;
    _lastTypingSent = now;
    unawaited(ServiceLocator.messaging.sendTypingNotification(_recipient).catchError((_) {}));
  }

  // ── Send ─────────────────────────────────────────────────────────────────────
  Future<void> _send() async {
    if (_sending) return;
    final text = _controller.text.trim();
    // Snapshot the pending attachments so we can restore them on rollback.
    final pending = List<({String base64, String fileName, Uint8List bytes})>.from(_pendingAttachments);
    final hasAttachment = pending.isNotEmpty;
    if (text.isEmpty && !hasAttachment) return;

    // Optimistic: show the message immediately with a "Sending…" status, clear
    // the composer, and reconcile once the server confirms (or roll back).
    final optimistic = _Msg(
      messageId: _nextTempId--,
      sender: _me,
      receiver: _recipient,
      // Placeholder transport (array of names) so the chips show file names
      // while sending; replaced with the real encrypted payload on confirm.
      attachment: hasAttachment
          ? jsonEncode([for (final a in pending) {'fileName': a.fileName}])
          : null,
      text: text,
      timestamp: DateTime.now(),
      sending: true,
    );
    setState(() {
      _sending = true;
      _controller.clear();
      _suggestion = null;
      _pendingAttachments.clear();
      _messages.add(optimistic);
      _recomputeDeliveryStatus();
    });
    _scrollToBottom();

    // Rolls the optimistic bubble back and restores the composer (bad tone / error).
    void rollback() {
      if (!mounted) return;
      setState(() {
        _messages.remove(optimistic);
        if (_controller.text.trim().isEmpty) _controller.text = text;
        _pendingAttachments
          ..clear()
          ..addAll(pending);
        _recomputeDeliveryStatus();
      });
    }

    try {
      final encrypted = await ServiceLocator.messageEncryption.encryptMessage(text, _me, _recipient);

      // Build the encrypted attachment transport as a JSON ARRAY of
      // {fileName, encryptedData}. Keys are camelCase to match the server's
      // case-SENSITIVE AttachmentModel ([JsonPropertyName] fileName/encryptedData);
      // PascalCase would null out EncryptedData → "Invalid attachment data" 500.
      String? attachmentPayload;
      if (hasAttachment) {
        final items = <Map<String, String>>[];
        for (final a in pending) {
          final enc = await ServiceLocator.messageEncryption
              .encryptAttachment(a.base64, _me, _recipient);
          items.add({'fileName': a.fileName, 'encryptedData': enc});
        }
        attachmentPayload = jsonEncode(items);
      }

      // MAUI sends to the raw contactEmail value (server resolves "partner").
      final response = await ServiceLocator.messaging
          .sendMessage(widget.contactEmail, encrypted, attachmentBase64: attachmentPayload);
      if (!mounted) return;

      switch (response.status) {
        case 'sent':
          // Reconcile the optimistic bubble in place: real id, real payload, no
          // longer "sending" → status flips to Delivered.
          setState(() {
            optimistic.messageId = response.messageId;
            optimistic.attachment = attachmentPayload;
            optimistic.sending = false;
            _displayedIds.add(response.messageId);
            _recomputeDeliveryStatus();
          });
          break;
        case 'bad_tone':
          rollback();
          setState(() {
            _suggestion = response.suggested;
            _toneScore = response.tonescore;
          });
          break;
        default:
          rollback();
          await _alert('Error', 'Failed to send message');
      }
    } catch (e) {
      rollback();
      if (mounted) await _alert('Error', 'Error sending message: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _useSuggestion() {
    if (_suggestion == null) return;
    setState(() {
      _controller.text = _suggestion!;
      _suggestion = null;
    });
  }

  // ── Delivery status ────────────────────────────────────────────────────────
  void _recomputeDeliveryStatus() {
    if (_messages.isEmpty) {
      _deliveryStatus = null;
      return;
    }
    final lastSentIndex = _messages.lastIndexWhere((m) => m.sender == _me);
    if (lastSentIndex < 0) {
      _deliveryStatus = null;
      return;
    }
    // Suppress if the contact replied after our last sent message.
    final newerReply = _messages.skip(lastSentIndex + 1).any((m) => m.sender != _me);
    if (newerReply) {
      _deliveryStatus = null;
      return;
    }
    final last = _messages[lastSentIndex];
    _deliveryStatus = last.sending
        ? 'Sending…'
        : last.isRead
            ? (last.readAt != null ? 'Read ${_fmtDateTime(last.readAt!)}' : 'Read')
            : 'Delivered';
  }

  // ── Scroll / format helpers ──────────────────────────────────────────────────
  void _onScroll() {
    // reverse:true → the TOP (oldest end) is near maxScrollExtent.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 50 &&
        _hasMore &&
        !_loadingOlder) {
      _loadOlder();
    }
  }

  // reverse:true → the bottom (newest) is offset 0.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  static String _fmtDateTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '${t.month}/${t.day}/${t.year} $h:${t.minute.toString().padLeft(2, '0')} $ampm';
  }

  Future<void> _alert(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // The trailing items count: messages + (typing bubble?) — delivery status is
    // appended after the last bubble inside the list.
    return Scaffold(
      backgroundColor: palette.surface,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: Container(
              color: palette.background,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                    children: [
                      Builder(builder: (_) {
                        // reverse:true anchors the list at the BOTTOM — the first
                        // frame opens on the newest message, and prepending older
                        // messages at the (visual) top never shifts the viewport.
                        // Index 0 is the bottom: the footer (delivery status +
                        // typing) when present, otherwise the newest message.
                        final hasFooter = _deliveryStatus != null || _partnerTyping;
                        return ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length + (hasFooter ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (hasFooter && i == 0) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_deliveryStatus != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8, bottom: 6),
                                      child: Text(_deliveryStatus!,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                              fontSize: 11, fontWeight: FontWeight.bold, color: palette.textSecondary)),
                                    ),
                                  if (_partnerTyping) _typingBubble(context),
                                ],
                              );
                            }
                            // Map the reversed display index → message (newest first).
                            final mi = _messages.length - 1 - (hasFooter ? i - 1 : i);
                            // Tighten the gap on the newest bubble when the delivery
                            // status sits right beneath it.
                            final tightBottom = hasFooter && i == 1 && _deliveryStatus != null && !_partnerTyping;
                            return Padding(
                              padding: EdgeInsets.only(bottom: tightBottom ? 2 : 12),
                              child: _bubble(context, _messages[mi]),
                            );
                          },
                        );
                      }),
                      if (_loadingOlder)
                        Positioned(
                          top: 10,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              width: 34,
                              height: 34,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: palette.surfaceElevated,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
                                ],
                              ),
                              child: const CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
            ),
            ),
          ),
          if (_suggestion != null) _suggestionBar(context),
          if (_pendingAttachments.isNotEmpty) _attachmentPreviewBar(context),
          _inputBar(context),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────
  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(4, MediaQuery.viewPaddingOf(context).top + 8, 16, 8),
      color: palette.surface,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Text('‹', style: TextStyle(fontSize: 32, color: AppColors.primaryBlue)),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(widget.contactName,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcon('icon_lock', size: 12, color: palette.textSecondary),
                    const SizedBox(width: 4),
                    Text('Encrypted', style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.successGreen, borderRadius: BorderRadius.circular(14)),
            child: const Center(child: AppIcon('icon_shield_check', size: 22, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Message bubble ─────────────────────────────────────────────────────────────
  Widget _bubble(BuildContext context, _Msg m) {
    final palette = context.palette;
    final outgoing = m.sender == _me;
    return Row(
      mainAxisAlignment: outgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!outgoing) ...[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(18)),
            child: Center(
              child: Text(widget.contactName.characters.isEmpty ? '?' : widget.contactName.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: outgoing ? AppColors.primaryBlue : palette.surfaceElevated,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(outgoing ? 16 : 4),
                bottomRight: Radius.circular(outgoing ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.hasAttachment) ...[
                  _attachments(context, m, outgoing),
                  if (m.text.isNotEmpty) const SizedBox(height: 8),
                ],
                if (m.text.isNotEmpty)
                  Text(m.text,
                      style: TextStyle(fontSize: 15, color: outgoing ? Colors.white : palette.textPrimary)),
                const SizedBox(height: 4),
                Text(_fmtDateTime(m.timestamp),
                    style: TextStyle(fontSize: 10, color: outgoing ? Colors.white70 : palette.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Attachments ────────────────────────────────────────────────────────────
  static const _imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'};

  /// Parses the attachment transport/metadata JSON into the list of (plaintext)
  /// file names. Tolerant of a JSON array (new, multi) OR a single object (legacy).
  List<String> _attachmentNames(_Msg m) {
    final raw = m.attachment;
    if (raw == null || raw.trim().isEmpty) return const [];
    String nameOf(dynamic e) =>
        (e is Map ? (e['fileName'] ?? e['FileName']) : null)?.toString().trim().isNotEmpty == true
            ? (e['fileName'] ?? e['FileName']).toString()
            : 'Attachment';
    try {
      final j = jsonDecode(raw);
      if (j is List) return [for (final e in j) nameOf(e)];
      if (j is Map) return [nameOf(j)];
    } catch (_) {/* fall through */}
    return const ['Attachment'];
  }

  bool _isImageName(String name) => _imageExts.contains(p.extension(name).toLowerCase());

  /// Renders all of a message's attachments — a single item, or a wrapped set
  /// of thumbnails/chips for multiple.
  Widget _attachments(BuildContext context, _Msg m, bool outgoing) {
    final names = _attachmentNames(m);
    if (names.isEmpty) return const SizedBox.shrink();
    if (names.length == 1) return _attachmentItem(context, m, outgoing, 0, names[0]);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (int i = 0; i < names.length; i++) _attachmentItem(context, m, outgoing, i, names[i]),
      ],
    );
  }

  Widget _attachmentItem(BuildContext context, _Msg m, bool outgoing, int index, String name) {
    final palette = context.palette;
    final isImage = _isImageName(name);
    final fg = outgoing ? Colors.white : palette.textPrimary;
    // Image attachments (already on the server) show a lazy-loaded thumbnail
    // instead of a generic icon — the bytes are cached + reused by the viewer.
    if (isImage && !m.sending) {
      return GestureDetector(
        onTap: () => _onAttachmentTapped(m, index, name),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _AttachmentThumb(
            key: ValueKey('thumb_${m.messageId}_$index'),
            load: () => _downloadAttachmentBytes(m, index, silent: true),
            placeholderColor: (outgoing ? Colors.white : palette.textSecondary).withValues(alpha: 0.15),
            iconColor: fg,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => _onAttachmentTapped(m, index, name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: (outgoing ? Colors.white : palette.textSecondary).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(isImage ? 'icon_image' : 'icon_document', size: 20, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ),
            const SizedBox(width: 6),
            AppIcon('icon_download', size: 16, color: fg),
          ],
        ),
      ),
    );
  }

  /// Action sheet for a tapped attachment (port of OnAttachmentPreviewTapped).
  Future<void> _onAttachmentTapped(_Msg m, int index, String name) async {
    if (m.sending) return; // not yet on the server — no real id to fetch by
    final isImage = _isImageName(name);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.surfaceElevated,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        Widget row(String value, String icon, String label) => ListTile(
              leading: AppIcon(icon, size: 20, color: context.palette.textSecondary),
              title: Text(label, style: TextStyle(color: context.palette.textPrimary, fontSize: 16)),
              onTap: () => Navigator.of(sheetCtx).pop(value),
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              row('view', 'icon_eye', 'View'),
              row('files', 'icon_share', 'Save to Files'),
              if (isImage) row('camera', 'icon_image', 'Save to Camera Roll'),
              row('vault', 'icon_folder', 'Save to Vault'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null) return;

    final bytes = await _downloadAttachmentBytes(m, index);
    if (bytes == null) return;
    switch (action) {
      case 'view':
        await _viewAttachment(name, bytes);
        break;
      case 'files':
        await _saveAttachmentToFiles(name, bytes);
        break;
      case 'camera':
        await _saveAttachmentToCameraRoll(name, bytes);
        break;
      case 'vault':
        await _saveAttachmentToVault(name, bytes);
        break;
    }
  }

  /// Downloads + decrypts an attachment to raw bytes (port of the
  /// GetAttachmentAsync + DecryptAttachment + base64-decode pipeline).
  /// Downloads + decrypts an attachment to raw bytes. [silent] suppresses the
  /// error alerts — used for the inline thumbnail load (a background fetch that
  /// must NOT pop a dialog over the chat if it fails); the interactive
  /// View/Save path leaves it false so the user still gets feedback.
  Future<List<int>?> _downloadAttachmentBytes(_Msg m, int index, {bool silent = false}) async {
    // A negative id is an optimistic message not yet on the server — there's no
    // real attachment to fetch by id.
    if (m.messageId < 0) return null;
    // Reuse already-downloaded+decrypted bytes when the user taps the same
    // attachment again (View, then Save, etc.). Keyed by message id + index.
    final cacheKey = '${m.messageId}:$index';
    final cached = _attachmentBytesCache[cacheKey];
    if (cached != null) return cached;
    try {
      final att = await ServiceLocator.messaging.getAttachment(m.messageId, index: index);
      if (att == null || att.encryptedData.isEmpty) {
        if (!silent && mounted) await _alert('Error', 'Failed to download attachment data');
        return null;
      }
      final decrypted = await ServiceLocator.messageEncryption
          .decryptAttachment(att.encryptedData, m.sender, m.receiver);
      // decryptAttachment returns the '[Encrypted message]' sentinel on auth
      // failure, which is not valid base64 — guard so we don't throw on decode.
      if (decrypted.isEmpty || decrypted == '[Encrypted message]') {
        if (!silent && mounted) await _alert('Error', 'Failed to decrypt attachment');
        return null;
      }
      final bytes = base64Decode(decrypted);
      _attachmentBytesCache[cacheKey] = bytes;
      return bytes;
    } catch (e) {
      if (!silent && mounted) await _alert('Error', 'Failed to decrypt attachment: $e');
      return null;
    }
  }

  Future<File> _writeTemp(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _viewAttachment(String name, List<int> bytes) async {
    final file = await _writeTemp(name, bytes);
    if (!mounted) return;
    if (_isImageName(name)) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _AttachmentImageViewer(path: file.path, name: name)));
    } else {
      await OpenFilex.open(file.path);
    }
  }

  Future<void> _saveAttachmentToFiles(String name, List<int> bytes) async {
    // Native "Save to Files": file_picker.saveFile presents the system document
    // picker (UIDocumentPicker export on iOS / SAF create-document on Android)
    // and writes the bytes to the chosen location. The old share-sheet route
    // didn't reliably surface "Save to Files" on iOS.
    try {
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save to Files',
        fileName: name,
        bytes: Uint8List.fromList(bytes),
      );
      if (saved != null && mounted) await _alert('Saved', 'Saved to Files.');
    } catch (e) {
      // Fall back to the share sheet (which also offers "Save to Files").
      try {
        final file = await _writeTemp(name, bytes);
        await Share.shareXFiles([XFile(file.path)], subject: name);
      } catch (_) {
        if (mounted) await _alert('Error', 'Could not save the file: $e');
      }
    }
  }

  Future<void> _saveAttachmentToCameraRoll(String name, List<int> bytes) async {
    try {
      final file = await _writeTemp(name, bytes);
      await Gal.putImage(file.path);
      if (mounted) await _alert('Saved', 'Image saved to your camera roll.');
    } catch (e) {
      if (mounted) await _alert('Error', 'Could not save to camera roll: $e');
    }
  }

  Future<void> _saveAttachmentToVault(String name, List<int> bytes) async {
    // Let the user choose the destination folder in the vault (mirrors MAUI's
    // folder-picker), defaulting to the root if they don't drill in.
    if (!mounted) return;
    final folder = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const FileVaultPage(pickFolder: true)));
    if (folder == null) return; // cancelled
    try {
      final dir = Directory(folder);
      if (!await dir.exists()) await dir.create(recursive: true);
      var dest = p.join(folder, name);
      if (await File(dest).exists()) {
        // Ask whether to replace, matching MAUI's overwrite prompt.
        final overwrite = await _confirmOverwrite(name);
        if (overwrite == null) return; // cancelled
        if (!overwrite) {
          final stem = p.basenameWithoutExtension(name);
          final ext = p.extension(name);
          dest = p.join(folder, '$stem-${DateTime.now().millisecondsSinceEpoch}$ext');
        }
      }
      await File(dest).writeAsBytes(bytes, flush: true);
      if (mounted) await _alert('Saved', 'Saved to your File Vault.');
    } catch (e) {
      if (mounted) await _alert('Error', 'Could not save to vault: $e');
    }
  }

  /// Returns true=replace, false=keep both, null=cancel.
  Future<bool?> _confirmOverwrite(String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('File Exists'),
        content: Text('"$name" already exists in this folder. Replace it?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep Both')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Replace')),
        ],
      ),
    );
  }

  /// Compose: pick an attachment for the next message. Mirrors MAUI's
  /// "Choose Attachment Source" sheet — Vault / Files / Photo Library.
  Future<void> _pickAttachment() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.surfaceElevated,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: AppIcon('icon_folder', size: 20, color: context.palette.textSecondary),
              title: Text('Select from Vault', style: TextStyle(color: context.palette.textPrimary, fontSize: 16)),
              onTap: () => Navigator.of(sheetCtx).pop('vault'),
            ),
            ListTile(
              leading: AppIcon('icon_image', size: 20, color: context.palette.textSecondary),
              title: Text('Photo Library', style: TextStyle(color: context.palette.textPrimary, fontSize: 16)),
              onTap: () => Navigator.of(sheetCtx).pop('photo'),
            ),
            ListTile(
              leading: AppIcon('icon_document', size: 20, color: context.palette.textSecondary),
              title: Text('Files', style: TextStyle(color: context.palette.textPrimary, fontSize: 16)),
              onTap: () => Navigator.of(sheetCtx).pop('files'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      // Every source is now multi-select; collect (path, name) pairs.
      final picked = <({String path, String name})>[];
      if (source == 'vault') {
        if (!mounted) return;
        final paths = await Navigator.of(context).push<List<String>>(
            MaterialPageRoute(builder: (_) => const FileVaultPage(pickFiles: true)));
        if (paths != null) {
          for (final pth in paths) {
            picked.add((path: pth, name: p.basename(pth)));
          }
        }
      } else if (source == 'photo') {
        final xs = await ImagePicker().pickMultiImage();
        for (final x in xs) {
          picked.add((path: x.path, name: p.basename(x.path)));
        }
      } else {
        final r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
        if (r != null) {
          for (final f in r.files) {
            if (f.path != null) picked.add((path: f.path!, name: f.name));
          }
        }
      }
      if (picked.isEmpty) return;
      final added = <({String base64, String fileName, Uint8List bytes})>[];
      for (final it in picked) {
        final bytes = await File(it.path).readAsBytes();
        added.add((base64: base64Encode(bytes), fileName: it.name, bytes: bytes));
      }
      if (!mounted) return;
      setState(() => _pendingAttachments.addAll(added));
    } catch (e) {
      if (mounted) await _alert('Error', 'Could not attach file: $e');
    }
  }

  Widget _attachmentPreviewBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
      child: SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pendingAttachments.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _pendingPreviewTile(context, i),
        ),
      ),
    );
  }

  Widget _pendingPreviewTile(BuildContext context, int i) {
    final palette = context.palette;
    final a = _pendingAttachments[i];
    final isImage = _isImageName(a.fileName);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 120,
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              if (isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    a.bytes,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: (40 * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorBuilder: (_, _, _) => AppIcon('icon_image', size: 20, color: palette.textSecondary),
                  ),
                )
              else
                AppIcon('icon_document', size: 22, color: palette.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(a.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: palette.textPrimary)),
              ),
            ],
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => setState(() => _pendingAttachments.removeAt(i)),
            child: Container(
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              padding: const EdgeInsets.all(3),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _typingBubble(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: _TypingDots(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── Suggestion bar (tone check) ──────────────────────────────────────────────
  Widget _suggestionBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      color: context.isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_toneScore != null ? 'Suggested revision · Tone score: $_toneScore/10' : 'Suggested revision',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: context.isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E))),
          const SizedBox(height: 4),
          Text(_suggestion ?? '',
              style: TextStyle(fontSize: 14, color: context.isDark ? const Color(0xFFFCD34D) : const Color(0xFF78350F))),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => setState(() => _suggestion = null), child: const Text('Dismiss')),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white),
                onPressed: _useSuggestion,
                child: const Text('Use Suggestion'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────────────
  Widget _inputBar(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: palette.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
              offset: const Offset(0, -4),
              blurRadius: 16),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _pickAttachment,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(child: AppIcon('icon_attachment', size: 22, color: palette.textSecondary)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 5,
                style: TextStyle(fontSize: 16, color: palette.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: palette.textSecondary),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: _sending ? AppColors.primaryBlue.withValues(alpha: 0.6) : AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(22)),
              child: Center(
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const AppIcon('icon_send', size: 20, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three dots that fade up and down in sequence — an animated "typing…" indicator
/// (replaces the static dots, the Flutter upgrade over MAUI's still bubble).
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            // Each dot's phase is offset by 1/3 so the wave travels left→right.
            Builder(builder: (_) {
              final phase = (_c.value - i * 0.2) % 1.0;
              final t = (1 - (phase * 2 - 1).abs()).clamp(0.0, 1.0); // triangle 0→1→0
              return Opacity(
                opacity: 0.3 + 0.7 * t,
                child: Transform.translate(
                  offset: Offset(0, -3 * t),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                  ),
                ),
              );
            }),
            if (i < 2) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// Lazily downloads + decrypts an image attachment and shows it as a rounded
/// thumbnail (with a loading placeholder / icon fallback). Used inline in chat
/// bubbles so image attachments preview instead of showing a generic icon.
class _AttachmentThumb extends StatefulWidget {
  const _AttachmentThumb({super.key, required this.load, required this.placeholderColor, required this.iconColor});
  final Future<List<int>?> Function() load;
  final Color placeholderColor;
  final Color iconColor;

  @override
  State<_AttachmentThumb> createState() => _AttachmentThumbState();
}

class _AttachmentThumbState extends State<_AttachmentThumb> {
  // Fixed thumbnail box. Both the loading placeholder AND the decoded image use
  // these exact dimensions (BoxFit.cover), so the image resolving in does NOT
  // change the bubble height — which previously caused a jarring scroll jump.
  static const double _w = 180.0;
  static const double _h = 135.0;

  Uint8List? _bytes;
  bool _failed = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    if (mounted && _failed) setState(() => _failed = false); // retry resets state
    try {
      final b = await widget.load();
      if (!mounted) return;
      setState(() {
        if (b != null && b.isNotEmpty) {
          _bytes = Uint8List.fromList(b);
          _failed = false;
        } else {
          _failed = true;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _loading = false;
    }
  }

  // Fixed-size box shared by the loading / failed / decode-error states so the
  // bubble doesn't jump as the image resolves.
  Widget _fallback({required bool spinner}) => Container(
        width: _w,
        height: _h,
        color: widget.placeholderColor,
        alignment: Alignment.center,
        child: spinner
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: widget.iconColor))
            : AppIcon('icon_image', size: 28, color: widget.iconColor),
      );

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return SizedBox(
        width: _w,
        height: _h,
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          // Downsample large photos to the display size — a multi-MB image
          // decoded at full resolution wastes memory and can fail/jank on iOS.
          cacheWidth: (_w * MediaQuery.devicePixelRatioOf(context)).round(),
          // A corrupt/partial/undecodable payload shows the icon instead of a
          // broken render or a thrown exception in layout.
          errorBuilder: (_, _, _) => _fallback(spinner: false),
        ),
      );
    }
    // Tapping the failed placeholder retries the download+decrypt.
    return GestureDetector(
      onTap: _failed ? _load : null,
      child: _fallback(spinner: !_failed),
    );
  }
}

/// Full-screen viewer for an image attachment (matches MAUI's in-chat image viewer).
class _AttachmentImageViewer extends StatelessWidget {
  const _AttachmentImageViewer({required this.path, required this.name});
  final String path;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      try {
                        await Share.shareXFiles([XFile(path)], subject: name);
                      } catch (_) {}
                    },
                    child: const Icon(Icons.ios_share, color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Unable to display this image.',
                          style: TextStyle(color: Colors.white70, fontSize: 15)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
