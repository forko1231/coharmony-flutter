import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/message_models.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/skeleton.dart';
import '../ai/ai_chat_page.dart';
import '../calling/call_actions.dart';
import 'chat_interface_page.dart';
import 'contact_detail_page.dart';

/// Messages hub — faithful port of `Views/Messaging/Messaging.xaml(.cs)`.
///
/// Loads the latest message per contact ([MessagingService.getLatestMessagesPerContact]),
/// **decrypts** each via [MessageEncryptionService], and categorizes contacts into
/// Co-Parent / Children / Legal / Other using `checkForInvite` + `getChildren` +
/// `getApprovedLawyers`. Reloads on the `onMessageReceived` stream while visible.
class MessagingPage extends StatefulWidget {
  const MessagingPage({super.key});

  @override
  State<MessagingPage> createState() => _MessagingPageState();
}

class _MessagingPageState extends State<MessagingPage> {
  bool _loading = true;
  List<_ContactSection> _sections = const [];
  StreamSubscription<MessageReceivedEvent>? _msgSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await ServiceLocator.messaging.initializeWebSocket();
    _msgSub = ServiceLocator.messaging.onMessageReceived.listen((_) => _load(silent: true));
    await _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final me = Preferences.getString('email');

      // Partner (synced) + relationship maps.
      final partner = await ServiceLocator.auth.checkForInvite();
      final hasPartner = partner.synced;
      final partnerEmail = hasPartner ? (partner.inviterEmail ?? '') : '';
      String partnerName = '';
      if (hasPartner) {
        if (partnerEmail.isNotEmpty) await Preferences.setString('partnerEmail', partnerEmail);
        partnerName = (partner.inviterName?.isNotEmpty ?? false)
            ? partner.inviterName!
            : _nameFromEmail(partnerEmail);
      }

      final lawyers = await ServiceLocator.auth.getApprovedLawyers();
      final children = await ServiceLocator.auth.getChildren();

      final lawyerEmails = <String>{};
      final lawyerNames = <String, String>{};
      for (final l in lawyers) {
        final e = l.lawyerEmail;
        if (e != null && e.isNotEmpty) {
          lawyerEmails.add(e.toLowerCase());
          if (l.lawyerName?.isNotEmpty ?? false) lawyerNames[e.toLowerCase()] = l.lawyerName!;
        }
      }
      final childEmails = <String>{};
      final childNames = <String, String>{};
      for (final c in children.where((c) => c.isAccepted)) {
        final e = c.email;
        if (e != null && e.isNotEmpty) {
          childEmails.add(e.toLowerCase());
          final name = (c.firstName?.isNotEmpty ?? false)
              ? '${c.firstName}${c.lastName?.isNotEmpty ?? false ? ' ${c.lastName}' : ''}'
              : '';
          if (name.isNotEmpty) childNames[e.toLowerCase()] = name;
        }
      }

      // Latest message per contact, decrypted.
      final latest = await ServiceLocator.messaging.getLatestMessagesPerContact();
      final byContact = <String, ({String name, String last, bool unread, DateTime time})>{};
      for (final m in latest) {
        final contact = m.sender.toLowerCase() == me.toLowerCase() ? m.receiver : m.sender;
        if (contact.isEmpty || contact.toLowerCase() == me.toLowerCase()) continue;
        final decrypted = m.message.isEmpty
            ? ''
            : await ServiceLocator.messageEncryption.decryptMessage(m.message, m.sender, m.receiver);
        final hasUnread = m.sender.toLowerCase() == contact.toLowerCase() &&
            m.receiver.toLowerCase() == me.toLowerCase() &&
            !m.isRead;
        final name = _displayName(contact, partnerEmail, partnerName, lawyerNames, childNames);
        // getLatestMessagesPerContact already returns one row per contact.
        byContact[contact.toLowerCase()] =
            (name: name, last: decrypted, unread: hasUnread, time: m.timestamp);
      }

      // Build sections.
      final coParent = <_Contact>[];
      final childContacts = <_Contact>[];
      final legalContacts = <_Contact>[];
      final otherContacts = <_Contact>[];

