import 'package:flutter/material.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../messaging/chat_interface_page.dart';

/// Child's parent contacts — faithful port of `Views/Child/ChildMessagingPage.xaml(.cs)`.
///
/// Loads the family ([AuthService.getFamilyInfo]) to list the child's two parents
/// and the latest message per contact (decrypted via [MessageEncryptionService])
/// for the preview + unread state. Tapping opens the shared encrypted chat.
class ChildMessagingPage extends StatefulWidget {
  const ChildMessagingPage({super.key});

  @override
  State<ChildMessagingPage> createState() => _ChildMessagingPageState();
}

class _ParentContact {
  _ParentContact(this.email, this.name, this.preview, this.hasUnread);
  final String email;
  final String name;
  final String preview;
  final bool hasUnread;
}

class _ChildMessagingPageState extends State<ChildMessagingPage> {
  bool _loading = true;
  bool _noFamily = false;
  List<_ParentContact> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      await ServiceLocator.messaging.initializeWebSocket();
      final family = await ServiceLocator.auth.getFamilyInfo();
      final latest = await ServiceLocator.messaging.getLatestMessagesPerContact();
      final me = Preferences.getString('email');

      // Decrypt previews (HTTP rows are AES-GCM ciphertext).
      final decrypted = <({String sender, String receiver, String text, DateTime ts, bool isRead})>[];
      for (final m in latest) {
        final text = m.message.isEmpty
            ? ''
            : await ServiceLocator.messageEncryption.decryptMessage(m.message, m.sender, m.receiver);
        decrypted.add((sender: m.sender, receiver: m.receiver, text: text, ts: m.timestamp, isRead: m.isRead));
      }

      if (family == null) {
        if (!mounted) return;
        setState(() {
          _noFamily = true;
          _loading = false;
        });
        return;
      }

      ({String preview, bool hasUnread}) previewFor(String parentEmail) {
        final rows = decrypted
            .where((m) =>
                (m.sender.toLowerCase() == parentEmail.toLowerCase() && m.receiver.toLowerCase() == me.toLowerCase()) ||
                (m.sender.toLowerCase() == me.toLowerCase() && m.receiver.toLowerCase() == parentEmail.toLowerCase()))
            .toList()
          ..sort((a, b) => b.ts.compareTo(a.ts));
        if (rows.isEmpty) return (preview: 'Tap to chat', hasUnread: false);
        final latestMsg = rows.first;
        final hasUnread = latestMsg.sender.toLowerCase() == parentEmail.toLowerCase() &&
            latestMsg.receiver.toLowerCase() == me.toLowerCase() &&
            !latestMsg.isRead;
        final preview = _truncate(latestMsg.text.isEmpty ? 'No message' : latestMsg.text);
        return (preview: preview, hasUnread: hasUnread);
      }

      final contacts = <_ParentContact>[];
      if ((family.parent1Email?.isNotEmpty ?? false)) {
        final name = (family.parent1Name?.isNotEmpty ?? false) ? family.parent1Name! : _nameFromEmail(family.parent1Email!);
        final p = previewFor(family.parent1Email!);
        contacts.add(_ParentContact(family.parent1Email!, name, p.preview, p.hasUnread));
      }
      if ((family.parent2Email?.isNotEmpty ?? false)) {
        final name = (family.parent2Name?.isNotEmpty ?? false) ? family.parent2Name! : _nameFromEmail(family.parent2Email!);
        final p = previewFor(family.parent2Email!);
        contacts.add(_ParentContact(family.parent2Email!, name, p.preview, p.hasUnread));
      }

      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _noFamily = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _truncate(String s) => s.length <= 30 ? s : '${s.substring(0, 27)}...';

  static String _nameFromEmail(String email) {
    final at = email.indexOf('@');
    final local = at > 0 ? email.substring(0, at) : email;
    final words = local.replaceAll('.', ' ').replaceAll('_', ' ').replaceAll('-', ' ').split(' ').where((w) => w.isNotEmpty);
    return words.isEmpty ? email : words.map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: palette.surface,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
                    offset: const Offset(0, 4),
                    blurRadius: 16),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(14)),
                  child: const Center(child: AppIcon('icon_chat', size: 24, color: AppColors.primaryBlue)),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Messages',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Chat with your parents', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _noFamily
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Opacity(opacity: 0.5, child: AppIcon('icon_users', size: 60, color: palette.textSecondary)),
                              const SizedBox(height: 16),
                              Text("You're not connected to a family yet",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        children: [
                          for (final c in _contacts) ...[
                            _contactCard(context, c),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _contactCard(BuildContext context, _ParentContact c) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatInterfacePage(contactEmail: c.email, contactName: c.name)),
        );
        if (mounted) _load();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(16)),
              child: Center(
                child: Text(c.name.isNotEmpty ? c.name.characters.first.toUpperCase() : '?',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(c.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: c.hasUnread ? FontWeight.bold : FontWeight.normal,
                          color: c.hasUnread ? palette.textPrimary : palette.textSecondary)),
                ],
              ),
            ),
            if (c.hasUnread) ...[
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(color: AppColors.primaryBlue, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
            ],
            AppIcon('icon_chevron_right', size: 18, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}
