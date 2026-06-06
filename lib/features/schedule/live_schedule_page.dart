import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../navigation/app_navigator.dart';
import '../../services/live_schedule_service.dart';
import '../../services/onboarding_state.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';

/// The LIVE custody schedule editor — one shared schedule both co-parents edit in real
/// time. Replaces the proposal draft/submit/review flow. Same visual language as
/// CustodySchedulePage (week cards, tappable day cells, a bottom-sheet day editor,
/// week-length dropdown) but:
///   • edits hit /api/schedule/live with the current version (stale → reload),
///   • week-length + template/AI take the schedule-wide lock,
///   • locks show LIVE (greyed days, a "co-parent is editing" overlay) via the WS ping,
///     with the 409/423 server reject as the fallback for the sub-second window,
///   • both parents tap Agree to lock in the schedule-of-record.
class LiveSchedulePage extends StatefulWidget {
  const LiveSchedulePage({super.key, this.isOnboarding = false});

  /// In onboarding, agreeing advances the onboarding flow instead of just showing a banner.
  final bool isOnboarding;

  @override
  State<LiveSchedulePage> createState() => _LiveSchedulePageState();
}

class _LiveSchedulePageState extends State<LiveSchedulePage> with WidgetsBindingObserver {
  static const _dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  static const _weekOptions = [1, 2, 3, 4, 6, 8];

  LiveScheduleService get _svc => ServiceLocator.liveSchedule;
  String _me = '';

  LiveScheduleData? _data;
  bool _loading = true;
  bool _noPartner = false;
  bool _busy = false; // a mutating call is in flight

