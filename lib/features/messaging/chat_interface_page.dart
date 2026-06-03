import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class _ChatInterfacePageState extends State<ChatInterfacePage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  final List<_Msg> _messages = [];
  final Set<int> _displayedIds = {};

  // Temporary (negative) ids for optimistic messages, before the server assigns
  // the real one — kept distinct from real ids so reconciliation can't collide.
  int _nextTempId = -1;

  // Decrypted attachment bytes cached by message id for the lifetime of the
  // open thread, so re-tapping an attachment doesn't refetch + redecrypt.
  final Map<int, List<int>> _attachmentBytesCache = {};

  late final String _me;
  late final String _recipient;

  bool _loading = true;
  bool _sending = false;
  // Pending attachment selected for the next outgoing message.
  String? _pendingAttachmentBase64;
  String? _pendingAttachmentFileName;
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
    _init();
  }

  @override
  void dispose() {
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
    _loadingOlder = true;
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
      setState(() {
        _messages.insertAll(0, older);
        _displayedIds.addAll(older.map((m) => m.messageId));
      });
    } catch (_) {
      // non-fatal
    } finally {
      _loadingOlder = false;
    }
  }

  Future<String> _decrypt(MessageContent m) =>
      ServiceLocator.messageEncryption.decryptMessage(m.message, m.sender, m.receiver);

  // ── Realtime streams ─────────────────────────────────────────────────────────
  void _onMessageReceived(MessageReceivedEvent e) {
    final between = (e.sender == _recipient && e.receiver == _me) ||
        (e.sender == _me && e.receiver == _recipient);
    if (!between || _displayedIds.contains(e.messageId)) return;
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
    final pendingBase64 = _pendingAttachmentBase64;
    final pendingFileName = _pendingAttachmentFileName;
    final hasAttachment = pendingBase64 != null;
    if (text.isEmpty && !hasAttachment) return;

    // Optimistic: show the message immediately with a "Sending…" status, clear
    // the composer, and reconcile once the server confirms (or roll back).
    final optimistic = _Msg(
      messageId: _nextTempId--,
      sender: _me,
      receiver: _recipient,
      // Placeholder transport so the attachment chip can show the file name
      // while sending; replaced with the real encrypted payload on confirm.
      attachment: hasAttachment ? jsonEncode({'FileName': pendingFileName}) : null,
      text: text,
      timestamp: DateTime.now(),
      sending: true,
    );
    setState(() {
      _sending = true;
      _controller.clear();
      _suggestion = null;
      _pendingAttachmentBase64 = null;
      _pendingAttachmentFileName = null;
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
        _pendingAttachmentBase64 = pendingBase64;
        _pendingAttachmentFileName = pendingFileName;
        _recomputeDeliveryStatus();
      });
    }

    try {
      final encrypted = await ServiceLocator.messageEncryption.encryptMessage(text, _me, _recipient);

      // Build the encrypted attachment transport ({FileName, EncryptedData}) —
      // mirrors MAUI's send path.
      String? attachmentPayload;
      if (hasAttachment) {
        final enc = await ServiceLocator.messageEncryption
            .encryptAttachment(pendingBase64, _me, _recipient);
        attachmentPayload =
            jsonEncode({'FileName': pendingFileName, 'EncryptedData': enc});
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
          setState(() => _suggestion = response.suggested);
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
    if (_scroll.position.pixels <= 50 && _hasMore && !_loadingOlder) {
      _loadOlder();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
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
                  : ListView.builder(
                      controller: _scroll,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(16),
                      // Messages, then a trailing footer row (delivery status +
                      // typing bubble) when either is present.
                      itemCount: _messages.length + ((_deliveryStatus != null || _partnerTyping) ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i < _messages.length) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _bubble(context, _messages[i]),
                          );
                        }
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
                      },
                    ),
            ),
            ),
          ),
          if (_suggestion != null) _suggestionBar(context),
          if (_pendingAttachmentFileName != null) _attachmentPreviewBar(context),
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
                  _attachmentChip(context, m, outgoing),
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

  /// Extracts the (plaintext) file name from the attachment metadata/transport JSON.
  String _attachmentFileName(_Msg m) {
    try {
      final j = jsonDecode(m.attachment!);
      if (j is Map) {
        final name = j['FileName'] ?? j['fileName'];
        if (name is String && name.isNotEmpty) return name;
      }
    } catch (_) {/* fall through */}
    return 'Attachment';
  }

  bool _isImageName(String name) => _imageExts.contains(p.extension(name).toLowerCase());

  Widget _attachmentChip(BuildContext context, _Msg m, bool outgoing) {
    final palette = context.palette;
    final name = _attachmentFileName(m);
    final isImage = _isImageName(name);
    final fg = outgoing ? Colors.white : palette.textPrimary;
    return GestureDetector(
      onTap: () => _onAttachmentTapped(m),
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
  Future<void> _onAttachmentTapped(_Msg m) async {
    if (m.sending) return; // not yet on the server — no real id to fetch by
    final name = _attachmentFileName(m);
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

    final bytes = await _downloadAttachmentBytes(m);
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
  Future<List<int>?> _downloadAttachmentBytes(_Msg m) async {
    // Reuse already-downloaded+decrypted bytes when the user taps the same
    // attachment again (View, then Save, etc.) — avoids a second network round
    // trip and AES-GCM decrypt. Keyed by the real message id.
    final cached = _attachmentBytesCache[m.messageId];
    if (cached != null) return cached;
    try {
      final att = await ServiceLocator.messaging.getAttachment(m.messageId);
      if (att == null || att.encryptedData.isEmpty) {
        if (mounted) await _alert('Error', 'Failed to download attachment data');
        return null;
      }
      final decrypted = await ServiceLocator.messageEncryption
          .decryptAttachment(att.encryptedData, m.sender, m.receiver);
      final bytes = base64Decode(decrypted);
      _attachmentBytesCache[m.messageId] = bytes;
      return bytes;
    } catch (e) {
      if (mounted) await _alert('Error', 'Failed to decrypt attachment: $e');
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
    final file = await _writeTemp(name, bytes);
    await Share.shareXFiles([XFile(file.path)], subject: name);
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
    try {
      final base = await getApplicationSupportDirectory();
      final vault = Directory(p.join(base.path, 'PrivateLocker'));
      if (!await vault.exists()) await vault.create(recursive: true);
      var dest = p.join(vault.path, name);
      // Avoid clobbering an existing file.
      if (await File(dest).exists()) {
        final stem = p.basenameWithoutExtension(name);
        final ext = p.extension(name);
        dest = p.join(vault.path, '$stem-${DateTime.now().millisecondsSinceEpoch}$ext');
      }
      await File(dest).writeAsBytes(bytes, flush: true);
      if (mounted) await _alert('Saved', 'Saved to your File Vault.');
    } catch (e) {
      if (mounted) await _alert('Error', 'Could not save to vault: $e');
    }
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
      String? path;
      String? name;
      if (source == 'vault') {
        if (!mounted) return;
        final picked = await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => const FileVaultPage(pickFile: true)));
        if (picked != null) {
          path = picked;
          name = p.basename(picked);
        }
      } else if (source == 'photo') {
        final x = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (x != null) {
          path = x.path;
          name = p.basename(x.path);
        }
      } else {
        final r = await FilePicker.platform.pickFiles(withData: false);
        if (r != null && r.files.isNotEmpty && r.files.first.path != null) {
          path = r.files.first.path;
          name = r.files.first.name;
        }
      }
      if (path == null || name == null) return;
      final bytes = await File(path).readAsBytes();
      setState(() {
        _pendingAttachmentBase64 = base64Encode(bytes);
        _pendingAttachmentFileName = name;
      });
    } catch (e) {
      if (mounted) await _alert('Error', 'Could not attach file: $e');
    }
  }

  Widget _attachmentPreviewBar(BuildContext context) {
    final palette = context.palette;
    final name = _pendingAttachmentFileName ?? '';
    final isImage = _isImageName(name);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
      child: Row(
        children: [
          AppIcon(isImage ? 'icon_image' : 'icon_document', size: 20, color: palette.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: palette.textPrimary)),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _pendingAttachmentBase64 = null;
              _pendingAttachmentFileName = null;
            }),
            child: AppIcon('icon_close', size: 18, color: palette.textSecondary),
          ),
        ],
      ),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: palette.textSecondary, shape: BoxShape.circle),
                  ),
                  if (i < 2) const SizedBox(width: 6),
                ],
              ],
            ),
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
          Text('Suggested revision',
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
                child: InteractiveViewer(child: Image.file(File(path), fit: BoxFit.contain)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
