import 'package:flutter/material.dart';
import '../../models/custody_models.dart';
import '../../models/financial_models.dart';
import '../../models/schedule_models.dart';
import '../../services/custody_templates/pending_template_service.dart';
import '../../services/holiday_resolver.dart';
import '../../services/live_schedule_service.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/skeleton.dart';
import 'live_schedule_page.dart';
import 'date_data_page.dart';

/// Schedule tab — port of `Views/Schedule/Scedule.xaml(.cs)` + `MonthItem.cs`. A month
/// calendar shaded by custody assignment (resolved from the live schedule pattern +
/// overrides), payment-status borders, event dots, monthly custody distribution
/// metrics, and entry points to manage custody / export. Device-calendar export +
/// .ics share remain phase-3 native.
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late int _year;
  late int _month; // 1-12
  bool _loading = true;
  String _currentUserEmail = '';

  ApprovedScheduleResponse? _approved;
  LiveAgreement? _agreement;
  List<ScheduleItem> _events = const []; // non-custodial only
  List<FCharge> _charges = const []; // current user's charges

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  // Custody fill colors (mirror MAUI's rgba(.,.,.,128) day backgrounds).
  static const _husbandColor = Color.fromARGB(128, 173, 216, 230);
  static const _wifeColor = Color.fromARGB(128, 255, 182, 193);
  static const _bothColor = Color.fromARGB(128, 147, 112, 219);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      _currentUserEmail = Preferences.getString('email');
      final results = await Future.wait([
        ServiceLocator.schedule.getScheduleOptimized(_month, _year),
        ServiceLocator.financial.getCharges(),
        ServiceLocator.liveSchedule.getApprovedSchedule(),
        ServiceLocator.liveSchedule.getAgreement(),
      ]);
      final allItems = results[0] as List<ScheduleItem>;
      final allCharges = results[1] as List<FCharge>;
      _approved = results[2] as ApprovedScheduleResponse?;
      _agreement = results[3] as LiveAgreement?;

      _events = allItems.where((s) => !s.isCustodial).toList();
      _charges = allCharges
          .where((c) => (c.email ?? '').toLowerCase() == _currentUserEmail.toLowerCase())
          .toList();
    } catch (_) {
      // Leave whatever loaded; calendar falls back to "None".
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftMonth(int delta) {
    var m = _month + delta;
    var y = _year;
    while (m < 1) {
      m += 12;
      y--;
    }
    while (m > 12) {
      m -= 12;
      y++;
    }
    _month = m;
    _year = y;
    _load();
  }

  // ── Effective custody source (the live/approved schedule) ───────────────────
  ({int patternLength, DateTime? patternAnchorDate, List<ApprovedDayDto> days, List<ApprovedOverrideDto> overrides}) _source() {
    return (
      patternLength: _approved?.patternLength ?? 1,
      patternAnchorDate: _approved?.patternAnchorDate,
      days: _approved?.days ?? const [],
      overrides: _approved?.overrides ?? const [],
    );
  }

  Map<String, ApprovedOverrideDto> _overrideLookup(List<ApprovedOverrideDto> overrides) {
    final lookup = <String, ApprovedOverrideDto>{};
    for (final ovr in overrides) {
      if (ovr.holidayRule?.isNotEmpty ?? false) {
        final resolved = HolidayResolver.resolveDate(ovr.holidayRule, _year);
        if (resolved != null) {
          lookup['${_pad(resolved.month)}-${_pad(resolved.day)}'] = ovr;
        }
      } else {
        lookup['${_pad(ovr.month)}-${_pad(ovr.day)}'] = ovr;
      }
    }
    return lookup;
  }

  /// Custody for a date → (parent, transferTime, endTime). Mirrors MonthItem.GenerateDays.
  ({String parent, String? time, String? endTime}) _resolveCustody(
      DateTime date,
      ({int patternLength, DateTime? patternAnchorDate, List<ApprovedDayDto> days, List<ApprovedOverrideDto> overrides}) src,
      Map<String, ApprovedOverrideDto> overrideLookup) {
    final dateKey = '${_pad(date.month)}-${_pad(date.day)}';
    final ovr = overrideLookup[dateKey];
    if (ovr != null) {
      var effective = ovr.parentAssignment;
      if (ovr.isAnnual && ovr.alternationMode == 'alternating' && (ovr.alternationStartParent?.isNotEmpty ?? false)) {
        final isOddYear = _year % 2 != 0;
        final start = ovr.alternationStartParent!;
        final other = start == 'Husband' ? 'Wife' : 'Husband';
        effective = isOddYear ? start : other;
      }
      if (effective != 'None') {
        return (parent: effective, time: ovr.transferTime, endTime: ovr.transferEndTime);
      }
    }
    if (src.days.isNotEmpty) {
      final dayIndex = date.weekday % 7; // Sun=0
      final weekInPattern = LiveScheduleService.weekIndexFor(date, src.patternLength, src.patternAnchorDate);
      for (final d in src.days) {
        if (d.dayIndex == dayIndex && d.weekIndex == weekInPattern) {
          return (parent: d.parentAssignment, time: d.transferTime, endTime: d.transferEndTime);
        }
      }
    }
    return (parent: 'None', time: null, endTime: null);
  }

  /// Payment status for a date: 0 none, 1 paid, 2 unpaid (any unpaid charge that day).
  int _paymentStatus(DateTime date) {
    var found = false;
    var anyUnpaid = false;
    for (final c in _charges) {
      final d = c.date;
      if (d == null) continue;
      var hit = d.year == date.year && d.month == date.month && d.day == date.day;
      if (!hit) {
        final rp = c.repeatPattern;
        if (rp != null && rp.isNotEmpty && rp != 'none' && rp != 'once') {
          hit = _chargeRepeatsOn(c, date);
        }
      }
      if (hit) {
        found = true;
        if (!c.isPaid) anyUnpaid = true;
      }
    }
    if (!found) return 0;
    return anyUnpaid ? 2 : 1;
  }

  bool _chargeRepeatsOn(FCharge c, DateTime target) {
    final orig = c.date;
    if (orig == null || target.isBefore(DateTime(orig.year, orig.month, orig.day))) return false;
    final t = target;
    switch (c.repeatPattern) {
      case 'weekly':
      case 'Weekly':
        return t.weekday == orig.weekday;
      case 'biweekly':
      case 'Biweekly':
        return t.weekday == orig.weekday && (t.difference(orig).inDays ~/ 7) % 2 == 0;
      case 'monthly':
      case 'Monthly':
        return t.day == orig.day;
      case 'quarterly':
      case 'Quarterly':
        return t.day == orig.day && ((t.year - orig.year) * 12 + (t.month - orig.month)) % 3 == 0;
      case 'yearly':
      case 'Yearly':
        return t.day == orig.day && t.month == orig.month;
      case 'biyearly':
      case 'Biyearly':
        return t.day == orig.day && t.month == orig.month && (t.year - orig.year) % 2 == 0;
      default:
        return false;
    }
  }

  /// Number of event dots (0-3) for a day: direct events first, then recurring.
  int _eventCount(int day) {
    final date = DateTime(_year, _month, day);
    var count = 0;
    for (final s in _events) {
      if (count >= 3) break;
      if (s.year == _year && s.month == _month && s.day == day) count++;
    }
    if (count < 3) {
      for (final s in _events) {
        if (count >= 3) break;
        final rt = s.repeatType;
        if (rt.isEmpty || rt == 'none' || rt == 'None') continue;
        if (s.year == _year && s.month == _month && s.day == day) continue; // already counted as direct
        if (_eventRepeatsOn(s, date)) count++;
      }
    }
    return count;
  }

  bool _eventRepeatsOn(ScheduleItem s, DateTime target) {
    final orig = DateTime(s.year, s.month, s.day);
    if (target.isBefore(orig)) return false;
    if (s.endDate != null && target.isAfter(s.endDate!)) return false;
    switch (s.repeatType) {
      case 'daily':
      case 'Daily':
        return true;
      case 'weekly':
      case 'Weekly':
        return target.weekday == orig.weekday;
      case 'biweekly':
      case 'Biweekly':
        return target.weekday == orig.weekday && (target.difference(orig).inDays ~/ 7) % 2 == 0;
      case 'monthly':
      case 'Monthly':
        return target.day == orig.day;
      case 'quarterly':
      case 'Quarterly':
        return target.day == orig.day && ((target.year - orig.year) * 12 + (target.month - orig.month)) % 3 == 0;
      case 'yearly':
      case 'Yearly':
        return target.day == orig.day && target.month == orig.month;
      case 'biyearly':
      case 'Biyearly':
        return target.day == orig.day && target.month == orig.month && (target.year - orig.year) % 2 == 0;
      default:
        return false;
    }
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Column(
            children: [
              _header(context),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: _loading
                    ? const SkeletonMonthGrid(key: ValueKey('skeleton'))
                    : SingleChildScrollView(
                        key: const ValueKey('content'),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_agreement?.needsMyAgreement ?? false) ...[
                                  _agreementBanner(context, mine: true),
                                  const SizedBox(height: 20),
                                ] else if ((_agreement?.iAgreed ?? false) && !(_agreement?.partnerAgreed ?? false)) ...[
                                  _agreementBanner(context, mine: false),
                                  const SizedBox(height: 20),
                                ],
                                _dayHeaders(context),
                                const SizedBox(height: 12),
                                _calendarGrid(context),
                                const SizedBox(height: 20),
                                _legend(context),
                                const SizedBox(height: 20),
                                _metrics(context),
                                const SizedBox(height: 20),
                                _manageButton(context),
                              ],
                            ),
                          ),
                        ),
                      ),
                ),
              ),
            ],
          ),
          Positioned(
            right: 20,
            bottom: 24,
            child: GestureDetector(
              onTap: () => _openManageCustody(context),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.4), offset: const Offset(0, 4), blurRadius: 12),
                  ],
                ),
                child: const Center(child: AppIcon('icon_settings', size: 24, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header (month nav) ───────────────────────────────────────────────────────
  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.viewPaddingOf(context).top + 12, 20, 16),
      color: palette.surface,
      child: Row(
        children: [
          _navButton(context, 'icon_chevron_left', () => _shiftMonth(-1)),
          Expanded(
            child: Column(
              children: [
                Text('${_monthNames[_month - 1]} $_year',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text('Family schedule overview', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          ),
          _navButton(context, 'icon_chevron_right', () => _shiftMonth(1)),
        ],
      ),
    );
  }

  Widget _navButton(BuildContext context, String icon, VoidCallback onTap) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(child: AppIcon(icon, size: 24, color: palette.textSecondary)),
      ),
    );
  }

  // ── Day headers ───────────────────────────────────────────────────────────────
  Widget _dayHeaders(BuildContext context) {
    final palette = context.palette;
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (final d in days)
            Expanded(
              child: Text(d,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            ),
        ],
      ),
    );
  }

  // ── Calendar grid ─────────────────────────────────────────────────────────────
  Widget _calendarGrid(BuildContext context) {
    final src = _source();
    final lookup = _overrideLookup(src.overrides);
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final firstWeekday = DateTime(_year, _month, 1).weekday % 7; // Sun=0
    final today = DateTime.now();

    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const Expanded(child: SizedBox()));
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_year, _month, day);
      final custody = _resolveCustody(date, src, lookup);
      final isToday = today.year == _year && today.month == _month && today.day == day;
      cells.add(Expanded(
        child: _dayCell(context, day, custody, _paymentStatus(date), _eventCount(day), isToday),
      ));
    }
    while (cells.length % 7 != 0) {
      cells.add(const Expanded(child: SizedBox()));
    }
    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            for (int c = i; c < i + 7; c++) ...[
              cells[c],
              if (c < i + 6) const SizedBox(width: 4),
            ],
          ],
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _dayCell(BuildContext context, int day, ({String parent, String? time, String? endTime}) custody,
      int paymentStatus, int eventCount, bool isToday) {
    final palette = context.palette;
    final txtColor = context.isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);

    Color borderColor;
    double borderWidth;
    if (isToday) {
      borderColor = AppColors.primaryBlue;
      borderWidth = 3;
    } else if (paymentStatus == 2) {
      borderColor = const Color(0xFFEF4444);
      borderWidth = 2;
    } else if (paymentStatus == 1) {
      borderColor = const Color(0xFF10B981);
      borderWidth = 2;
    } else {
      borderColor = palette.border;
      borderWidth = 1;
    }

    const eventColors = [Color(0xFFEF4444), Color(0xFFF59E0B), Color(0xFFEAB308)];

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DateDataPage(date: DateTime(_year, _month, day))),
      ),
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(4),
        decoration: _custodyDecoration(custody).copyWith(
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Text('$day',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: txtColor)),
            ),
            if (eventCount > 0)
              Align(
                alignment: Alignment.bottomLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < eventCount; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: eventColors[i], shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _custodyDecoration(({String parent, String? time, String? endTime}) custody) {
    final parent = custody.parent.toLowerCase();
    Color base;
    switch (parent) {
      case 'husband':
        base = _husbandColor;
        break;
      case 'wife':
        base = _wifeColor;
        break;
      case 'both':
        base = _bothColor;
        break;
      default:
        return const BoxDecoration(color: Colors.transparent);
    }

    final start = _parseTod(custody.time);
    final end = _parseTod(custody.endTime);
    if (start != null && parent != 'both') {
      final startP = ((start.hour * 60 + start.minute) / (24 * 60)).clamp(0.0, 1.0);
      final to = parent == 'husband' ? _wifeColor : _husbandColor;
      if (end != null && (end.hour * 60 + end.minute) > (start.hour * 60 + start.minute)) {
        final endP = ((end.hour * 60 + end.minute) / (24 * 60)).clamp(0.0, 1.0);
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

  static TimeOfDay? _parseTod(String? s) {
    if (s == null || s.isEmpty || s == '00:00') return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
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

  // ── Legend ────────────────────────────────────────────────────────────────────
  Widget _legend(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text('Custody Legend',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _legendChip(_husbandColor, const Color(0xFF1E40AF), 'Dad')),
              const SizedBox(width: 8),
              Expanded(child: _legendChip(_wifeColor, const Color(0xFFBE185D), 'Mom')),
              const SizedBox(width: 8),
              Expanded(child: _legendChip(_bothColor, Colors.white, 'Both')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendChip(Color bg, Color text, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Center(
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: text)),
      ),
    );
  }

  // ── Metrics ─────────────────────────────────────────────────────────────────
  Widget _metrics(BuildContext context) {
    final palette = context.palette;
    final src = _source();
    final lookup = _overrideLookup(src.overrides);
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    int husband = 0, wife = 0, both = 0;
    for (int day = 1; day <= daysInMonth; day++) {
      final p = _resolveCustody(DateTime(_year, _month, day), src, lookup).parent.toLowerCase();
      if (p == 'husband') husband++;
      if (p == 'wife') wife++;
      if (p == 'both') both++;
    }
    final total = daysInMonth;
    int pct(int n) => total > 0 ? (n * 100 / total).floor() : 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(12)),
                child: const Center(child: AppIcon('icon_chart', size: 24, color: AppColors.primaryBlue)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monthly Custody Distribution',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Custody time breakdown for this month',
                        style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _statTile('Dad', pct(husband), AppColors.primaryBlue)),
              const SizedBox(width: 16),
              Expanded(child: _statTile('Mom', pct(wife), const Color(0xFFEC4899))),
              const SizedBox(width: 16),
              Expanded(child: _statTile('Both', pct(both), AppColors.accentPurple)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, int pct, Color circleColor) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
            child: Center(
              child: Text('$pct%',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        ],
      ),
    );
  }

  // ── Action buttons ─────────────────────────────────────────────────────────────
  Widget _manageButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _openManageCustody(context),
      child: Container(
        height: 56,
        decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(16)),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon('icon_settings', size: 20, color: Colors.white),
            SizedBox(width: 8),
            Text('Manage Custody Schedule',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  // "You haven't agreed yet" (mine) / "Waiting for your co-parent" (!mine).
  Widget _agreementBanner(BuildContext context, {required bool mine}) {
    final palette = context.palette;
    final accent = mine ? AppColors.dangerRed : AppColors.warningAmber;
    final title = mine ? "You haven't agreed to this schedule yet" : 'Waiting for your co-parent to agree';
    final subtitle = mine
        ? 'Tap to review the current schedule and agree.'
        : "You've agreed — they still need to review and agree.";
    return GestureDetector(
      onTap: () => _openManageCustody(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: context.isDark ? 0.18 : 0.10),
          border: Border.all(color: accent.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
              child: Icon(mine ? Icons.error_outline : Icons.hourglass_top, size: 22, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                ],
              ),
            ),
            if (mine) Icon(Icons.chevron_right, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _openManageCustody(BuildContext context) async {
    // Main-app entry into the editor must NOT be onboarding mode (the flag is a global
    // static that onboarding may have left set).
    PendingTemplateService.isOnboardingMode = false;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveSchedulePage()));
    if (mounted) _load(); // refresh after returning (schedule may have changed)
  }
}
