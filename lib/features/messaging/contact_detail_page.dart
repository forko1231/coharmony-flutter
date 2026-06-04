import 'package:flutter/material.dart';

import '../../models/call_models.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../calling/call_actions.dart';
import 'chat_interface_page.dart';

/// Contact hub — reached by tapping a contact's avatar in the Messages list.
/// Shows quick actions (message / voice / video) and the full call history with
/// transcripts for this contact.
class ContactDetailPage extends StatefulWidget {
  const ContactDetailPage({
    super.key,
    required this.contactEmail,
    required this.contactName,
    this.avatarColor = AppColors.primaryBlue,
  });

  final String contactEmail;
  final String contactName;
  final Color avatarColor;

  @override
  State<ContactDetailPage> createState() => _ContactDetailPageState();
}

class _ContactDetailPageState extends State<ContactDetailPage> {
  bool _loading = true;
  List<CallSession> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final history = await ServiceLocator.calling.getCallHistory(widget.contactEmail);
      history.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
      if (mounted) {
        setState(() {
          _history = history;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatInterfacePage(
          contactEmail: widget.contactEmail,
          contactName: widget.contactName,
        ),
      ),
    );
  }

  Future<void> _call({required bool video}) async {
    await startOutgoingCall(context, widget.contactEmail, video: video);
    if (mounted) _load(); // refresh history after the call
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final callingEnabled = Preferences.getBool('calling_enabled', true);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        title: Text(widget.contactName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: widget.avatarColor,
                  child: Text(
                    _initials(widget.contactName),
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                Text(widget.contactName,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 4),
                Text(widget.contactEmail, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Quick actions
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionButton(
                icon: Icons.chat_bubble_outline,
                label: 'Message',
                color: AppColors.primaryBlue,
                onTap: _openChat,
              ),
              if (callingEnabled) ...[
                const SizedBox(width: 20),
                _ActionButton(
                  icon: Icons.call,
                  label: 'Voice',
                  color: AppColors.accentTeal,
                  onTap: () => _call(video: false),
                ),
                const SizedBox(width: 20),
                _ActionButton(
                  icon: Icons.videocam,
                  label: 'Video',
                  color: AppColors.successGreen,
                  onTap: () => _call(video: true),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),

          Text('Call History',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 8),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No calls yet', style: TextStyle(color: palette.textSecondary)),
              ),
            )
          else
            for (final session in _history) _CallRow(session: session),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, color: context.palette.textSecondary)),
        ],
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.session});
  final CallSession session;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final missed = session.isMissed;
    final icon = session.hasVideo ? Icons.videocam : Icons.call;
    final iconColor = missed ? AppColors.dangerRed : AppColors.successGreen;
    final subtitle = _subtitle();
    final transcript = session.transcript;

    final leading = CircleAvatar(
      backgroundColor: iconColor.withValues(alpha: 0.15),
      child: Icon(icon, color: iconColor, size: 20),
    );

    if (transcript == null || transcript.isEmpty) {
      return Card(
        color: palette.surfaceElevated,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: leading,
          title: Text(_title(), style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: TextStyle(color: palette.textSecondary, fontSize: 12)),
        ),
      );
    }

    return Card(
      color: palette.surfaceElevated,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: leading,
          title: Text(_title(), style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600)),
          subtitle: Row(
            children: [
              Expanded(child: Text(subtitle, style: TextStyle(color: palette.textSecondary, fontSize: 12))),
              const Icon(Icons.text_snippet_outlined, size: 14, color: AppColors.infoBlue),
              const SizedBox(width: 4),
              const Text('Transcript', style: TextStyle(fontSize: 11, color: AppColors.infoBlue)),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(transcript, style: TextStyle(color: palette.textPrimary, fontSize: 13, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }

  String _title() {
    if (session.status == 'missed') return 'Missed call';
    if (session.status == 'rejected') return 'Declined call';
    return session.hasVideo ? 'Video call' : 'Voice call';
  }

  String _subtitle() {
    final d = session.createdAt.toLocal();
    final date = '${d.month}/${d.day}/${d.year}';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final time = '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    final dur = session.duration;
    if (dur != null) {
      final m = dur.inMinutes;
      final s = dur.inSeconds % 60;
      return '$date · $time · ${m}m ${s}s';
    }
    return '$date · $time';
  }
}