      if (hasPartner) {
        final data = byContact.remove(partnerEmail.toLowerCase());
        coParent.add(_Contact(
          email: partnerEmail,
          name: partnerName.isNotEmpty ? partnerName : 'Co-Parent',
          lastMessage: data?.last.isNotEmpty == true ? data!.last : 'Tap to start chatting',
          time: data != null ? _relativeTime(data.time) : '',
          avatarColor: AppColors.primaryBlue,
          hasUnread: data?.unread ?? false,
          callable: true,
        ));
      } else if (partner.valid && partner.status == 'pending_sent') {
        // Invite sent but not connected yet — show the co-parent as a pending row
        // so the section isn't empty and the user can see the invite is live.
        final pendingEmail = partner.inviterEmail ?? '';
        final status = !partner.partnerHasAccount
            ? 'Invite sent — not on CoHarmony yet'
            : !partner.partnerSubscribed
                ? 'Invite sent — joined, not subscribed'
                : 'Invite sent — awaiting accept';
        if (pendingEmail.isNotEmpty) {
          coParent.add(_Contact(
            email: pendingEmail,
            name: _nameFromEmail(pendingEmail),
            lastMessage: status,
            time: '',
            avatarColor: AppColors.warningAmber,
            hasUnread: false,
            pending: true,
          ));
        }
      }
      byContact.forEach((email, d) {
        final isChild = childEmails.contains(email);
        final isLawyer = lawyerEmails.contains(email);
        final contact = _Contact(
          email: email,
          name: d.name,
          lastMessage: d.last,
          time: _relativeTime(d.time),
          avatarColor: isChild
              ? AppColors.successGreen
              : isLawyer
                  ? AppColors.accentPurple
                  : const Color(0xFF64748B),
          hasUnread: d.unread,
          // Children are callable; lawyers and unknown "other" contacts are not.
          callable: isChild,
        );
        if (isChild) {
          childContacts.add(contact);
        } else if (isLawyer) {
          legalContacts.add(contact);
        } else {
          otherContacts.add(contact);
        }
      });

      final sections = <_ContactSection>[
        if (coParent.isNotEmpty) _ContactSection('Co-Parent', coParent),
        if (childContacts.isNotEmpty) _ContactSection('Children', childContacts),
        if (legalContacts.isNotEmpty) _ContactSection('Legal', legalContacts),
        if (otherContacts.isNotEmpty) _ContactSection('Other', otherContacts),
      ];

