import 'package:flutter/material.dart';
import '../../models/custody_models.dart';
import '../../models/schedule_models.dart';
import '../../services/holiday_resolver.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';

/// Port of `Views/Child/ChildSchedulePage.xaml(.cs)` — a read-only month
/// calendar shaded by the **approved** custody schedule, a legend, and a
/// tapped-day detail card. Custody is resolved from `getApprovedSchedule()`
/// (overrides + repeating pattern + annual alternation + transfer-time
/// gradients) exactly like the parent calendar, so the two never disagree.
class ChildSchedulePage extends StatefulWidget {
  const ChildSchedulePage({super.key});

  @override
  State<ChildSchedulePage> createState() => _ChildSchedulePageState();
}

class _ChildSchedulePageState extends State<ChildSchedulePage> {
  bool _loading = true;
  ApprovedScheduleResponse? _approved;
  List<ScheduleItem> _events = const []; // parents' non-custodial events shared with kids

  late int _year;
  late int _month;
  int? _selectedDay;

  // Pastel custody colours (match the child dashboard mini-month).
  static const _husband = Color.fromARGB(128, 173, 216, 230);
  static const _wife = Color.fromARGB(128, 255, 182, 193);
  static const _both = Color.fromARGB(128, 147, 112, 219);

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static const _dayHeaders = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  Future<void> _load() async {
    try {
      _approved = await ServiceLocator.liveSchedule.getApprovedSchedule();
    } catch (_) {}
    await _loadEvents();
    if (mounted) setState(() => _loading = false);
  }

  // Parents' events the server has marked visible to kids (backend resolves child → parents).
  Future<void> _loadEvents() async {
    try {
      final all = await ServiceLocator.schedule.getScheduleOptimized(_month, _year);
      _events = all.where((s) => !s.isCustodial).toList();
    } catch (_) {/* keep showing custody even if events fail */}
  }

