import 'package:flutter/material.dart';
import '../../models/auth_models.dart';
import '../../models/custody_models.dart';
import '../../models/message_models.dart';
import '../../services/holiday_resolver.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../calling/call_permissions_primer.dart';
import '../messaging/chat_interface_page.dart';
import 'child_family_page.dart';
import 'child_settings_page.dart';

/// Port of `Views/Child/ChildMainMenu.xaml(.cs)` — the child dashboard: today's
/// custody + next change, a custody-shaded mini-month, parent message previews, and a
/// family card. Read-only (children can't edit the schedule).
class ChildMainMenu extends StatefulWidget {
  /// Switch the child shell to the Schedule tab ("View All").
  final VoidCallback? onViewSchedule;
  const ChildMainMenu({super.key, this.onViewSchedule});

  @override
  State<ChildMainMenu> createState() => _ChildMainMenuState();
}

class _ChildMainMenuState extends State<ChildMainMenu> {
  bool _loading = true;
  String _email = '';
  ApprovedScheduleResponse? _approved;
  FamilyInfo? _family;
  List<MessageContent> _messages = const [];

  final _now = DateTime.now();

  static const _husband = Color.fromARGB(128, 173, 216, 230);
  static const _wife = Color.fromARGB(128, 255, 182, 193);
  static const _both = Color.fromARGB(128, 147, 112, 219);
  static const _monthsLong = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _load();
    ServiceLocator.push.init(); // FCM token register (Android only; no-op on iOS)
    ServiceLocator.callKit.registerVoipToken(); // iOS VoIP token register (no-op on Android)
    ServiceLocator.messaging.onMessageReceived.listen((_) {
      if (mounted) _loadMessages();
    });
    // Prime calling permissions (mic + Android notification/full-screen) so the
    // child can receive a parent's call. One-time; gated inside.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowCallPermissionsPrimer(context);
    });
  }

  Future<void> _load() async {
    _email = Preferences.getString('email');
    try {
      _approved = await ServiceLocator.liveSchedule.getApprovedSchedule();
    } catch (_) {}
    await Future.wait([_loadFamily(), _loadMessages()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadFamily() async {
    try {
      _family = await ServiceLocator.auth.getFamilyInfo();
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    try {
      await ServiceLocator.messaging.initializeWebSocket();
      final raw = await ServiceLocator.messaging.getLatestMessagesPerContact();
      final decrypted = <MessageContent>[];
      for (final m in raw) {
        final text = m.message.isEmpty
            ? ''
            : await ServiceLocator.messageEncryption.decryptMessage(m.message, m.sender, m.receiver);
        decrypted.add(MessageContent(
            sender: m.sender, receiver: m.receiver, message: text, timestamp: m.timestamp, isRead: m.isRead));
      }
      _messages = decrypted;
      if (mounted) setState(() {});
    } catch (_) {
      _messages = const [];
    }
  }

  // ── Custody resolution (approved only) ───────────────────────────────────────
  Map<String, ApprovedOverrideDto> get _overrideLookup {
    final lookup = <String, ApprovedOverrideDto>{};
    for (final ovr in _approved?.overrides ?? const <ApprovedOverrideDto>[]) {
      if (ovr.holidayRule?.isNotEmpty ?? false) {
        final resolved = HolidayResolver.resolveDate(ovr.holidayRule, _now.year);
        if (resolved != null) lookup['${_pad(resolved.month)}-${_pad(resolved.day)}'] = ovr;
      } else {
        lookup['${_pad(ovr.month)}-${_pad(ovr.day)}'] = ovr;
      }
    }
    return lookup;
  }

  ({String parent, String? time, String? endTime}) _custodyFor(DateTime date, Map<String, ApprovedOverrideDto> lookup) {
    final ovr = lookup['${_pad(date.month)}-${_pad(date.day)}'];
    if (ovr != null) {
      var effective = ovr.parentAssignment;
      if (ovr.isAnnual && ovr.alternationMode == 'alternating' && (ovr.alternationStartParent?.isNotEmpty ?? false)) {
        final isOddYear = _now.year % 2 != 0;
        final start = ovr.alternationStartParent!;
        effective = isOddYear ? start : (start == 'Husband' ? 'Wife' : 'Husband');
      }
      if (effective != 'None') return (parent: effective, time: ovr.transferTime, endTime: ovr.transferEndTime);
    }
    final days = _approved?.days ?? const <ApprovedDayDto>[];
    if (days.isNotEmpty) {
      final patternLength = _approved?.patternLength ?? 1;
      final dayIndex = date.weekday % 7;
      final week = patternLength <= 1 ? 0 : _calcWeek(date, patternLength);
      for (final d in days) {
        if (d.dayIndex == dayIndex && d.weekIndex == week) {
          return (parent: d.parentAssignment, time: d.transferTime, endTime: d.transferEndTime);
        }
      }
    }
    return (parent: 'None', time: null, endTime: null);
  }

  int _calcWeek(DateTime date, int patternLength) {
    final patternStart = DateTime(_now.year, _now.month, 1);
    final refSunday = patternStart.subtract(Duration(days: patternStart.weekday % 7));
    final targetSunday = DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday % 7));
    var weeks = targetSunday.difference(refSunday).inDays ~/ 7;
    if (weeks < 0) weeks += ((weeks.abs() ~/ patternLength) + 1) * patternLength;
    return weeks % patternLength;
  }

  static String _parentLabel(String p) => switch (p.toLowerCase()) {
        'husband' => 'Parent 1 (Dad)',
        'wife' => 'Parent 2 (Mom)',
        'both' => 'Both Parents',
        _ => 'Unknown',
      };

  String _todayCustody() {
    final c = _custodyFor(DateTime(_now.year, _now.month, _now.day), _overrideLookup);
    return c.parent == 'None' ? 'No schedule' : 'With ${_parentLabel(c.parent)}';
  }

  String _nextChange() {
    if (!(_approved?.hasSchedule ?? false)) return 'No events';
    final lookup = _overrideLookup;
    final today = DateTime(_now.year, _now.month, _now.day);
    for (int i = 1; i <= 7; i++) {
      final future = today.add(Duration(days: i));
      final futureC = _custodyFor(future, lookup).parent;
      final prevC = _custodyFor(future.subtract(const Duration(days: 1)), lookup).parent;
      if (futureC != prevC && futureC != 'None') {
        return '${_weekday(future)} — ${_parentLabel(futureC)}';
      }
    }
    return 'No changes';
  }

  // ── Parent message previews ──────────────────────────────────────────────────
  List<_ParentMsg> _parentMessages() {
    final f = _family;
    if (f == null) return const [];
    final parents = <String>[
      if (f.parent1Email?.isNotEmpty ?? false) f.parent1Email!,
      if (f.parent2Email?.isNotEmpty ?? false) f.parent2Email!,
    ];
    return [
      for (final pe in parents)
        () {
          MessageContent? latest;
          for (final m in _messages) {
            final between = (m.sender.toLowerCase() == pe.toLowerCase() && m.receiver.toLowerCase() == _email.toLowerCase()) ||
                (m.sender.toLowerCase() == _email.toLowerCase() && m.receiver.toLowerCase() == pe.toLowerCase());
            if (between && (latest == null || m.timestamp.isAfter(latest.timestamp))) latest = m;
          }
          final hasUnread = latest != null && latest.sender.toLowerCase() == pe.toLowerCase() && !latest.isRead;
          return _ParentMsg(
            email: pe,
            name: _parentName(pe),
            preview: latest != null ? _truncate(latest.message.isEmpty ? 'No message' : latest.message, 30) : 'No messages yet',
            ts: latest?.timestamp,
            hasUnread: hasUnread,
          );
        }(),
    ];
  }

  String _parentName(String email) {
    final f = _family;
    if (f != null) {
      if ((f.parent1Email?.toLowerCase() == email.toLowerCase()) && (f.parent1Name?.isNotEmpty ?? false)) return f.parent1Name!;
      if ((f.parent2Email?.toLowerCase() == email.toLowerCase()) && (f.parent2Name?.isNotEmpty ?? false)) return f.parent2Name!;
    }
    final at = email.indexOf('@');
    return at > 0 ? email[0].toUpperCase() + email.substring(1, at) : email;
  }

  // ── helpers ───────────────────────────────────────────────────────────────────
  static String _pad(int n) => n.toString().padLeft(2, '0');
  static String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 3)}...';
  static String _weekday(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
  static String _monthAbbr(int m) => _monthsLong[m - 1].substring(0, 3);
  String _ts(DateTime t) {
    final local = t.toLocal();
    final today = DateTime(_now.year, _now.month, _now.day);
    final d = DateTime(local.year, local.month, local.day);
    if (d == today) {
      final ampm = local.hour < 12 ? 'AM' : 'PM';
      var dh = local.hour % 12;
      if (dh == 0) dh = 12;
      return '$dh:${_pad(local.minute)} $ampm';
    }
    if (local.year == _now.year) return '${_monthAbbr(local.month)} ${local.day}';
    return '${_monthAbbr(local.month)} ${local.day}, ${local.year}';
  }

  static TimeOfDay? _parseTod(String? s) {
    if (s == null || s.isEmpty || s == '00:00') return null;
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static List<double> _stops(List<double> raw) {
    final out = <double>[];
    double prev = 0;
    for (final v in raw) {
      var c = v.clamp(0.0, 1.0);
      if (c < prev) c = prev;
      out.add(c);
      prev = c;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          Container(
            // Top inset accounts for the status bar / Dynamic Island (was a fixed 20).
            padding: EdgeInsets.fromLTRB(24, MediaQuery.viewPaddingOf(context).top + 14, 24, 20),
            color: palette.surface,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChildSettingsPage())),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(child: AppIcon('icon_settings', size: 24, color: palette.textSecondary)),
                    ),
                  ),
                ),
                Text('Dashboard',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                      child: _statCard(context, 'icon_calendar', AppColors.iconBgBlue,
                                          AppColors.primaryBlue, 'Today', _todayCustody())),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: _statCard(context, 'icon_clock', AppColors.iconBgYellow,
                                          AppColors.warningAmber, 'Next Change', _nextChange())),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _calendarCard(context),
                              const SizedBox(height: 20),
                              _messagesCard(context),
                              const SizedBox(height: 20),
                              _familyCard(context),
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

  Widget _statCard(BuildContext context, String icon, Color bg, Color tint, String label, String value) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Center(child: AppIcon(icon, size: 24, color: tint)),
          ),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        ],
      ),
    );
  }

  Widget _calendarCard(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Calendar',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    const SizedBox(height: 4),
                    Text('${_monthsLong[_now.month - 1]} ${_now.year}',
                        style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: widget.onViewSchedule,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('View All →',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                ),
              ),
            ],
          ),
          // Was 20 — matched to the parent main menu so the weekday row sits right under the header.
          const SizedBox(height: 8),
          _miniMonth(context),
        ],
      ),
    );
  }

  Widget _miniMonth(BuildContext context) {
    final palette = context.palette;
    final lookup = _overrideLookup;
    final daysInMonth = DateTime(_now.year, _now.month + 1, 0).day;
    final firstWeekday = DateTime(_now.year, _now.month, 1).weekday % 7;
    const headers = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    // Day cells only (NO weekday labels in the grid — they go in a compact Row above it).
    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_now.year, _now.month, d);
      final custody = _custodyFor(date, lookup);
      final isToday = d == _now.day;
      cells.add(Container(
        decoration: _custodyDecoration(custody).copyWith(
          border: isToday ? Border.all(color: AppColors.primaryBlue, width: 3) : Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text('$d',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: palette.textPrimary)),
        ),
      ));
    }

    // Copied from the parent main menu's _miniMonth.
    return Column(
      children: [
        Row(
          children: headers
              .map((h) => Expanded(
                  child: Center(
                      child: Text(h,
                          style: TextStyle(
                              fontSize: 12, height: 1.0, fontWeight: FontWeight.bold, color: palette.textSecondary)))))
              .toList(),
        ),
        const SizedBox(height: 2),
        // Explicit zero padding — otherwise GridView applies the ambient MediaQuery top inset
        // (status bar / Dynamic Island), injecting a tall gap between the weekday row and the grid.
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: cells.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 44,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemBuilder: (_, i) => cells[i],
        ),
      ],
    );
  }

  BoxDecoration _custodyDecoration(({String parent, String? time, String? endTime}) custody) {
    final parent = custody.parent.toLowerCase();
    Color base;
    switch (parent) {
      case 'husband':
        base = _husband;
        break;
      case 'wife':
        base = _wife;
        break;
      case 'both':
        base = _both;
        break;
      default:
        return const BoxDecoration();
    }
    final start = _parseTod(custody.time);
    final end = _parseTod(custody.endTime);
    if (start != null && parent != 'both') {
      final startP = ((start.hour * 60 + start.minute) / 1440).clamp(0.0, 1.0);
      final to = parent == 'husband' ? _wife : _husband;
      if (end != null && (end.hour * 60 + end.minute) > (start.hour * 60 + start.minute)) {
        final endP = ((end.hour * 60 + end.minute) / 1440).clamp(0.0, 1.0);
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [base, base, to, to, base, base],
            stops: _stops([0, startP - 0.001, startP, endP, endP + 0.001, 1]),
          ),
        );
      }
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [base, base, to, to],
          stops: _stops([0, startP - 0.001, startP, 1]),
        ),
      );
    }
    return BoxDecoration(color: base);
  }

  Widget _messagesCard(BuildContext context) {
    final palette = context.palette;
    final contacts = _parentMessages();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Messages',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    Text('Recent conversations', style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(12)),
                child: const Center(child: AppIcon('icon_chat', size: 24, color: AppColors.primaryBlue)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (contacts.isEmpty)
            Text('No conversations yet', style: TextStyle(fontSize: 14, color: palette.textSecondary))
          else
            for (final c in contacts) ...[
              _contactRow(context, c),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _contactRow(BuildContext context, _ParentMsg c) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatInterfacePage(contactEmail: c.email, contactName: c.name)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(20)),
              child: Center(
                  child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
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
            const SizedBox(width: 8),
            if (c.ts != null) Text(_ts(c.ts!), style: TextStyle(fontSize: 12, color: palette.textMuted)),
            if (c.hasUnread) ...[
              const SizedBox(width: 8),
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(color: AppColors.primaryBlue, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _familyCard(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.iconBgPurple, borderRadius: BorderRadius.circular(16)),
            child: const Center(child: AppIcon('icon_users', size: 28, color: AppColors.accentPurple)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Family',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                Text('View family members', style: TextStyle(fontSize: 14, color: palette.textSecondary)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChildFamilyPage())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('View →',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParentMsg {
  _ParentMsg({required this.email, required this.name, required this.preview, required this.ts, required this.hasUnread});
  final String email;
  final String name;
  final String preview;
  final DateTime? ts;
  final bool hasUnread;
}