      if (!mounted) return;
      setState(() {
        _sections = sections;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _displayName(String email, String partnerEmail, String partnerName,
      Map<String, String> lawyerNames, Map<String, String> childNames) {
    final lower = email.toLowerCase();
    if (partnerEmail.isNotEmpty && lower == partnerEmail.toLowerCase()) {
      return partnerName.isNotEmpty ? partnerName : 'Co-Parent';
    }
    return lawyerNames[lower] ?? childNames[lower] ?? _nameFromEmail(email);
  }

  static String _nameFromEmail(String email) {
    final at = email.indexOf('@');
    final local = at > 0 ? email.substring(0, at) : email;
    final words = local.replaceAll('.', ' ').replaceAll('_', ' ').split(' ').where((w) => w.isNotEmpty);
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  static String _relativeTime(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day.weekday - 1];
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[t.month]} ${t.day}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: LoadingSwitcher(
              loading: _loading,
              skeleton: const SkeletonListTiles(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                // topCenter, not center: Center vertically-centers the column, so when
                // there are few contacts (e.g. only a co-parent) it floated to the
                // middle of the viewport, leaving a gap below the header. Top-aligning
                // keeps the content pinned under the header in every state.
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _aiCard(context),
                        const SizedBox(height: 16),
                        for (final section in _sections) ...[
                          _section(context, section),
                          const SizedBox(height: 16),
                        ],
                        _securityCard(context),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────
  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.viewPaddingOf(context).top + 12, 24, 20),
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
              Text('Stay connected securely', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  // ── AI card ─────────────────────────────────────────────────────────────────
  Widget _aiCard(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AiChatPage()),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
                offset: const Offset(0, 8),
                blurRadius: 32),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Center(child: AppIcon('icon_sparkle', size: 28, color: Colors.white)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('CoHarmony™ AI',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(8)),
                        child: const Text('AI',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Ask me anything about your schedule',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: AppIcon('icon_arrow_right', size: 18, color: AppColors.primaryBlue)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Contact section ─────────────────────────────────────────────────────────
  Widget _section(BuildContext context, _ContactSection section) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(section.title.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: palette.textSecondary, letterSpacing: 0.5)),
        ),
        for (final c in section.contacts) ...[
          _contactCard(context, c),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _contactCard(BuildContext context, _Contact c) {
    final palette = context.palette;
    final callingEnabled = Preferences.getBool('calling_enabled', true);
    return GestureDetector(
      onTap: () => c.pending ? _showPendingInfo(c) : _openChat(c),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            // Avatar → contact detail page (call history + transcripts + actions).
            GestureDetector(
              onTap: () => c.pending ? _showPendingInfo(c) : _openContact(c),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: c.avatarColor, borderRadius: BorderRadius.circular(16)),
                child: Center(
                  child: Text(_initials(c.name),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(c.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: c.hasUnread ? FontWeight.bold : FontWeight.normal,
                          color: c.hasUnread ? palette.textPrimary : palette.textSecondary)),
                ],
              ),
            ),
            // Quick call/video buttons (optional — gated by the calling setting;
            // hidden for a pending co-parent who isn't reachable yet, and for
            // non-callable contacts like lawyers).
            if (callingEnabled && !c.pending && c.callable) ...[
              _cardCallButton(
                icon: Icons.call,
                color: AppColors.accentTeal,
                onTap: () => _callContact(c, video: false),
              ),
              const SizedBox(width: 6),
              _cardCallButton(
                icon: Icons.videocam,
                color: AppColors.primaryBlue,
                onTap: () => _callContact(c, video: true),
              ),
              const SizedBox(width: 8),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(c.time, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                const SizedBox(height: 6),
                if (c.hasUnread)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: AppColors.primaryBlue, shape: BoxShape.circle),
                  )
                else
                  const SizedBox(height: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardCallButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    // Inline icon, no colored background — just the tinted glyph.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }

  Future<void> _openChat(_Contact c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatInterfacePage(contactEmail: c.email, contactName: c.name, callable: c.callable),
      ),
    );
    if (mounted) _load(silent: true); // refresh unread state on return
  }

  Future<void> _openContact(_Contact c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactDetailPage(
          contactEmail: c.email,
          contactName: c.name,
          avatarColor: c.avatarColor,
          callable: c.callable,
        ),
      ),
    );
    if (mounted) _load(silent: true);
  }

  Future<void> _callContact(_Contact c, {required bool video}) =>
      startOutgoingCall(context, c.email, contactName: c.name, video: video);

  Future<void> _showPendingInfo(_Contact c) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invitation pending'),
        content: Text(
          "${c.email} hasn't connected yet. You'll be able to message and call them "
          'once they accept your co-parent invitation.',
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
  }

  // ── Security card ─────────────────────────────────────────────────────────────
  Widget _securityCard(BuildContext context) {
    Widget point(String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppIcon('icon_checkmark', size: 16, color: Color(0xFFA7F3D0)),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFFE0F2FE)))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.infoBlue, Color(0xFF0284C7)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppColors.infoBlue.withValues(alpha: 0.3), offset: const Offset(0, 6), blurRadius: 16),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: const Color(0x30FFFFFF), borderRadius: BorderRadius.circular(12)),
                child: const Center(child: AppIcon('icon_shield_check', size: 24, color: Colors.white)),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Encrypted Messaging',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 2),
                  Text('Your messages are always secure',
                      style: TextStyle(fontSize: 13, color: Color(0xFFE0F2FE))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0x30FFFFFF)),
          point('Messages encrypted before leaving your device'),
          point('Only you and the recipient can read messages'),
          point('Attachments are also encrypted'),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

class _ContactSection {
  final String title;
  final List<_Contact> contacts;
  const _ContactSection(this.title, this.contacts);
}

class _Contact {
  final String email;
  final String name;
  final String lastMessage;
  final String time;
  final Color avatarColor;
  final bool hasUnread;
  /// A co-parent who was invited but hasn't connected yet — shown as a status
  /// row (no chat / no call until they accept).
  final bool pending;

  /// Whether voice/video calling is offered for this contact. Co-parents and
  /// children are callable; lawyers (and other/unknown contacts) are NOT — calling
  /// is a family feature, not a legal-communication channel.
  final bool callable;

  const _Contact({
    required this.email,
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.avatarColor,
    required this.hasUnread,
    this.pending = false,
    this.callable = false,
  });
}
