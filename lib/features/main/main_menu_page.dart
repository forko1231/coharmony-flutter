import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/custody_models.dart';
import '../../models/financial_models.dart';
import '../../models/location_models.dart';
import '../../models/message_models.dart';
import '../../models/schedule_models.dart';
import '../../services/analytics_service.dart';
import '../../services/custody_templates/pending_template_service.dart';
import '../../services/holiday_resolver.dart';
import '../../services/preferences.dart';
import '../../services/live_schedule_service.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/skeleton.dart';
import '../ai/ai_chat_page.dart';
import '../calling/call_permissions_primer.dart';
import '../filevault/file_vault_page.dart';
import '../messaging/chat_interface_page.dart';
import '../schedule/live_schedule_page.dart';
import '../schedule/date_data_page.dart';
import '../shell/app_shell.dart';
import '../subscription/subscription_page.dart';
import 'partner_page.dart';
import 'settings_page.dart';

/// Dashboard / Home — port of `Views/Main/MainMenu.xaml(.cs)`. Loads partner / lawyer /
/// children contacts, schedule events, custody (live schedule), charges, messages and
/// location records, then renders quick stats, a custody-shaded mini-calendar, upcoming
/// events, a payment summary, recent conversations, co-parent status and location stats.
class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  bool _loading = true;
  bool _loadFailed = false; // transport failure during the last load → show the banner
  String _email = '';
  StreamSubscription<MessageReceivedEvent>? _msgSub;

  ApprovedScheduleResponse? _approved;
  LiveAgreement? _agreement;
  List<ScheduleItem> _events = const [];
  List<FCharge> _monthCharges = const []; // all charges in current month (calendar borders)
  List<FCharge> _userMonthCharges = const []; // current user's charges (payment summary)
  List<MessageContent> _messages = const [];
  List<LocationRecord> _locations = const [];

  bool _partnerSynced = false;
  bool _partnerPending = false; // invite sent, awaiting the co-parent
  String _partnerName = '';
  String _partnerEmail = '';
  final Set<String> _lawyerEmails = {};
  final Map<String, String> _contactNames = {};

  double _verified = 0, _pending = 0, _overdue = 0;

  final _now = DateTime.now();

  static const _husband = Color.fromARGB(128, 173, 216, 230);
  static const _wife = Color.fromARGB(128, 255, 182, 193);
  static const _both = Color.fromARGB(128, 147, 112, 219);

  @override
  void initState() {
    super.initState();
    _load();
    ServiceLocator.push.init(); // FCM token register (Android only; no-op on iOS)
    ServiceLocator.callKit.registerVoipToken(); // iOS VoIP token register (no-op on Android)
    _msgSub = ServiceLocator.messaging.onMessageReceived.listen((_) {
      if (mounted) _loadMessages();
    });
    // First time on the dashboard after onboarding/subscription: prime calling
    // permissions so incoming calls (which may arrive while killed/locked, where
    // the OS can't prompt) can be answered. One-time; gated inside.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowCallPermissionsPrimer(context);
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _email = Preferences.getString('email');
    // Track transport failures across the whole load: the fetches run
    // concurrently, so the notifier's final value alone could be masked by a
    // late success. Any TRUE during the load means data may be missing.
    final net = ServiceLocator.api.hadTransportFailure;
    var sawNetFailure = false;
    void trackNet() {
      if (net.value) sawNetFailure = true;
    }
    net.addListener(trackNet);
    await Future.wait([
      _loadPartner(),
      _loadLawyers(),
      _loadChildren(),
    ]);
    await Future.wait([
      _loadSchedule(),
      _loadCustody(),
      _loadCharges(),
      _loadMessages(),
      _loadLocations(),
    ]);
    net.removeListener(trackNet);
    _loadFailed = sawNetFailure || net.value;
    if (mounted) setState(() => _loading = false);
    unawaited(_maybePostJoinSchedulePrompt());
  }

  /// Port of MAUI's `MaybeShowPostJoinSchedulePromptAsync` (called from MainMenu):
  /// for an already-onboarded user whose co-parent finally joined and who has no
  /// schedule yet, offer to set one up now. One-shot (the router flips the flag).
  Future<void> _maybePostJoinSchedulePrompt() async {
    bool show;
    try {
      show = await ServiceLocator.onboardingRouter.shouldPromptPostJoinSchedule();
    } catch (_) {
      return;
    }
    if (!show || !mounted) return;
    final wantsNow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your co-parent joined!'),
        content: const Text(
            'Now you can set up your custody schedule together. Want to do that now?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Later')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Set it up')),
        ],
      ),
    );
    if (wantsNow == true) {
      AnalyticsService.trackCustom('post_join_schedule_prompt_accepted');
      PendingTemplateService.clear();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveSchedulePage()));
      if (mounted) _load();
    } else {
      AnalyticsService.trackCustom('post_join_schedule_prompt_dismissed');
    }
  }

  Future<void> _loadPartner() async {
    try {
      final info = await ServiceLocator.auth.checkForInvite();
      _partnerSynced = info.synced;
      _partnerPending = info.valid && !info.synced && info.status == 'pending_sent';
      if (info.synced) {
        _partnerEmail = info.inviterEmail ?? '';
        _partnerName = (info.inviterName?.isNotEmpty ?? false) ? info.inviterName! : _nameFromEmail(_partnerEmail);
        await Preferences.setString('partnerEmail', _partnerEmail);
        if (_partnerEmail.isNotEmpty) _contactNames[_partnerEmail.toLowerCase()] = _partnerName;
      } else if (_partnerPending) {
        _partnerEmail = info.inviterEmail ?? '';
      }
    } catch (_) {}
  }

  Future<void> _loadLawyers() async {
    try {
      final lawyers = await ServiceLocator.auth.getApprovedLawyers();
      for (final l in lawyers) {
        final email = l.lawyerEmail ?? '';
        if (email.isNotEmpty) {
          _lawyerEmails.add(email.toLowerCase());
          final name = l.lawyerName ?? '';
          if (name.isNotEmpty) _contactNames[email.toLowerCase()] = name;
        }
      }
    } catch (_) {}
  }

  Future<void> _loadChildren() async {
    try {
      final children = await ServiceLocator.auth.getChildren();
      for (final c in children) {
        final email = c.email ?? '';
        if (email.isNotEmpty) {
          final name = '${c.firstName ?? ''} ${c.lastName ?? ''}'.trim();
          if (name.isNotEmpty) _contactNames[email.toLowerCase()] = name;
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSchedule() async {
    try {
      final all = await ServiceLocator.schedule.getScheduleOptimized(_now.month, _now.year);
      _events = all.where((s) => !s.isCustodial).toList();
    } catch (_) {
      _events = const [];
    }
  }

  Future<void> _loadCustody() async {
    try {
      _approved = await ServiceLocator.liveSchedule.getApprovedSchedule();
      _agreement = await ServiceLocator.liveSchedule.getAgreement();
    } catch (_) {}
  }

  Future<void> _loadCharges() async {
    try {
      final monthStart = DateTime(_now.year, _now.month, 1);
      final all = await ServiceLocator.financial.getCharges(date: monthStart);
      _monthCharges = all;
      _userMonthCharges =
          all.where((c) => (c.email ?? '').toLowerCase() == _email.toLowerCase()).toList();
      double share(FCharge c) =>
          (c.isSplitPayment && c.splitPercentage != null) ? c.amount * (c.splitPercentage! / 100) : c.amount;
      final today = DateTime(_now.year, _now.month, _now.day);
      _verified = _userMonthCharges.where((c) => c.paymentStatus == 'verified').fold(0.0, (s, c) => s + share(c));
      _pending = _userMonthCharges
          .where((c) =>
              c.paymentStatus == 'pending_verification' ||
              (c.paymentStatus == 'unpaid' && c.date != null && !c.date!.isBefore(today)))
          .fold(0.0, (s, c) => s + share(c));
      _overdue = _userMonthCharges
          .where((c) => c.paymentStatus == 'unpaid' && c.date != null && c.date!.isBefore(today))
          .fold(0.0, (s, c) => s + share(c));
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
          sender: m.sender,
          receiver: m.receiver,
          message: text,
          timestamp: m.timestamp,
          isRead: m.isRead,
        ));
      }
      _messages = decrypted;
      if (mounted) setState(() {});
    } catch (_) {
      _messages = const [];
    }
  }

  Future<void> _loadLocations() async {
    try {
      final (records, _) = await ServiceLocator.location.getLocationRecords(page: 1, pageSize: 10);
      _locations = records;
    } catch (_) {
      _locations = const [];
    }
  }

  // ── Custody resolution (approved schedule pattern + overrides) ───────────────
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
      final week = LiveScheduleService.weekIndexFor(date, patternLength, _approved?.patternAnchorDate);
      for (final d in days) {
        if (d.dayIndex == dayIndex && d.weekIndex == week) {
          return (parent: d.parentAssignment, time: d.transferTime, endTime: d.transferEndTime);
        }
      }
    }
    return (parent: 'None', time: null, endTime: null);
  }

  // ── Today custody + next event ───────────────────────────────────────────────
  String _todayCustody() {
    final c = _custodyFor(DateTime(_now.year, _now.month, _now.day), _overrideLookup);
    if (c.parent == 'None') return 'Your Day';
    final t = _parseTod(c.time);
    if (t != null) {
      final who = c.parent == 'Husband' ? 'Dad' : (c.parent == 'Wife' ? 'Mom' : 'Parent');
      return '$who @ ${_fmtTime(t)}';
    }
    return switch (c.parent) {
      'Husband' => "Dad's Day",
      'Wife' => "Mom's Day",
      'Both' => 'Shared Day',
      _ => 'Your Day',
    };
  }

  String _nextEvent() {
    final occ = _occurrences();
    if (occ.isEmpty) return 'No events';
    final next = occ.first;
    final today = DateTime(_now.year, _now.month, _now.day);
    final name = _truncate(next.item.tag, 12);
    final d = next.date;
    if (d == today) return '$name today';
    if (d == today.add(const Duration(days: 1))) return '$name tomorrow';
    if (d.isBefore(today.add(const Duration(days: 7)))) return '$name ${_weekday(d)}';
    return '$name ${_monthAbbr(d.month)} ${d.day}';
  }

  List<({ScheduleItem item, DateTime date})> _upcoming() => _occurrences().take(5).toList();

  /// Upcoming event occurrences within [horizonDays], expanding recurring events
  /// (daily/weekly/biweekly/monthly/quarterly/yearly/biyearly) so a repeating
  /// event seeded in the past still surfaces — mirrors MAUI's recurrence expansion.
  List<({ScheduleItem item, DateTime date})> _occurrences({int horizonDays = 90}) {
    final today = DateTime(_now.year, _now.month, _now.day);
    final out = <({ScheduleItem item, DateTime date})>[];
    for (final s in _events) {
      if (s.tag.isEmpty) continue;
      final orig = DateTime(s.year, s.month, s.day);
      final repeats = s.repeatType.isNotEmpty && s.repeatType.toLowerCase() != 'none';
      if (!repeats) {
        if (!orig.isBefore(today)) out.add((item: s, date: orig));
        continue;
      }
      for (int i = 0; i <= horizonDays; i++) {
        final day = today.add(Duration(days: i));
        if (_eventRepeatsOn(s, day)) out.add((item: s, date: day));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// True if any event lands on [date] — its seeded date OR a recurrence. Used for the
  /// mini-calendar dots, which previously only matched the exact seeded date (so repeating
  /// events showed a dot on their first day only).
  bool _eventOccursOn(DateTime date) {
    for (final s in _events) {
      if (s.tag.isEmpty) continue;
      if (s.year == date.year && s.month == date.month && s.day == date.day) return true;
      final rt = s.repeatType;
      if (rt.isNotEmpty && rt.toLowerCase() != 'none' && _eventRepeatsOn(s, date)) return true;
    }
    return false;
  }

  bool _eventRepeatsOn(ScheduleItem s, DateTime target) {
    final orig = DateTime(s.year, s.month, s.day);
    if (target.isBefore(orig)) return false;
    if (s.endDate != null && target.isAfter(s.endDate!)) return false;
    switch (s.repeatType.toLowerCase()) {
      case 'daily':
        return true;
      case 'weekly':
        return target.weekday == orig.weekday;
      case 'biweekly':
        return target.weekday == orig.weekday && (target.difference(orig).inDays ~/ 7) % 2 == 0;
      case 'monthly':
        return target.day == orig.day;
      case 'quarterly':
        return target.day == orig.day && ((target.year - orig.year) * 12 + (target.month - orig.month)) % 3 == 0;
      case 'yearly':
        return target.day == orig.day && target.month == orig.month;
      case 'biyearly':
        return target.day == orig.day && target.month == orig.month && (target.year - orig.year) % 2 == 0;
      default:
        return false;
    }
  }

  // ── Message contacts ─────────────────────────────────────────────────────────
  List<_ContactMsg> _contacts() {
    final byContact = <String, MessageContent>{};
    for (final m in _messages) {
      final contact = m.sender.toLowerCase() == _email.toLowerCase() ? m.receiver : m.sender;
      if (contact.isEmpty || contact.toLowerCase() == _email.toLowerCase()) continue;
      final key = contact.toLowerCase();
      final existing = byContact[key];
      if (existing == null || m.timestamp.isAfter(existing.timestamp)) byContact[key] = m;
    }
    final list = byContact.entries.map((e) {
      final email = e.key;
      final isCoParent = _partnerEmail.isNotEmpty && email == _partnerEmail.toLowerCase();
      final isLawyer = _lawyerEmails.contains(email);
      return _ContactMsg(
        email: e.value.sender.toLowerCase() == _email.toLowerCase() ? e.value.receiver : e.value.sender,
        name: _displayName(email),
        preview: _truncate(e.value.message.isEmpty ? 'No message' : e.value.message, 30),
        ts: e.value.timestamp,
        isCoParent: isCoParent,
        isLawyer: isLawyer,
      );
    }).toList()
      ..sort((a, b) {
        if (a.isCoParent != b.isCoParent) return a.isCoParent ? -1 : 1;
        if (a.isLawyer != b.isLawyer) return a.isLawyer ? -1 : 1;
        return b.ts.compareTo(a.ts);
      });
    return list.take(4).toList();
  }

  String _displayName(String emailLower) {
    final n = _contactNames[emailLower];
    if (n != null && n.trim().isNotEmpty) return n;
    return _nameFromEmail(emailLower);
  }

  Color _avatarColor(_ContactMsg c) {
    if (c.isCoParent) return AppColors.primaryBlue;
    if (c.isLawyer) return const Color(0xFF8B5CF6);
    const colors = [Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFF6366F1), Color(0xFFEC4899)];
    return colors[c.email.hashCode.abs() % colors.length];
  }

  // ── helpers ─────────────────────────────────────────────────────────────────
  static String _pad(int n) => n.toString().padLeft(2, '0');
  static String _nameFromEmail(String email) {
    final at = email.indexOf('@');
    final local = at > 0 ? email.substring(0, at) : email;
    final words = local.replaceAll('.', ' ').replaceAll('_', ' ').split(' ').where((w) => w.isNotEmpty);
    return words.isEmpty ? email : words.map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  static String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 3)}...';

  static TimeOfDay? _parseTod(String? s) {
    if (s == null || s.isEmpty || s == '00:00') return null;
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _fmtTime(TimeOfDay t) {
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    var dh = t.hour % 12;
    if (dh == 0) dh = 12;
    return '$dh:${t.minute.toString().padLeft(2, '0')} $ampm';
  }

  static const _monthsLong = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static String _monthAbbr(int m) => _monthsLong[m - 1].substring(0, 3);
  static String _weekday(DateTime d) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
  String _ts(DateTime t) {
    final local = t.toLocal();
    final today = DateTime(_now.year, _now.month, _now.day);
    final d = DateTime(local.year, local.month, local.day);
    if (d == today) return _fmtTime(TimeOfDay(hour: local.hour, minute: local.minute));
    if (local.year == _now.year) return '${_monthAbbr(local.month)} ${local.day}';
    return '${_monthAbbr(local.month)} ${local.day}, ${local.year}';
  }

  void _goToTab(int i) => AppShellScope.of(context)?.goToTab(i);

  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            color: palette.surface,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.viewPaddingOf(context).top + 12, 24, 20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                          child: AppIcon('icon_settings',
                              size: 24, color: context.isDark ? const Color(0xFFD1D5DB) : const Color(0xFF374151))),
                    ),
                  ),
                ),
                Text('Dashboard',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              ],
            ),
          ),
          Expanded(
            child: LoadingSwitcher(
              loading: _loading,
              skeleton: const SkeletonDashboard(),
              child: RefreshIndicator(
                    onRefresh: () async {
                      setState(() => _loading = false);
                      await _load();
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      child: Column(
                        children: [
                          if (_loadFailed) ...[
                            _offlineBanner(context),
                            const SizedBox(height: 16),
                          ],
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _statCard(context, 'icon_calendar', AppColors.iconBgBlue, AppColors.primaryBlue, 'Today', _todayCustody())),
                                const SizedBox(width: 12),
                                Expanded(child: _statCard(context, 'icon_clock', AppColors.iconBgYellow, AppColors.warningAmber, 'Next Event', _nextEvent())),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _calendarCard(context),
                          const SizedBox(height: 20),
                          _upcomingCard(context),
                          const SizedBox(height: 20),
                          _paymentsCard(context),
                          const SizedBox(height: 20),
                          _messagesCard(context),
                          const SizedBox(height: 20),
                          _coParentCard(context),
                          const SizedBox(height: 20),
                          _locationCard(context),
                          const SizedBox(height: 20),
                          _quickAccessCard(context),
                        ],
                      ),
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Cards ─────────────────────────────────────────────────────────────────────
  /// Slim non-blocking banner shown when the last load hit a transport failure
  /// (offline/timeout) — without it a network blip renders as "you have no
  /// data". Tap (or pull down) to retry; a clean load clears it.
  Widget _offlineBanner(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () {
        setState(() {
          _loading = true;
          _loadFailed = false;
        });
        _load();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: palette.errorBg,
          border: Border.all(color: AppColors.dangerRed.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const AppIcon('icon_warning', size: 20, color: AppColors.dangerRed),
            const SizedBox(width: 10),
            Expanded(
              child: Text("Couldn't reach the server — pull down or tap to retry",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            ),
            const SizedBox(width: 10),
            const AppIcon('icon_refresh', size: 18, color: AppColors.dangerRed),
          ],
        ),
      ),
    );
  }

  Widget _calendarCard(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Calendar',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                        // Little red dot when you haven't agreed to the current schedule yet.
                        if (_agreement?.needsMyAgreement ?? false) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(color: AppColors.dangerRed, shape: BoxShape.circle),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${_monthsLong[_now.month - 1]} ${_now.year}',
                        style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _goToTab(1),
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
    final leading = DateTime(_now.year, _now.month, 1).weekday % 7;
    const headers = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    final cells = <Widget>[];
    for (int i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_now.year, _now.month, day);
      final custody = _custodyFor(date, lookup);
      final charges = _monthCharges.where((c) {
        final d = c.date;
        return d != null && d.year == _now.year && d.month == _now.month && d.day == day;
      });
      final hasCharge = charges.isNotEmpty;
      final anyUnpaid = charges.any((c) => !c.isPaid);
      final hasEvent = _eventOccursOn(date); // exact date OR a recurrence (was exact-only)
      final isToday = day == _now.day;

      Color borderColor;
      double borderWidth;
      if (isToday) {
        borderColor = AppColors.primaryBlue;
        borderWidth = 3;
      } else if (hasCharge) {
        borderColor = anyUnpaid ? const Color(0xFFEF4444) : const Color(0xFF10B981);
        borderWidth = 2;
      } else {
        borderColor = palette.border;
        borderWidth = 1;
      }

      cells.add(GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DateDataPage(date: date)),
        ),
        child: Container(
          decoration: _custodyDecoration(custody).copyWith(
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  child: Text('$day',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                ),
              ),
              if (hasEvent)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: CircleAvatar(radius: 3, backgroundColor: Color(0xFFEF4444)),
                  ),
                ),
            ],
          ),
        ),
      ));
    }

    return Column(
      children: [
        Row(
          children: headers
              .map((h) => Expanded(
                  child: Center(
                      child: Text(h,
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.0,
                              fontWeight: FontWeight.bold,
                              color: palette.textSecondary)))))
              .toList(),
        ),
        const SizedBox(height: 2),
        // Fixed-height cells (mirrors MAUI's 45px day cells). A square
        // childAspectRatio made cells balloon on wide screens, leaving the day
        // number stranded at the top over big blank boxes.
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // MUST be explicit: with padding null, GridView auto-applies the ambient
          // MediaQuery vertical padding (the status-bar / home-indicator insets),
          // which injected a ~status-bar-tall gap between the weekday row and the
          // day grid on notch/Dynamic-Island phones.
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

  Widget _upcomingCard(BuildContext context) {
    final palette = context.palette;
    final events = _upcoming();
    return _card(
      context,
      child: Column(
        children: [
          _sectionHeader(context, 'Upcoming', 'Next events', 'icon_clipboard', AppColors.iconBgGreen, AppColors.successGreen),
          const SizedBox(height: 16),
          if (events.isEmpty)
            Text('No upcoming events', style: TextStyle(fontSize: 14, color: palette.textSecondary))
          else
            for (final e in events) ...[
              _eventRow(context, e.item, e.date),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  /// " • Weekly" style recurrence suffix for an event row (port of MAUI's
  /// GetFriendlyRecurrenceText). Empty for one-off events.
  static String _recurrenceSuffix(String repeatType) {
    if (repeatType.isEmpty || repeatType.toLowerCase() == 'once') return '';
    final label = switch (repeatType.toLowerCase()) {
      'daily' => 'Daily',
      'weekly' => 'Weekly',
      'biweekly' => 'Bi-weekly',
      'monthly' => 'Monthly',
      'quarterly' => 'Quarterly',
      'yearly' => 'Yearly',
      'biyearly' => 'Every 2 years',
      'oddweeks' => 'Odd weeks',
      'evenweeks' => 'Even weeks',
      _ => 'Repeating',
    };
    return ' • $label';
  }

  Widget _eventRow(BuildContext context, ScheduleItem evt, DateTime date) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DateDataPage(date: date))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(20)),
              child: Center(
                  child: Text('${date.day}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(evt.tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                      '${_monthAbbr(date.month)} ${date.day} • ${evt.startTime}-${evt.endTime}${_recurrenceSuffix(evt.repeatType)}',
                      style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentsCard(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      child: Column(
        children: [
          _sectionHeader(context, 'Payments', 'Track and verify', 'icon_credit_card', AppColors.iconBgPurple, AppColors.accentPurple),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _amountTile(context, palette.successBg, const Color(0xFF15803D), AppColors.successGreen, '\$${_verified.toStringAsFixed(0)}', 'Verified')),
              const SizedBox(width: 10),
              Expanded(child: _amountTile(context, const Color(0xFFFFFBEB), const Color(0xFFA16207), AppColors.warningAmber, '\$${_pending.toStringAsFixed(0)}', 'Pending')),
              const SizedBox(width: 10),
              Expanded(child: _amountTile(context, palette.errorBg, const Color(0xFFB91C1C), AppColors.dangerRed, '\$${_overdue.toStringAsFixed(0)}', 'Overdue')),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _goToTab(3),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(16)),
              child: const Row(
                children: [
                  Expanded(
                    child: Text('View All Payments',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  Text('→', style: TextStyle(fontSize: 20, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messagesCard(BuildContext context) {
    final palette = context.palette;
    final contacts = _contacts();
    return _card(
      context,
      child: Column(
        children: [
          _sectionHeader(context, 'Messages', 'Recent conversations', 'icon_chat', AppColors.iconBgBlue, AppColors.primaryBlue),
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

  Widget _contactRow(BuildContext context, _ContactMsg c) {
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
              decoration: BoxDecoration(color: _avatarColor(c), borderRadius: BorderRadius.circular(20)),
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
                      style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_ts(c.ts), style: TextStyle(fontSize: 12, color: palette.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _coParentCard(BuildContext context) {
    final palette = context.palette;
    final bg = _partnerSynced
        ? AppColors.iconBgGreen
        : _partnerPending
            ? AppColors.iconBgYellow
            : AppColors.iconBgRed;
    final tint = _partnerSynced
        ? AppColors.successGreen
        : _partnerPending
            ? AppColors.warningAmber
            : AppColors.dangerRed;
    final subtitle = _partnerSynced && _partnerName.isNotEmpty
        ? 'Connected with $_partnerName'
        : _partnerPending
            ? 'Invitation pending${_partnerEmail.isNotEmpty ? ' — $_partnerEmail' : ''}'
            : 'Not connected with partner';
    return _card(
      context,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PartnerPage())),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
            child: Center(child: AppIcon('icon_people', size: 28, color: tint)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Co-Parent Status',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
              ],
            ),
          ),
          AppIcon('icon_chevron_right', size: 18, color: palette.textSecondary),
        ],
      ),
    );
  }

  Widget _locationCard(BuildContext context) {
    final custodyVisits = _locations.where((r) => r.isCustodyTransfer).length;
    return _card(
      context,
      child: Column(
        children: [
          _sectionHeader(context, 'Location', 'Track custody transfers', 'icon_location', AppColors.iconBgPurple, AppColors.accentPurple),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _locTile(context, 'icon_plus', AppColors.accentPurple, 'Add Record', () => _goToTab(4))),
              const SizedBox(width: 12),
              Expanded(child: _locTile(context, 'icon_map', AppColors.accentTeal, 'View Map', () => _goToTab(4))),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(color: AppColors.accentPurple, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Expanded(child: _bannerStat('${_locations.length}', 'Records')),
                Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.2)),
                Expanded(child: _bannerStat('$custodyVisits', 'Visits')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAccessCard(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      bg: palette.surface,
      child: Column(
        children: [
          _sectionHeader(context, 'Quick Access', 'More features', 'icon_layers', AppColors.iconBgGreen, AppColors.successGreen),
          const SizedBox(height: 20),
          _aiCard(context),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _quickTile(context, 'icon_lock', AppColors.iconBgYellow, AppColors.warningAmber, 'File Vault',
                      () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FileVaultPage()))),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _quickTile(context, 'icon_diamond', AppColors.iconBgPurple, AppColors.accentPurple, 'Subscription',
                      () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionPage()))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── shared widgets ────────────────────────────────────────────────────────────
  Widget _card(BuildContext context, {required Widget child, Color? bg, VoidCallback? onTap}) {
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg ?? context.palette.surfaceElevated, borderRadius: BorderRadius.circular(24)),
      child: child,
    );
    return onTap == null ? box : GestureDetector(onTap: onTap, child: box);
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
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, String subtitle, String icon, Color bg, Color tint) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
            ],
          ),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Center(child: AppIcon(icon, size: 24, color: tint)),
        ),
      ],
    );
  }

  Widget _amountTile(BuildContext context, Color bg, Color amountColor, Color labelColor, String amount, String label) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: amountColor)),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
          ],
        ),
      );

  Widget _locTile(BuildContext context, String icon, Color tint, String label, VoidCallback onTap) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: palette.surfaceInput,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(icon, size: 24, color: tint),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _bannerStat(String value, String label) => Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFE9D5FF))),
        ],
      );

  Widget _aiCard(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiChatPage(chatContext: 'general'))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: palette.surfaceInput,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(child: AppIcon('icon_sparkle', size: 24, color: Colors.white)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('AI Assistant',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(8)),
                        child: const Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Schedules, payments, and more', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickTile(BuildContext context, String icon, Color bg, Color tint, String label, VoidCallback onTap) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: palette.surfaceInput,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Center(child: AppIcon(icon, size: 26, color: tint)),
            ),
            const SizedBox(height: 14),
            Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _ContactMsg {
  _ContactMsg({
    required this.email,
    required this.name,
    required this.preview,
    required this.ts,
    required this.isCoParent,
    required this.isLawyer,
  });
  final String email;
  final String name;
  final String preview;
  final DateTime ts;
  final bool isCoParent;
  final bool isLawyer;
}