  StreamSubscription<int>? _wsSub;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _me = Preferences.getString('email').toLowerCase();
    WidgetsBinding.instance.addObserver(this);
    // Live updates: refetch when the co-parent pings us over the socket…
    _wsSub = _svc.onChanged.listen((_) => _refresh());
    // …and a gentle poll while the editor is open as the fallback (covers a dropped
    // socket and surfaces lock changes within a few seconds).
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  // ── data ───────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _svc.get();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _noPartner = r.op == LiveOp.noPartner;
      if (r.data != null) _data = r.data;
    });
  }

  // Silent refresh used by the WS ping / poll — don't flicker the spinner, and don't
  // stomp the screen while the user has a mutating call in flight.
  Future<void> _refresh() async {
    if (_busy || !mounted) return;
    final r = await _svc.get();
    if (!mounted || r.data == null) return;
    setState(() => _data = r.data);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // Apply a mutation result to the screen, with consistent conflict/lock handling.
  Future<void> _applyResult(LiveResult r) async {
    if (!mounted) return;
    switch (r.op) {
      case LiveOp.ok:
        setState(() => _data = r.data);
        break;
      case LiveOp.conflict:
        _toast('Your co-parent just changed this — reloaded.');
        await _refresh();
        break;
      case LiveOp.locked:
        if (r.data != null) setState(() => _data = r.data);
        _toast('Your co-parent is editing the whole schedule right now.');
        break;
      case LiveOp.lockedDay:
        if (r.data != null) setState(() => _data = r.data);
        _toast('Your co-parent is editing that day right now.');
        break;
      case LiveOp.noPartner:
        setState(() => _noPartner = true);
        break;
      case LiveOp.error:
        _toast('Something went wrong — please try again.');
        break;
    }
  }

  bool get _scheduleLockedByOther {
    final l = _data?.locked;
    return l != null && l.by.toLowerCase() != _me;
  }

  // ── actions ─────────────────────────────────────────────────────────────────
  Future<void> _changeWeekLength(int weeks) async {
    final d = _data;
    if (d == null || _busy) return;
    setState(() => _busy = true);
    // Treat the week-length change as a structural/bulk op: take the schedule-wide lock
    // so the co-parent can't edit into a half-resized pattern, change it, then release.
    final lock = await _svc.acquireLock('pattern');
    if (lock.op != LiveOp.ok) {
      await _applyResult(lock);
      if (mounted) setState(() => _busy = false);
      return;
    }
    final res = await _svc.setPatternLength(d.version, weeks);
    await _svc.releaseLock();
    if (mounted) setState(() => _busy = false);
    await _applyResult(res);
  }

  Future<void> _tapDay(int weekIndex, int dayIndex) async {
    final d = _data;
    if (d == null) return;
    if (_scheduleLockedByOther) {
      _toast('Your co-parent is editing the whole schedule right now.');
      return;
    }
    final lockedBy = d.dayLockedBy(weekIndex, dayIndex);
    if (lockedBy != null && lockedBy.toLowerCase() != _me) {
      _toast('Your co-parent is editing that day right now.');
      return;
    }
    HapticFeedback.selectionClick();
    // Presence lock for the day (best-effort; the version check is the real guard).
    final got = await _svc.acquireDayLock(weekIndex, dayIndex);
    if (!got) {
      _toast('Your co-parent just started editing that day.');
      await _refresh();
      return;
    }
    if (!mounted) return;
    await _openDayEditor(weekIndex, dayIndex);
    await _svc.releaseDayLock(weekIndex, dayIndex);
    await _refresh();
  }

  Future<void> _openDayEditor(int weekIndex, int dayIndex) async {
    final existing = _data?.dayAt(weekIndex, dayIndex);
    var parent = existing?.parentAssignment ?? 'None';
    TimeOfDay? time = _tod(existing?.transferTime);

    final result = await showModalBottomSheet<_DayEdit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final palette = ctx.palette;
        return StatefulBuilder(builder: (ctx, setSheet) {
          Widget parentBtn(String value, String label, Color color) {
            final sel = parent == value;
            return Expanded(
              child: GestureDetector(
                onTap: () => setSheet(() => parent = value),
                child: Container(
                  height: 56,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: value == 'None' ? Colors.transparent : color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel ? AppColors.primaryBlue : palette.border,
                      width: sel ? 3 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(label,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                  ),
                ),
              ),
            );
          }

          return Container(
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
                left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 5, margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                Text(
                  (_data?.patternLength ?? 1) > 1 ? 'Week ${weekIndex + 1} · ${_dayNames[dayIndex]}' : _dayNames[dayIndex],
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary),
                ),
                const SizedBox(height: 4),
                Text('Who has the child this day?', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                const SizedBox(height: 14),
                Row(children: [
                  parentBtn('Husband', 'Dad', AppColors.parentDad),
                  parentBtn('Wife', 'Mom', AppColors.parentMom),
                  parentBtn('Both', 'Both', AppColors.parentBoth),
                  parentBtn('None', 'None', Colors.transparent),
                ]),
                const SizedBox(height: 16),
                // Optional handoff time
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: time ?? const TimeOfDay(hour: 9, minute: 0));
                    if (picked != null) setSheet(() => time = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: palette.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.schedule, size: 20),
                      const SizedBox(width: 10),
                      Text(time == null ? 'Add handoff time (optional)' : 'Handoff: ${time!.format(ctx)}',
                          style: TextStyle(fontSize: 15, color: palette.textPrimary)),
                      const Spacer(),
                      if (time != null)
                        GestureDetector(
                          onTap: () => setSheet(() => time = null),
                          child: Icon(Icons.close, size: 18, color: palette.textSecondary),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(_DayEdit(parent, time)),
                    child: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );

    if (result == null || !mounted) return;
    final d = _data;
    if (d == null) return;
    setState(() => _busy = true);
    final res = await _svc.upsertDay(
      d.version,
      LiveDay(
        weekIndex: weekIndex,
        dayIndex: dayIndex,
        parentAssignment: result.parent,
        transferTime: result.time == null ? null : _todStr(result.time!),
      ),
    );
    if (mounted) setState(() => _busy = false);
    await _applyResult(res);
  }

  Future<void> _agree() async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await _svc.agree();
    if (mounted) setState(() => _busy = false);
    await _applyResult(res);
  }

  // Onboarding only: continue WITHOUT requiring agreement. The first parent builds the
  // schedule and proceeds — the co-parent may not have joined yet; they agree later, in
  // the main-app editor. One-shot acknowledgement gates the onboarding step.
  void _continue() {
    OnboardingState.scheduleAcknowledged = true;
    advanceOnboarding(context);
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  static TimeOfDay? _tod(String? s) {
    if (s == null || s.isEmpty) return null;
    final p = s.split(':');
    if (p.length < 2) return null;
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0);
  }

  static String _todStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  static Color _fill(String p) => switch (p) {
        'Husband' => AppColors.parentDad,
        'Wife' => AppColors.parentMom,
        'Both' => AppColors.parentBoth,
        _ => Colors.transparent,
      };

  String _shortName(String email) {
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _noPartner
                ? _centeredMessage(context, 'Link your co-parent first to start building your schedule together.')
                : _body(context),
      ),
    );
  }

  Widget _centeredMessage(BuildContext context, String msg) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(msg, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: context.palette.textSecondary)),
        ),
      );

  Widget _body(BuildContext context) {
    final d = _data!;
    return Stack(
      children: [
        Column(
          children: [
            _header(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statusBar(context, d),
                    const SizedBox(height: 12),
                    _weekLengthRow(context, d),
                    const SizedBox(height: 12),
                    _legend(context),
                    const SizedBox(height: 12),
                    for (int w = 0; w < d.patternLength; w++) ...[
                      _weekCard(context, d, w),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 8),
                    if (widget.isOnboarding) _continueBar(context) else _agreeBar(context, d),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Live whole-schedule lock overlay.
        if (_scheduleLockedByOther) _lockOverlay(context, d),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          if (!widget.isOnboarding)
            IconButton(
              icon: Icon(Icons.arrow_back, color: palette.textPrimary),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          Expanded(
            child: Text('Custody Schedule',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          ),
          if (_busy)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }

  Widget _statusBar(BuildContext context, LiveScheduleData d) {
    final palette = context.palette;
    final agreed = d.isAgreed;
    final color = agreed ? AppColors.successGreen : AppColors.warningAmber;
    final text = agreed
        ? 'Agreed — this is your active schedule.'
        : 'Live draft — both of you can edit. Tap Agree when it looks right.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(agreed ? Icons.check_circle : Icons.edit_calendar, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: palette.textPrimary))),
      ]),
    );
  }

  Widget _weekLengthRow(BuildContext context, LiveScheduleData d) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Expanded(
          child: Text('Schedule repeats every',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _weekOptions.contains(d.patternLength) ? d.patternLength : 1,
            dropdownColor: palette.surfaceElevated,
            style: TextStyle(fontSize: 14, color: palette.textPrimary),
            items: [
              for (final w in _weekOptions)
                DropdownMenuItem(value: w, child: Text('$w ${w == 1 ? 'Week' : 'Weeks'}')),
            ],
            onChanged: _busy ? null : (v) { if (v != null && v != d.patternLength) _changeWeekLength(v); },
          ),
        ),
      ]),
    );
  }

  Widget _legend(BuildContext context) {
    final palette = context.palette;
    Widget item(Color c, String label, {bool outline = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: outline ? Colors.transparent : c,
              border: outline ? Border.all(color: palette.border) : null,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
        ]);
    return Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 8, children: [
      item(AppColors.parentDad, 'Dad'),
      item(AppColors.parentMom, 'Mom'),
      item(AppColors.parentBoth, 'Both'),
      item(Colors.transparent, 'None', outline: true),
    ]);
  }

  Widget _weekCard(BuildContext context, LiveScheduleData d, int weekIndex) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.patternLength > 1) ...[
            Text('Week ${weekIndex + 1}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            const SizedBox(height: 8),
          ],
          Row(children: [
            for (int i = 0; i < 7; i++) ...[
              Expanded(
                child: Text(_dayNames[i].substring(0, 3),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: palette.textSecondary)),
              ),
              if (i < 6) const SizedBox(width: 4),
            ],
          ]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (int day = 0; day < 7; day++) ...[
              Expanded(child: _dayCell(context, d, weekIndex, day)),
              if (day < 6) const SizedBox(width: 4),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _dayCell(BuildContext context, LiveScheduleData d, int weekIndex, int dayIndex) {
    final palette = context.palette;
    final cell = d.dayAt(weekIndex, dayIndex);
    final parent = cell?.parentAssignment ?? 'None';
    final time = _tod(cell?.transferTime);
    final lockedBy = d.dayLockedBy(weekIndex, dayIndex);
    final lockedByOther = lockedBy != null && lockedBy.toLowerCase() != _me;

    return GestureDetector(
      onTap: () => _tapDay(weekIndex, dayIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 64,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: parent == 'None' ? Colors.transparent : _fill(parent),
          border: Border.all(
            color: lockedByOther ? AppColors.warningAmber : palette.border,
            width: lockedByOther ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            if (lockedByOther)
              const Align(alignment: Alignment.topCenter, child: Icon(Icons.lock, size: 12, color: AppColors.warningAmber))
            else if (parent == 'None')
              Center(
                child: Text('Tap to\nedit', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, color: palette.textSecondary)),
              ),
            if (time != null)
              const Align(
                alignment: Alignment.bottomCenter,
                child: Icon(Icons.schedule, size: 12, color: Color(0xFF111827)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _continueBar(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            "You can keep editing this anytime. Your co-parent will be able to review and agree once they join.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
        ),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _busy ? null : _continue,
            child: const Text('Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _agreeBar(BuildContext context, LiveScheduleData d) {
    final palette = context.palette;
    if (d.isAgreed) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.successGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.verified, color: AppColors.successGreen),
          const SizedBox(width: 10),
          Expanded(child: Text('You both agreed to this schedule.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.textPrimary))),
        ]),
      );
    }
    final iAgreed = (d.agreedByA?.toLowerCase() == _me) || (d.agreedByB?.toLowerCase() == _me);
    final otherAgreed = (d.agreedByA != null && d.agreedByA!.toLowerCase() != _me) ||
        (d.agreedByB != null && d.agreedByB!.toLowerCase() != _me);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (otherAgreed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Your co-parent has agreed — your turn.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.successGreen, fontWeight: FontWeight.w600)),
          ),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: iAgreed ? palette.surfaceElevated : AppColors.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: (_busy || iAgreed) ? null : _agree,
            child: Text(
              iAgreed ? 'Waiting for your co-parent…' : 'Agree to this schedule',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: iAgreed ? palette.textSecondary : Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _lockOverlay(BuildContext context, LiveScheduleData d) {
    final palette = context.palette;
    final kind = d.locked?.kind;
    final who = _shortName(d.locked?.by ?? 'Your co-parent');
    final what = switch (kind) {
      'template' => 'applying a template',
      'ai' => 'building the schedule with AI',
      _ => 'changing the schedule',
    };
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(20)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 16),
              Text('$who is $what',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const SizedBox(height: 6),
              Text('Hang tight — you can edit again in a moment.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DayEdit {
  final String parent;
  final TimeOfDay? time;
  _DayEdit(this.parent, this.time);
}
