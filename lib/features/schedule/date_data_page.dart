import 'package:flutter/material.dart';
import '../../models/custody_models.dart';
import '../../models/financial_models.dart';
import '../../models/schedule_models.dart';
import '../../services/holiday_resolver.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import 'add_event_popup.dart';

/// Port of `Views/Schedule/DateData.xaml(.cs)` — a single-day detail view: custody &
/// payment summary cards plus a 24-hour timeline of events (with recurrence), and an
/// Add Event button. Events come from [ScheduleService]; custody from the proposal
/// system; payments from [FinancialService]. Tapping an event offers edit/delete.
class DateDataPage extends StatefulWidget {
  final DateTime date;
  const DateDataPage({super.key, required this.date});

  @override
  State<DateDataPage> createState() => _DateDataPageState();
}

class _DateDataPageState extends State<DateDataPage> {
  late DateTime _date;
  bool _loading = true;
  bool _busy = false;

  List<ScheduleItem> _allEvents = const []; // non-custodial, current month
  int _loadedMonth = 0, _loadedYear = 0;
  ApprovedScheduleResponse? _approved;
  List<FCharge> _charges = const [];

  String _custodyText = 'No custody information for this day';
  String _paymentText = 'No payment records for this day';
  Color _paymentBorder = const Color(0xFF10B981);

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _date = widget.date;
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      if (_loadedMonth != _date.month || _loadedYear != _date.year) {
        final all = await ServiceLocator.schedule.getScheduleOptimized(_date.month, _date.year);
        _allEvents = all.where((s) => !s.isCustodial).toList();
        _loadedMonth = _date.month;
        _loadedYear = _date.year;
      }
      _approved ??= await ServiceLocator.liveSchedule.getApprovedSchedule();
      if (_charges.isEmpty) _charges = await ServiceLocator.financial.getCharges();
      _recompute();
    } catch (_) {
      // leave defaults
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _recompute() {
    _custodyText = _resolveCustodyText();
    final (text, border) = _resolvePayment();
    _paymentText = text;
    _paymentBorder = border;
  }

  Future<void> _shiftDay(int delta) async {
    _date = _date.add(Duration(days: delta));
    await _load();
  }

  String get _dateLabel => '${_weekdays[_date.weekday - 1]}, ${_months[_date.month - 1]} ${_date.day}';

  // ── Events for the date (incl. recurrence) ───────────────────────────────────
  List<_DayEvent> _eventsForDate() {
    final out = <_DayEvent>[];
    final seen = <String>{};
    void add(ScheduleItem s, {required bool recurring}) {
      final key = '${s.tag}|${s.startTime}|${s.endTime}';
      if (seen.contains(key)) return;
      seen.add(key);
      out.add(_DayEvent(
        tag: s.tag,
        start: _parseTod(s.startTime) ?? const TimeOfDay(hour: 0, minute: 0),
        end: _parseTod(s.endTime) ?? const TimeOfDay(hour: 23, minute: 59),
        startRaw: s.startTime,
        endRaw: s.endTime,
        repeatType: s.repeatType,
        endDate: s.endDate,
        origMonth: s.month,
        origDay: s.day,
        origYear: s.year,
        visibleToKids: s.visibleToKids,
        scheduleId: s.scheduleId,
      ));
    }

    for (final s in _allEvents) {
      if (s.year == _date.year && s.month == _date.month && s.day == _date.day) add(s, recurring: false);
    }
    for (final s in _allEvents) {
      if (s.year == _date.year && s.month == _date.month && s.day == _date.day) continue;
      if (s.repeatType.isEmpty || s.repeatType.toLowerCase() == 'none') continue;
      if (_eventRepeatsOn(s, _date)) add(s, recurring: true);
    }
    out.sort((a, b) => _min(a.start).compareTo(_min(b.start)));
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

  // ── Custody resolution (override → pattern + alternation) ─────────────────────
  String _resolveCustodyText() {
    final approved = _approved;
    if (approved == null || !approved.hasSchedule) return 'No custody schedule set up';

    String? parent, handoffStart, handoffEnd, locationName, description;
    var isOverride = false;
    final dateKey = '${_pad(_date.month)}-${_pad(_date.day)}';

    for (final ovr in approved.overrides) {
      String effectiveKey;
      if (ovr.holidayRule?.isNotEmpty ?? false) {
        final resolved = HolidayResolver.resolveDate(ovr.holidayRule, _date.year);
        if (resolved == null) continue;
        effectiveKey = '${_pad(resolved.month)}-${_pad(resolved.day)}';
      } else {
        effectiveKey = '${_pad(ovr.month)}-${_pad(ovr.day)}';
      }
      if (effectiveKey == dateKey) {
        var effective = ovr.parentAssignment;
        if (ovr.isAnnual && ovr.alternationMode == 'alternating' && (ovr.alternationStartParent?.isNotEmpty ?? false)) {
          final isOddYear = _date.year % 2 != 0;
          final start = ovr.alternationStartParent!;
          effective = isOddYear ? start : (start == 'Husband' ? 'Wife' : 'Husband');
        }
        if (effective != 'None') {
          parent = effective;
          handoffStart = ovr.transferTime;
          handoffEnd = ovr.transferEndTime;
          locationName = ovr.transferLocationName;
          description = ovr.description;
          isOverride = true;
        }
        break;
      }
    }

    if (parent == null && approved.days.isNotEmpty) {
      final dayIndex = _date.weekday % 7;
      final patternLength = approved.patternLength > 0 ? approved.patternLength : 1;
      final week = patternLength <= 1 ? 0 : _calcWeek(_date, patternLength);
      for (final d in approved.days) {
        if (d.dayIndex == dayIndex && d.weekIndex == week && d.parentAssignment != 'None') {
          parent = d.parentAssignment;
          handoffStart = d.transferTime;
          handoffEnd = d.transferEndTime;
          locationName = d.transferLocationName;
          break;
        }
      }
    }

    if (parent == null) return 'No custody information for this day';

    final parts = <String>[_displayParent(parent)];
    if (isOverride && (description?.isNotEmpty ?? false)) parts.add(description!);
    final start = _parseTod(handoffStart);
    if (start != null) {
      final end = _parseTod(handoffEnd);
      parts.add(end != null ? 'Handoff ${_fmt(start)} – ${_fmt(end)}' : 'Handoff at ${_fmt(start)}');
    }
    if (locationName?.isNotEmpty ?? false) parts.add('📍 $locationName');
    return parts.join('\n');
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

  // ── Payment resolution (direct + recurring charges) ──────────────────────────
  (String, Color) _resolvePayment() {
    final charges = <FCharge>[];
    for (final c in _charges) {
      final d = c.date;
      if (d == null) continue;
      if (d.year == _date.year && d.month == _date.month && d.day == _date.day) {
        charges.add(c);
        continue;
      }
      final rp = c.repeatPattern;
      if (rp == null || rp.isEmpty || rp == 'none' || rp == 'once') continue;
      if (_chargeRepeatsOn(c, _date)) charges.add(c);
    }
    if (charges.isEmpty) return ('No payment records for this day', const Color(0xFF10B981));
    if (charges.length == 1) {
      final c = charges.first;
      final status = c.isPaid ? 'Paid' : 'Unpaid';
      return (
        'Payment due today\nAmount: \$${c.amount.toStringAsFixed(0)}\nStatus: $status',
        c.isPaid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
      );
    }
    final total = charges.fold(0.0, (s, c) => s + c.amount);
    final paid = charges.where((c) => c.isPaid).length;
    final allPaid = paid == charges.length;
    return (
      '${charges.length} payments due today\nTotal: \$${total.toStringAsFixed(0)}\n$paid/${charges.length} paid',
      allPaid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
    );
  }

  bool _chargeRepeatsOn(FCharge c, DateTime target) {
    final orig = c.date;
    if (orig == null || target.isBefore(DateTime(orig.year, orig.month, orig.day))) return false;
    switch (c.repeatPattern?.toLowerCase()) {
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

  // ── Event CRUD ────────────────────────────────────────────────────────────────
  Future<void> _addEvent() async {
    final result = await AddEventPopup.show(context);
    if (result == null || !mounted) return;
    await _createEvent(result);
  }

  Future<void> _editEvent(_DayEvent e) async {
    final result = await AddEventPopup.show(
      context,
      isEdit: true,
      initialName: e.tag,
      initialStart: e.start,
      initialEnd: e.end,
      initialRepeat: e.repeatType,
      initialRepeatEnd: e.endDate,
      initialVisibleToKids: e.visibleToKids,
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    // Delete the original first (by id, so a co-parent's event resolves), then recreate.
    final ok = await ServiceLocator.schedule.deleteSchedules([
      ScheduleDeleteRequest(
          month: e.origMonth, day: e.origDay, year: e.origYear, tag: e.tag, scheduleId: e.scheduleId),
    ]);
    if (!ok) {
      if (mounted) {
        setState(() => _busy = false);
        await _alert('Error', 'Failed to update event on server');
      }
      return;
    }
    await _createEvent(result, alreadyBusy: true);
  }

  Future<void> _deleteEvent(_DayEvent e) async {
    final confirm = await _confirm('Delete Event', "Are you sure you want to delete '${e.tag}'?", 'Delete');
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final ok = await ServiceLocator.schedule.deleteSchedules([
        ScheduleDeleteRequest(
            month: e.origMonth, day: e.origDay, year: e.origYear, tag: e.tag, scheduleId: e.scheduleId),
      ]);
      if (ok) {
        _loadedMonth = 0; // force events refetch
        await _load();
      } else {
        await _alert('Error', 'Failed to delete event from server');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createEvent(AddEventResult r, {bool alreadyBusy = false}) async {
    if (!alreadyBusy) setState(() => _busy = true);
    try {
      final endDate = (r.repeatEndDate ?? DateTime.now()).toIso8601String();
      final ok = await ServiceLocator.schedule.updateSchedules([
        ScheduleUpdateRequest(
          month: _date.month,
          day: _date.day,
          year: _date.year,
          tag: r.eventName,
          startTime: _hms(r.startTime),
          endTime: _hms(r.endTime),
          repeatType: r.repeatPattern,
          endDate: endDate,
          isCustodial: false,
          isOverride: false,
          isProtected: false,
          visibleToKids: r.visibleToKids,
        ),
      ]);
      if (!ok) {
        await _alert('Error', 'Failed to save event on server');
      }
      _loadedMonth = 0; // force events refetch
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showEventOptions(_DayEvent e) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(e.tag,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ctx.palette.textPrimary)),
            ),
            ListTile(
              leading: const AppIcon('icon_edit', size: 22, color: AppColors.primaryBlue),
              title: const Text('Edit Event'),
              onTap: () {
                Navigator.of(ctx).pop();
                _editEvent(e);
              },
            ),
            ListTile(
              leading: const AppIcon('icon_trash', size: 22, color: AppColors.dangerRed),
              title: const Text('Delete Event', style: TextStyle(color: AppColors.dangerRed)),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteEvent(e);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────────
  static String _pad(int n) => n.toString().padLeft(2, '0');
  static int _min(TimeOfDay t) => t.hour * 60 + t.minute;
  static String _displayParent(String p) => switch (p) {
        'Husband' => 'Dad',
        'Wife' => 'Mom',
        _ => p,
      };
  static TimeOfDay? _parseTod(String? s) {
    if (s == null || s.isEmpty || s == '00:00' || s == '0:00') return null;
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _hms(TimeOfDay t) => '${_pad(t.hour)}:${_pad(t.minute)}:00';
  static String _fmt(TimeOfDay t) {
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    var dh = t.hour % 12;
    if (dh == 0) dh = 12;
    return '$dh:${_pad(t.minute)} $ampm';
  }

  Future<void> _alert(String title, String message) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );

  Future<bool?> _confirm(String title, String message, String confirmLabel) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(confirmLabel)),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────────
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
              _infoCards(context),
              Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _timeline(context)),
              _addEventBar(context),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.viewPaddingOf(context).top + 12, 20, 16),
      color: palette.surface,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: AppIcon('icon_chevron_left', size: 24, color: palette.textSecondary)),
            ),
          ),
          GestureDetector(
            onTap: () => _shiftDay(-1),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(child: AppIcon('icon_chevron_left', size: 20, color: palette.textSecondary)),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(_dateLabel,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text('Daily schedule overview', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _shiftDay(1),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(child: AppIcon('icon_chevron_right', size: 20, color: palette.textSecondary)),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _infoCards(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _infoCard(context, 'icon_users', AppColors.iconBgGreen, AppColors.successGreen, 'Custody Info',
                  _custodyText, null),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _infoCard(context, 'icon_money', AppColors.iconBgYellow, AppColors.warningAmber, 'Payment Info',
                  _paymentText, _paymentBorder),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(BuildContext context, String icon, Color iconBg, Color iconTint, String title, String body,
      Color? borderColor) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: borderColor != null ? Border.all(color: borderColor, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                child: Center(child: AppIcon(icon, size: 16, color: iconTint)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
        ],
      ),
    );
  }

  Widget _timeline(BuildContext context) {
    final palette = context.palette;
    final events = _eventsForDate();
    const gutter = 92.0;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: SizedBox(
          height: 24 * 60,
          child: Stack(
            children: [
              // hour grid
              for (int h = 0; h < 24; h++)
                Positioned(
                  top: h * 60.0,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: 60,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: gutter,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text('${h % 12 == 0 ? 12 : h % 12}:00 ${h < 12 ? 'AM' : 'PM'}',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: palette.textSecondary)),
                          ),
                        ),
                        Expanded(child: Container(height: 1, margin: const EdgeInsets.only(top: 10), color: palette.border)),
                      ],
                    ),
                  ),
                ),
              // event blocks
              for (final e in events) _eventBlock(context, e, gutter),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventBlock(BuildContext context, _DayEvent e, double gutter) {
    final top = _min(e.start).toDouble();
    var height = (_min(e.end) - _min(e.start)).toDouble();
    if (height <= 0) height = 30;
    return Positioned(
      top: top,
      left: gutter,
      right: 12,
      height: height,
      child: GestureDetector(
        onTap: () => _showEventOptions(e),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.5),
            border: Border.all(color: const Color(0xFFEF4444)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(e.tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }

  Widget _addEventBar(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 48 + MediaQuery.viewPaddingOf(context).bottom),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: GestureDetector(
        onTap: _addEvent,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.3), offset: const Offset(0, 4), blurRadius: 12),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon('icon_plus', size: 20, color: Colors.white),
              SizedBox(width: 8),
              Text('Add Event', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayEvent {
  _DayEvent({
    required this.tag,
    required this.start,
    required this.end,
    required this.startRaw,
    required this.endRaw,
    required this.repeatType,
    required this.endDate,
    required this.origMonth,
    required this.origDay,
    required this.origYear,
    this.visibleToKids = true,
    this.scheduleId = 0,
  });
  final String tag;
  final TimeOfDay start;
  final TimeOfDay end;
  final String startRaw;
  final String endRaw;
  final String repeatType;
  final DateTime? endDate;
  final int origMonth;
  final int origDay;
  final int origYear;
  final bool visibleToKids;
  final int scheduleId;
}