  // Events occurring on [date] — direct matches + recurrence (mirrors the parent calendar).
  List<ScheduleItem> _eventsOn(DateTime date) {
    final out = <ScheduleItem>[];
    final seen = <String>{};
    void add(ScheduleItem s) {
      final key = '${s.tag}|${s.startTime}|${s.endTime}';
      if (seen.add(key)) out.add(s);
    }
    for (final s in _events) {
      if (s.year == date.year && s.month == date.month && s.day == date.day) add(s);
    }
    for (final s in _events) {
      final rt = s.repeatType;
      if (rt.isEmpty || rt.toLowerCase() == 'none') continue;
      if (s.year == date.year && s.month == date.month && s.day == date.day) continue;
      if (_eventRepeatsOn(s, date)) add(s);
    }
    return out;
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

  void _shift(int delta) {
    setState(() {
      var m = _month + delta, y = _year;
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
      _selectedDay = null;
    });
    _loadEvents().then((_) { if (mounted) setState(() {}); });
  }

  bool get _hasSchedule => _approved?.hasSchedule ?? false;

  // ── Custody resolution (approved only) ───────────────────────────────────────
  Map<String, ApprovedOverrideDto> get _overrideLookup {
    final lookup = <String, ApprovedOverrideDto>{};
    for (final ovr in _approved?.overrides ?? const <ApprovedOverrideDto>[]) {
      if (ovr.holidayRule?.isNotEmpty ?? false) {
        final resolved = HolidayResolver.resolveDate(ovr.holidayRule, _year);
        if (resolved != null) lookup['${_pad(resolved.month)}-${_pad(resolved.day)}'] = ovr;
      } else {
        lookup['${_pad(ovr.month)}-${_pad(ovr.day)}'] = ovr;
      }
    }
    return lookup;
  }

  ({String parent, String? time, String? endTime}) _custodyFor(
      DateTime date, Map<String, ApprovedOverrideDto> lookup) {
    final ovr = lookup['${_pad(date.month)}-${_pad(date.day)}'];
    if (ovr != null) {
      var effective = ovr.parentAssignment;
      if (ovr.isAnnual && ovr.alternationMode == 'alternating' && (ovr.alternationStartParent?.isNotEmpty ?? false)) {
        final isOddYear = _year % 2 != 0;
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
    final today = DateTime.now();
    final patternStart = DateTime(today.year, today.month, 1);
    final refSunday = patternStart.subtract(Duration(days: patternStart.weekday % 7));
    final targetSunday = DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday % 7));
    var weeks = targetSunday.difference(refSunday).inDays ~/ 7;
    if (weeks < 0) weeks += ((weeks.abs() ~/ patternLength) + 1) * patternLength;
    return weeks % patternLength;
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

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

  static String _label(String parent) => switch (parent.toLowerCase()) {
        'husband' => 'Dad',
        'wife' => 'Mom',
        'both' => 'Shared',
        _ => 'No schedule',
      };

  static Color? _solidFor(String parent) => switch (parent.toLowerCase()) {
        'husband' => _husband,
        'wife' => _wife,
        'both' => _both,
        _ => null,
      };

  BoxDecoration _custodyDecoration(({String parent, String? time, String? endTime}) custody) {
    final base = _solidFor(custody.parent);
    if (base == null) return const BoxDecoration();
    final parent = custody.parent.toLowerCase();
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: (!_hasSchedule && _events.isEmpty)
                            ? _noSchedule(context)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _dayHeadersRow(context),
                                  // Match the parent schedule — weekday row sits just above the grid.
                                  const SizedBox(height: 12),
                                  _calendar(context),
                                  const SizedBox(height: 20),
                                  _legend(context),
                                  if (_selectedDay != null) ...[
                                    const SizedBox(height: 20),
                                    _dayDetail(context),
                                  ],
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

  Widget _noSchedule(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(24)),
            child: const Center(child: AppIcon('icon_calendar', size: 40, color: AppColors.primaryBlue)),
          ),
          const SizedBox(height: 20),
          Text('No Schedule Yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          const SizedBox(height: 8),
          Text("Your parents haven't set up a custody schedule yet.",
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;
    Widget nav(String icon, VoidCallback onTap) => GestureDetector(
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
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.viewPaddingOf(context).top + 16, 20, 20),
      color: palette.surfaceElevated,
      child: Row(
        children: [
          nav('icon_chevron_left', () => _shift(-1)),
          Expanded(
            child: Column(
              children: [
                Text('${_monthNames[_month - 1]} $_year',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text('Your custody calendar', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          ),
          nav('icon_chevron_right', () => _shift(1)),
        ],
      ),
    );
  }

  Widget _dayHeadersRow(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (final d in _dayHeaders)
            Expanded(
              child: Text(d,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            ),
        ],
      ),
    );
  }

  Widget _calendar(BuildContext context) {
    final palette = context.palette;
    final lookup = _overrideLookup;
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final firstWeekday = DateTime(_year, _month, 1).weekday % 7;
    final today = DateTime.now();
    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const Expanded(child: SizedBox()));
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final custody = _custodyFor(DateTime(_year, _month, d), lookup);
      final isToday = today.year == _year && today.month == _month && today.day == d;
      final selected = _selectedDay == d;
      final decoration = _custodyDecoration(custody);
      final eventCount = _eventsOn(DateTime(_year, _month, d)).length;
      const eventColors = [Color(0xFFEF4444), Color(0xFFF59E0B), Color(0xFFEAB308)];
      Color borderColor;
      double borderWidth;
      if (selected) {
        borderColor = AppColors.accentPurple;
        borderWidth = 3;
      } else if (isToday) {
        borderColor = AppColors.primaryBlue;
        borderWidth = 3;
      } else {
        borderColor = palette.border;
        borderWidth = 1;
      }
      cells.add(Expanded(
        // Day grid styled exactly like the PARENT schedule (64-tall cells, day# top-right,
        // event dots bottom-left, radius 12). Child-only behaviour kept: tapping selects the
        // day to reveal its details below (instead of pushing the parent's DateDataPage).
        child: GestureDetector(
          onTap: () => setState(() => _selectedDay = d),
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: decoration.copyWith(
              border: Border.all(color: borderColor, width: borderWidth),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Text('$d',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                ),
                if (eventCount > 0)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int k = 0; k < eventCount && k < 3; k++)
                          Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: eventColors[k], shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
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

  Widget _legend(BuildContext context) {
    final palette = context.palette;
    Widget chip(Color color, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Center(
                child: Text(label,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary))),
          ),
        );
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
              chip(_husband, 'Dad'),
              const SizedBox(width: 8),
              chip(_wife, 'Mom'),
              const SizedBox(width: 8),
              chip(_both, 'Shared'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayDetail(BuildContext context) {
    final palette = context.palette;
    final custody = _custodyFor(DateTime(_year, _month, _selectedDay!), _overrideLookup);
    final label = _label(custody.parent);
    final who = custody.parent.toLowerCase() == 'none'
        ? 'No schedule for this day'
        : (label == 'Shared' ? 'Shared day' : "$label's day");
    final time = _parseTod(custody.time);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_monthNames[_month - 1]} $_selectedDay, $_year',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          const SizedBox(height: 8),
          Text(who, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
          if (time != null) ...[
            const SizedBox(height: 4),
            Text('Transfer at ${time.format(context)}',
                style: TextStyle(fontSize: 13, color: palette.textSecondary)),
          ],
          ..._dayEventTiles(context),
        ],
      ),
    );
  }

  List<Widget> _dayEventTiles(BuildContext context) {
    final palette = context.palette;
    final events = _eventsOn(DateTime(_year, _month, _selectedDay!));
    if (events.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      Divider(color: palette.border, height: 1),
      const SizedBox(height: 12),
      Text('Events', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: palette.textSecondary)),
      const SizedBox(height: 6),
      for (final e in events)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.circle, size: 8, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(e.tag,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.textPrimary)),
              ),
              if (_parseTod(e.startTime) != null)
                Text(_parseTod(e.startTime)!.format(context),
                    style: TextStyle(fontSize: 12, color: palette.textSecondary)),
            ],
          ),
        ),
    ];
  }
}
