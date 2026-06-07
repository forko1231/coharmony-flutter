import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/custody_models.dart';
import '../../models/location_models.dart';
import '../../navigation/app_navigator.dart';
import '../../services/custody_templates/pending_template_service.dart';
import '../../services/holiday_resolver.dart';
import '../../services/live_schedule_service.dart';
import '../../services/onboarding_state.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../ai/ai_chat_page.dart';
import 'day_editor_view.dart';
import 'editor_models.dart';
import 'override_editor_view.dart';
import 'templates/template_catalog_page.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';

/// The LIVE custody schedule editor — one shared schedule both co-parents edit in real
/// time. Replaces the proposal draft/submit/review flow. Same visual language as the old
/// CustodySchedulePage (week cards, tappable day cells, a bottom-sheet day editor,
/// special-day overrides, the floating action menu, the how-it-works walkthrough) but:
///   • edits hit /api/schedule/live with the current version (stale → reload),
///   • week-length + template/AI take the schedule-wide lock,
///   • locks + presence show LIVE (greyed days, a "co-parent is editing" overlay, and a
///     "your co-parent is also here" banner) via the WS ping + presence heartbeat,
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
  static const _guideSeenKey = 'live_editor_guide_seen';
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  LiveScheduleService get _svc => ServiceLocator.liveSchedule;
  String _me = '';

  LiveScheduleData? _data;
  List<PointOfInterest> _pois = const [];
  bool _loading = true;
  bool _noPartner = false;
  bool _busy = false; // a bulk/structural call is in flight (week length, template, agree)
  bool _introShown = false; // onboarding one-shot "co-parent already started" intro

  // Auto-commit (no Save button): day edits coalesce into _pendingDays and are sent
  // serialized + debounced. _saving drives the "Saving…/Saved" status; never blocks editing.
  final Map<String, LiveDay> _pendingDays = {};
  bool _sendingDays = false;
  bool _saving = false;
  bool _savedFlash = false;
  bool _catchingUp = false; // leaving the editor: blocking loader while pending saves finish
  int? _selWeek; // the day whose panel is open — shown with a blue border
  int? _selDay;
  // The docked editor panel (day or override). Non-modal: the grid stays scrollable +
  // tappable so you can switch days without closing; only the ✕ dismisses it.
  Widget? _dockedChild;
  Timer? _commitDebounce;
  Timer? _savedFlashTimer;
  // Per-day presence lock: while a day panel is open we hold a lock on that day so the
  // co-parent sees it locked and can't edit it. Heartbeated; released on close/switch.
  ({int w, int d})? _heldDayKey;
  Timer? _dayLockBeat;

  StreamSubscription<int>? _wsSub;
  Timer? _poll;
  Timer? _presence;

  @override
  void initState() {
    super.initState();
    _me = Preferences.getString('email').toLowerCase();
    WidgetsBinding.instance.addObserver(this);
    // Live updates: refetch when the co-parent pings us over the socket…
    _wsSub = _svc.onChanged.listen((_) => _refresh());
    // …and a gentle poll while the editor is open as the fallback (covers a dropped
    // socket and surfaces lock/presence changes within a few seconds).
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    // Presence: tell the co-parent we're in the editor (and pick up their presence).
    _presence = Timer.periodic(const Duration(seconds: 10), (_) => _beat());
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    _poll?.cancel();
    _presence?.cancel();
    _commitDebounce?.cancel();
    _savedFlashTimer?.cancel();
    _dayLockBeat?.cancel();
    // Best-effort release so we don't strand the day lock for the co-parent.
    final k = _heldDayKey;
    if (k != null) _svc.releaseDayLock(k.w, k.d);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _beat();
    }
  }

  // ── data ───────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _svc.get();
    // POIs power the "choose existing location" picker in the day/override editors.
    try {
      _pois = await ServiceLocator.location.getPois();
    } catch (_) {/* continue without saved locations */}
    if (!mounted) return;
    setState(() {
      _loading = false;
      _noPartner = r.op == LiveOp.noPartner;
      if (r.data != null) _data = r.data;
    });
    _beat(); // announce presence immediately on open
    _maybeShowIntroOrGuide();
  }

  void _maybeShowIntroOrGuide() {
    final d = _data;
    // Second-parent onboarding: if the co-parent already built + agreed a schedule, show
    // a one-shot "review it" intro before they edit/Continue. Otherwise, first-time users
    // get the how-it-works walkthrough.
    if (widget.isOnboarding && !_introShown && d != null && d.days.isNotEmpty && _partnerAgreed(d)) {
      _introShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showReviewIntro());
    } else if (!Preferences.getBool(_guideSeenKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showGuide());
    }
  }

  // True while we have unsent / in-flight day edits — refreshes must not stomp our
  // optimistic local state with stale server data during that window.
  bool get _localDirty => _pendingDays.isNotEmpty || _sendingDays || (_commitDebounce?.isActive ?? false);

  // Presence heartbeat — silent; just refresh our copy of the schedule (incl. who's here).
  Future<void> _beat() async {
    if (_busy || _localDirty || !mounted) return;
    final r = await _svc.presenceHeartbeat();
    if (!mounted || r.data == null || _localDirty) return;
    setState(() => _data = r.data);
  }

  // Silent refresh used by the WS ping / poll — don't flicker the spinner, and don't
  // stomp the screen while the user has a mutating call (or unsynced local edit) in flight.
  Future<void> _refresh() async {
    if (_busy || _localDirty || !mounted) return;
    final r = await _svc.get();
    if (!mounted || r.data == null || _localDirty) return;
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
        final wasAgreed = _data?.isAgreed ?? false;
        setState(() => _data = r.data);
        // If my edit reopened a schedule you'd both agreed to, say so — otherwise the
        // Agree button silently reappearing is confusing.
        if (wasAgreed && !(r.data?.isAgreed ?? false)) {
          _toast("Your change reopened the schedule — you'll both need to Agree again.");
        }
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

  // The co-parent is actively editing — either the whole schedule (template/AI/pattern) or
  // a specific day (they have its panel open).
  bool get _partnerEditing {
    if (_scheduleLockedByOther) return true;
    final d = _data;
    if (d == null) return false;
    for (final l in d.dayLocks) {
      if (l.by.toLowerCase() != _me) return true;
    }
    return false;
  }

  // The co-parent has the editor open (heartbeat fresh) but isn't mid-edit.
  bool get _partnerHere => _data?.partnerPresent(_me) ?? false;

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

  // Start-from-a-template: holds the schedule-wide lock for the whole pick-and-apply
  // (the co-parent sees the "applying a template" overlay and can't edit), heartbeating
  // it while the catalog is open, then bulk-applies the generated pattern + releases.
  Future<void> _useTemplate() async {
    if (_busy) return;
    final lock = await _svc.acquireLock('template');
    if (lock.op != LiveOp.ok) {
      await _applyResult(lock);
      return;
    }
    setState(() => _busy = true);
    final hb = Timer.periodic(const Duration(seconds: 25), (_) => _svc.heartbeatLock());
    PendingTemplateService.clear();
    PendingTemplateService.isOnboardingMode = false; // hand the result back to us, don't make a proposal
    if (!mounted) {
      hb.cancel();
      await _svc.releaseLock();
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplateCatalogPage()));
    hb.cancel();

    final picked = PendingTemplateService.tryConsume();
    if (picked == null) {
      await _svc.releaseLock(); // user backed out
      if (mounted) setState(() => _busy = false);
      await _refresh();
      return;
    }
    final gen = picked.template.buildPattern(picked.answers);
    final days = [
      for (final d in gen)
        LiveDay(
          weekIndex: d.weekIndex,
          dayIndex: d.dayIndex,
          parentAssignment: d.parentAssignment,
          transferTime: d.transferTime,
          transferEndTime: d.transferEndTime,
        ),
    ];
    final apply = await _svc.applyBulk('template', picked.template.patternLengthWeeks, days, const []);
    await _svc.releaseLock();
    if (mounted) setState(() => _busy = false);
    await _applyResult(apply);
  }

  // Open the AI assistant; it applies to the live schedule under the lock. Refresh on return.
  Future<void> _openAi() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AiChatPage(chatContext: 'schedule')));
    if (!mounted) return;
    await _refresh();
  }

  // Open the template catalog from the floating menu (same flow as the inline CTA).
  Future<void> _openTemplates() => _useTemplate();

  void _tapDay(int weekIndex, int dayIndex) {
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
    _openDayEditor(weekIndex, dayIndex);
  }

  // The day editor is a DOCKED panel — not a modal. The grid stays scrollable/tappable so
  // you can switch to another day without closing (tapping just rebuilds the panel for that
  // day). It AUTO-COMMITS every change live (no Save button); only the ✕ dismisses it.
  void _openDayEditor(int weekIndex, int dayIndex) {
    final d0 = _data;
    if (d0 == null) return;
    final existing = d0.dayAt(weekIndex, dayIndex);
    final input = ProposalDayDto(
      weekIndex: weekIndex,
      dayIndex: dayIndex,
      parentAssignment: existing?.parentAssignment ?? 'None',
      transferTime: existing?.transferTime,
      transferEndTime: existing?.transferEndTime,
      transferLatitude: existing?.transferLatitude,
      transferLongitude: existing?.transferLongitude,
      transferLocationName: existing?.transferLocationName,
      transferAddress: existing?.transferAddress,
    );
    setState(() {
      _selWeek = weekIndex;
      _selDay = dayIndex;
      _dockedChild = DayEditorView(
        // Unique key per (week, day) so switching days rebuilds the editor State with the
        // new day's data instead of reusing the previous day's fields.
        key: ValueKey('day-$weekIndex-$dayIndex'),
        weekIndex: weekIndex,
        dayIndex: dayIndex,
        title: (d0.patternLength) > 1
            ? 'Week ${weekIndex + 1} · ${_dayNames[dayIndex]}'
            : _dayNames[dayIndex],
        data: input,
        baseline: null,
        pois: _pois,
        onCommit: (c) => _commitDay(weekIndex, dayIndex, c),
        onClose: _closeDock,
      );
    });
    // Hold a presence lock on this day so the co-parent sees it locked.
    _holdDayLock(weekIndex, dayIndex);
  }

  // Acquire (and keep alive) the per-day lock for the open day, releasing any previous one.
  Future<void> _holdDayLock(int weekIndex, int dayIndex) async {
    await _releaseHeldDayLock();
    _heldDayKey = (w: weekIndex, d: dayIndex);
    final ok = await _svc.acquireDayLock(weekIndex, dayIndex);
    if (!mounted) return;
    if (!ok) {
      // Lost the race — the co-parent grabbed it first.
      _heldDayKey = null;
      _toast('Your co-parent just started editing that day.');
      _closeDock();
      await _refresh();
      return;
    }
    _dayLockBeat?.cancel();
    _dayLockBeat = Timer.periodic(const Duration(seconds: 30), (_) {
      final k = _heldDayKey;
      if (k != null) _svc.acquireDayLock(k.w, k.d); // re-acquire extends the 45s TTL
    });
  }

  Future<void> _releaseHeldDayLock() async {
    _dayLockBeat?.cancel();
    final k = _heldDayKey;
    _heldDayKey = null;
    if (k != null) await _svc.releaseDayLock(k.w, k.d);
  }

  // Close the docked panel (only entry point is the ✕). Release the day lock + flush commits.
  void _closeDock() {
    if (!mounted) return;
    setState(() { _dockedChild = null; _selWeek = null; _selDay = null; });
    _releaseHeldDayLock();
    _flushDayCommits();
  }

  // ── Auto-commit pipeline ──────────────────────────────────────────────────────
  // Each change coalesces into _pendingDays (latest per day wins), debounced so typing an
  // address doesn't fire per keystroke, then drained serially so versions stay consistent.
  void _commitDay(int weekIndex, int dayIndex, DayEditCommit c) {
    final day = LiveDay(
      weekIndex: weekIndex,
      dayIndex: dayIndex,
      parentAssignment: c.parent,
      transferTime: c.transferTime == null ? null : _todStr(c.transferTime!),
      transferEndTime: c.transferEndTime == null ? null : _todStr(c.transferEndTime!),
      transferLatitude: c.location?.latitude,
      transferLongitude: c.location?.longitude,
      transferLocationName: c.location?.name,
      transferAddress: c.location?.address,
    );
    _pendingDays['$weekIndex,$dayIndex'] = day;
    // Optimistic: recolor the cell immediately; the network write follows.
    if (mounted) {
      setState(() {
        if (_data != null) _data = _data!.withDay(day);
        _saving = true;
      });
    }
    _commitDebounce?.cancel();
    _commitDebounce = Timer(const Duration(milliseconds: 150), _drainDayCommits);
  }

  void _flushDayCommits() {
    _commitDebounce?.cancel();
    _drainDayCommits();
  }

  Future<void> _drainDayCommits() async {
    if (_sendingDays) return;
    _sendingDays = true;
    var guard = 0;
    while (_pendingDays.isNotEmpty && guard++ < 50) {
      final key = _pendingDays.keys.first;
      final day = _pendingDays.remove(key)!;
      final res = await _svc.upsertDay(_data?.version ?? 0, day);
      if (!mounted) { _sendingDays = false; return; }
      if (res.op == LiveOp.ok) {
        final wasAgreed = _data?.isAgreed ?? false;
        setState(() => _data = res.data);
        if (wasAgreed && !(res.data?.isAgreed ?? false)) {
          _toast("Your change reopened the schedule — you'll both need to Agree again.");
        }
      } else if (res.op == LiveOp.conflict) {
        // Fetch the latest version directly (can't use _refresh — it's gated while dirty),
        // then resend this day on top of it.
        final latest = await _svc.get();
        if (!mounted) { _sendingDays = false; return; }
        if (latest.data != null) setState(() => _data = latest.data);
        // If the co-parent just took the whole-schedule lock (template/AI), stop —
        // resending would just conflict until they're done. Their work wins; drop ours.
        if (_scheduleLockedByOther) {
          _pendingDays.clear();
          _toast('Your co-parent is editing the whole schedule — try again in a moment.');
          break;
        }
        _pendingDays[key] = day;
      } else if (res.op == LiveOp.locked || res.op == LiveOp.lockedDay) {
        _pendingDays.clear();
        await _applyResult(res); // schedule/day locked → message, drop
        break;
      } else {
        await _applyResult(res); // error → message, drop it
      }
    }
    _sendingDays = false;
    if (mounted) {
      setState(() { _saving = false; _savedFlash = true; });
      _savedFlashTimer?.cancel();
      _savedFlashTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _savedFlash = false);
      });
    }
  }

  // ── Overrides (special days) ──────────────────────────────────────────────────
  // Also a docked panel. Unlike the day editor this keeps its Add/Update button (it builds
  // a record around a date), then applies + closes.
  void _openOverrideEditor({LiveOverride? existing}) {
    if (_scheduleLockedByOther) {
      _toast('Your co-parent is editing the whole schedule right now.');
      return;
    }
    final exDto = existing == null
        ? null
        : ProposalOverrideDto(
            dateKey: existing.dateKey,
            month: existing.month,
            day: existing.day,
            parentAssignment: existing.parentAssignment,
            transferTime: existing.transferTime,
            transferEndTime: existing.transferEndTime,
            description: existing.description,
            isAnnual: existing.isAnnual,
            holidayRule: existing.holidayRule,
            alternationMode: existing.alternationMode,
            alternationStartParent: existing.alternationStartParent,
            transferLatitude: existing.transferLatitude,
            transferLongitude: existing.transferLongitude,
            transferLocationName: existing.transferLocationName,
            transferAddress: existing.transferAddress,
          );
    _releaseHeldDayLock(); // override editor isn't a grid day
    setState(() {
      _selWeek = null;
      _selDay = null;
      _dockedChild = OverrideEditorView(
        key: ValueKey('override-${existing?.dateKey ?? 'new'}'),
        existingDateKey: existing?.dateKey,
        existing: exDto,
        baseline: null,
        pois: _pois,
        onApply: (r) => _applyOverrideResult(existing, r),
        onClose: _closeDock,
      );
    });
  }

  Future<void> _applyOverrideResult(LiveOverride? existing, OverrideDayEditResult result) async {
    _closeDock();
    final d = _data;
    if (d == null) return;
    setState(() => _busy = true);
    var res = await _svc.upsertOverride(
      d.version,
      LiveOverride(
        dateKey: result.dateKey,
        month: result.selectedDate.month,
        day: result.selectedDate.day,
        parentAssignment: result.parent,
        transferTime: result.transferTime == null ? null : _todStr(result.transferTime!),
        transferEndTime: result.transferEndTime == null ? null : _todStr(result.transferEndTime!),
        description: result.description,
        isAnnual: result.isAnnual,
        holidayRule: result.holidayRule,
        alternationMode: result.alternationMode,
        alternationStartParent: result.alternationStartParent,
        transferLatitude: result.transferLocation?.latitude,
        transferLongitude: result.transferLocation?.longitude,
        transferLocationName: result.transferLocation?.name,
        transferAddress: result.transferLocation?.address,
      ),
    );
    // If the date changed on an existing override, remove the stale old-date entry.
    if (res.ok && existing != null && result.dateWasChanged) {
      final v = res.data?.version ?? d.version;
      res = await _svc.deleteOverride(v, existing.dateKey);
    }
    if (mounted) setState(() => _busy = false);
    await _applyResult(res);
  }

  Future<void> _deleteOverride(LiveOverride o) async {
    final d = _data;
    if (d == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove special day?'),
        content: Text('Remove "${_overrideLabel(o)}" from the schedule?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove', style: TextStyle(color: AppColors.dangerRed))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final res = await _svc.deleteOverride(d.version, o.dateKey);
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

  // Onboarding: Continue = THIS parent agrees, then proceed. The co-parent may not have
  // joined yet — that's fine; they agree later. If the co-parent already agreed and the
  // schedule is unchanged, this makes it mutually agreed; if this parent edited, the
  // co-parent's prior agreement was already cleared server-side and they'll re-agree.
  Future<void> _continue() async {
    if (_busy) return;
    await _flushAndWait(); // commit any pending day edits before leaving onboarding
    if (!mounted) return;
    setState(() => _busy = true);
    await _svc.agree(); // best-effort; we proceed regardless of network result
    OnboardingState.scheduleAcknowledged = true;
    if (mounted) advanceOnboarding(context);
  }

  bool _partnerAgreed(LiveScheduleData d) {
    final a = d.agreedByA?.toLowerCase();
    final b = d.agreedByB?.toLowerCase();
    return (a != null && a != _me) || (b != null && b != _me);
  }

  Future<void> _showReviewIntro() async {
    if (!mounted) return;
    final palette = context.palette;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Your co-parent started a schedule'),
        content: Text(
          'Your co-parent already set up a custody schedule. Review it below — you can '
          'make any changes you need. When you tap Continue you agree to it; if you edit '
          'anything, they\'ll be asked to re-confirm.',
          style: TextStyle(fontSize: 14, height: 1.4, color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Review schedule'),
          ),
        ],
      ),
    );
  }

  void _showGuide() {
    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (_) => const _GuideDialog(),
    ).then((_) => Preferences.setBool(_guideSeenKey, true));
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

  String _overrideLabel(LiveOverride o) {
    if (o.holidayRule != null && o.holidayRule!.isNotEmpty) {
      return HolidayResolver.getDisplayName(o.holidayRule!);
    }
    if (o.description != null && o.description!.isNotEmpty) return o.description!;
    return '${_months[(o.month.clamp(1, 12)) - 1]} ${o.day}';
  }

  Widget _grabber() => Center(
        child: Container(
          width: 40,
          height: 5,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(3)),
        ),
      );

  // A live request is in flight (day commit drain or a bulk op) — block the UI so nothing
  // overlaps it; the header shows "Saving…".
  bool get _inFlight => _busy || _sendingDays;
  bool get _hasUnsaved => _inFlight || _pendingDays.isNotEmpty || (_commitDebounce?.isActive ?? false);

  // Don't leave the editor until every pending change is committed (backup so nothing is
  // lost). Flush the queue, then wait for it to settle (with the blocking loader showing).
  Future<void> _flushAndWait() async {
    _commitDebounce?.cancel();
    if (!(_sendingDays || _busy || _pendingDays.isNotEmpty)) return; // nothing behind
    if (mounted) setState(() => _catchingUp = true);
    if (_pendingDays.isNotEmpty && !_sendingDays) {
      unawaited(_drainDayCommits());
    }
    var guard = 0;
    while ((_sendingDays || _busy || _pendingDays.isNotEmpty) && mounted && guard++ < 200) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (mounted) setState(() => _catchingUp = false);
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopScope(
      // Block the back/pop while anything is unsaved; flush + wait, then pop ourselves.
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _flushAndWait();
        if (mounted) navigator.pop(result);
      },
      child: Scaffold(
        backgroundColor: palette.background,
        // No outer SafeArea — the docked panel must reach the true screen bottom (no gap
        // under it on iOS). Insets are handled per-section: header (top), scroll (bottom),
        // FAB (bottom), and the panel's own SafeArea(top:false).
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _noPartner
                ? SafeArea(
                    child: _centeredMessage(context, 'Link your co-parent first to start building your schedule together.'))
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
    final docked = _dockedChild != null;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    // When the panel is docked, reserve room at the bottom of the scroll so the LAST week /
    // overrides can scroll clear above the panel (panel is capped at 55% of the screen).
    // Otherwise pad for the FAB + the home-indicator inset (no outer SafeArea anymore).
    final bottomPad = docked ? MediaQuery.of(context).size.height * 0.55 + 24 : 96.0 + safeBottom;
    return Stack(
      children: [
        Column(
          children: [
            _header(context),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statusBar(context, d),
                    if (_partnerEditing || _partnerHere) ...[
                      const SizedBox(height: 10),
                      _presenceBanner(context, d),
                    ],
                    const SizedBox(height: 12),
                    _weekLengthRow(context, d),
                    const SizedBox(height: 12),
                    _legend(context),
                    const SizedBox(height: 12),
                    _templateCta(context),
                    for (int w = 0; w < d.patternLength; w++) ...[
                      _weekCard(context, d, w),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 4),
                    _overridesSection(context, d),
                    const SizedBox(height: 12),
                    if (widget.isOnboarding) _continueBar(context) else _agreeBar(context, d),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Live whole-schedule lock overlay.
        if (_scheduleLockedByOther) _lockOverlay(context, d),
        // Keep a way OUT even while the co-parent holds the whole-schedule lock (the overlay
        // covers the header back button) — render a back button on top of it.
        if (_scheduleLockedByOther && !widget.isOnboarding)
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 4,
            left: 4,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: context.palette.textPrimary),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        // Docked editor panel (day / override) — non-modal; grid stays usable above it.
        if (docked)
          Positioned(left: 0, right: 0, bottom: 0, child: _dockedPanel(context)),
        // Only when LEAVING: block + show a loader while we catch up on pending saves.
        if (_catchingUp) _catchUpOverlay(context),
        // Floating action menu (AI / Templates / Help) — hidden while the panel is docked.
        if (!docked)
          Positioned(
            right: 20,
            bottom: 24 + safeBottom,
            child: _EditorActionMenu(onAi: _openAi, onTemplates: _openTemplates, onHelp: _showGuide),
          ),
      ],
    );
  }

  // The docked editor panel: a bottom-anchored, NON-modal sheet (no barrier) so the grid
  // above stays scrollable/tappable — you can switch days without closing. Capped height,
  // scrolls internally, rides above the keyboard.
  Widget _dockedPanel(BuildContext context) {
    final palette = context.palette;
    final maxH = MediaQuery.of(context).size.height * 0.55;
    return Material(
      color: palette.surfaceElevated,
      elevation: 16,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Padding(
            padding: EdgeInsets.only(
                left: 16, right: 16, top: 8, bottom: 12 + MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _grabber(),
                  _dockedChild ?? const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.viewPaddingOf(context).top + 8, 16, 12),
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
          _saveStatus(context),
        ],
      ),
    );
  }

  // Live "Saving… / Saved" pill (auto-commit) — also covers bulk ops via _busy.
  Widget _saveStatus(BuildContext context) {
    final palette = context.palette;
    if (_saving || _busy) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 6),
        Text('Saving…', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
      ]);
    }
    if (_savedFlash) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, size: 16, color: AppColors.successGreen),
        const SizedBox(width: 4),
        const Text('Saved', style: TextStyle(fontSize: 12, color: AppColors.successGreen)),
      ]);
    }
    return const SizedBox(width: 0, height: 18);
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

  // "Your co-parent is also here / editing" — the live presence banner.
  Widget _presenceBanner(BuildContext context, LiveScheduleData d) {
    final name = _shortName(d.partnerEmail(_me));
    final editing = _partnerEditing;
    final color = editing ? AppColors.warningAmber : AppColors.successGreen;
    final text = editing ? '$name is editing right now…' : '$name is also here';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        if (editing)
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
        else
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
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

  Widget _templateCta(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _useTemplate,
        icon: const Icon(Icons.dashboard_customize, size: 18),
        label: const Text('Start from a template'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: palette.border),
          foregroundColor: palette.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
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
    final selected = _selWeek == weekIndex && _selDay == dayIndex;
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
            color: selected
                ? AppColors.primaryBlue
                : lockedByOther
                    ? AppColors.warningAmber
                    : palette.border,
            width: (selected || lockedByOther) ? (selected ? 3 : 2) : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            if (lockedByOther)
              const Align(
                  alignment: Alignment.topCenter,
                  child: Icon(Icons.lock, size: 12, color: AppColors.warningAmber))
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

  // Special days (overrides) — list + add button.
  Widget _overridesSection(BuildContext context, LiveScheduleData d) {
    final palette = context.palette;
    final overrides = [...d.overrides]..sort((a, b) {
        final am = a.month * 100 + a.day, bm = b.month * 100 + b.day;
        return am.compareTo(bm);
      });
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.celebration, size: 18, color: AppColors.dangerRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Holidays & special days',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            ),
          ]),
          if (overrides.isEmpty) ...[
            const SizedBox(height: 8),
            Text('Add a date that overrides the normal pattern — like Christmas → always Mom.',
                style: TextStyle(fontSize: 13, color: palette.textSecondary)),
          ] else
            for (final o in overrides) _overrideRow(context, o),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openOverrideEditor(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a special day'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              side: BorderSide(color: palette.border),
              foregroundColor: palette.textPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overrideRow(BuildContext context, LiveOverride o) {
    final palette = context.palette;
    final color = _fill(o.parentAssignment);
    final dateText = (o.holidayRule != null && o.holidayRule!.isNotEmpty)
        ? '${_months[(o.month.clamp(1, 12)) - 1]} ${o.day}${o.isAnnual ? ' · yearly' : ''}'
        : '${_months[(o.month.clamp(1, 12)) - 1]} ${o.day}';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _busy ? null : () => _openOverrideEditor(existing: o),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: o.parentAssignment == 'None' ? Colors.transparent : color,
              border: o.parentAssignment == 'None' ? Border.all(color: palette.border) : null,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_overrideLabel(o),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.textPrimary)),
                Text(dateText, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: palette.textSecondary),
            onPressed: _busy ? null : () => _deleteOverride(o),
          ),
        ]),
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

  // Shown only while leaving the editor — blocks input and waits for pending saves to land.
  Widget _catchUpOverlay(BuildContext context) {
    final palette = context.palette;
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.35),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(20)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(height: 16),
                Text('Saving your changes…',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: palette.textPrimary)),
              ]),
            ),
          ),
        ),
      ),
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

// ── Floating action menu (hamburger that opens upward) ───────────────────────────
/// A menu button (bottom-right) that expands upward to expose the AI assistant, the
/// template catalog, and the how-it-works guide.
class _EditorActionMenu extends StatefulWidget {
  const _EditorActionMenu({required this.onAi, required this.onTemplates, required this.onHelp});
  final VoidCallback onAi;
  final VoidCallback onTemplates;
  final VoidCallback onHelp;

  @override
  State<_EditorActionMenu> createState() => _EditorActionMenuState();
}

class _EditorActionMenuState extends State<_EditorActionMenu> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);
  void _run(VoidCallback action) {
    setState(() => _open = false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomRight,
          child: _open
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _item('Templates', 'icon_calendar', const [Color(0xFF10B981), Color(0xFF059669)],
                        () => _run(widget.onTemplates)),
                    const SizedBox(height: 12),
                    _item('AI Assistant', 'icon_sparkle', const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        () => _run(widget.onAi)),
                    const SizedBox(height: 12),
                    _item('How it works', '?', const [Color(0xFF3B82F6), Color(0xFF2563EB)],
                        () => _run(widget.onHelp)),
                    const SizedBox(height: 16),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _open
                      ? const [Color(0xFF6B7280), Color(0xFF4B5563)]
                      : const [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4), offset: const Offset(0, 4), blurRadius: 12),
              ],
            ),
            child: Center(child: Icon(_open ? Icons.close : Icons.menu, color: Colors.white, size: 26)),
          ),
        ),
      ],
    );
  }

  Widget _item(String label, String icon, List<Color> grad, VoidCallback onTap) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          ),
          const SizedBox(width: 10),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grad),
              borderRadius: BorderRadius.circular(23),
              boxShadow: [BoxShadow(color: grad.last.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Center(
              child: icon.startsWith('icon_')
                  ? AppIcon(icon, size: 22, color: Colors.white)
                  : Text(icon, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── How-it-works walkthrough ─────────────────────────────────────────────────────
/// Which example illustration a guide step shows (above the title).
enum _Vis { none, welcome, cycle, tapDay, times, special, live, conflict, menu }

class _GuideStep {
  final String icon; // 'icon_*' name, or a literal glyph like '?'
  final Color iconBg;
  final Color iconTint;
  final String title;
  final String body;
  final String? note;
  final _Vis visual;
  const _GuideStep(this.icon, this.iconBg, this.iconTint, this.title, this.body,
      {this.note, this.visual = _Vis.none});
}

class _GuideDialog extends StatefulWidget {
  const _GuideDialog();

  @override
  State<_GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<_GuideDialog> {
  int _step = 0;

  static const _steps = <_GuideStep>[
    _GuideStep('?', AppColors.iconBgBlue, AppColors.primaryBlue, 'Your custody calendar',
        "This is where you and your co-parent build your kids' schedule — together, live. We'll show you how in a few quick taps.",
        visual: _Vis.welcome, note: 'Tap the menu button (bottom-right) → "How it works" to replay this anytime.'),
    _GuideStep('icon_refresh', AppColors.iconBgBlue, AppColors.primaryBlue, 'What is a "cycle"?',
        'A cycle is a pattern that repeats — like the days of the week always go Mon, Tue… then start over. You set up one or two weeks, and they repeat forever.',
        visual: _Vis.cycle, note: 'Most families use a 1- or 2-week cycle.'),
    _GuideStep('icon_calendar', Color(0xFFFCE7F3), Color(0xFFBE185D), 'Tap a day to set it',
        'Tap any day, then choose who has the kids: Dad, Mom, Both, or None. The day changes colour right away.',
        visual: _Vis.tapDay),
    _GuideStep('icon_clock', AppColors.iconBgGreen, AppColors.successGreen, 'Set handoff times',
        'For each day you can set when custody starts and ends — and even the handoff location — so pickup and drop-off are crystal clear.',
        visual: _Vis.times),
    _GuideStep('icon_gift', AppColors.iconBgRed, AppColors.dangerRed, 'Holidays & special days',
        'Special dates can override the normal pattern. For example: Christmas → always Mom, July 4th → always Dad. Add them under "Holidays & special days".',
        visual: _Vis.special),
    _GuideStep('icon_handshake', AppColors.iconBgGreen, AppColors.successGreen, 'You both edit it live',
        'There are no proposals — you share ONE schedule and edit it together in real time. When it looks right, you each tap Agree; once you BOTH agree it becomes your official schedule.',
        visual: _Vis.live),
    _GuideStep('icon_alert', AppColors.iconBgYellow, AppColors.warningAmber, 'Editing at the same time',
        "When your co-parent is in the editor you'll see \"they're also here\". If they're changing a day or applying a template, it locks briefly so edits don't collide — and if you both change something, we keep the latest and let you reload.",
        visual: _Vis.conflict),
    _GuideStep('icon_sparkle', AppColors.iconBgPurple, AppColors.accentPurple, 'Need a hand? Use the menu',
        'Tap the menu button (bottom-right) for the AI assistant — it can build a whole schedule for you — and ready-made Templates you can apply in one tap.',
        visual: _Vis.menu),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final s = _steps[_step];
    final isLast = _step == _steps.length - 1;
    return Dialog(
      backgroundColor: palette.surfaceElevated,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < _steps.length; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _step ? AppColors.primaryBlue : const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _hero(context, s),
                    const SizedBox(height: 16),
                    Text(s.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    const SizedBox(height: 8),
                    Text(s.body,
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: palette.textSecondary)),
                    if (s.note != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(s.note!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: palette.textSecondary)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textSecondary,
                      side: BorderSide(color: palette.border, width: 2),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () => _step == 0 ? Navigator.of(context).pop() : setState(() => _step--),
                    child: Text(_step == 0 ? 'Skip' : 'Back', style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () {
                      if (isLast) {
                        Navigator.of(context).pop();
                      } else {
                        setState(() => _step++);
                      }
                    },
                    child: Text(isLast ? 'Got It!' : 'Next',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Step illustrations ───────────────────────────────────────────────────────
  static const _cDad = Color(0xFFBFDBFE);
  static const _cMom = Color(0xFFFCE7F3);
  static const _cBoth = Color(0xFFE9D5FF);
  static const _cNone = Color(0xFFF1F5F9);
  static const _cDadInk = Color(0xFF1E40AF);
  static const _cMomInk = Color(0xFFBE185D);
  static const _muted = Color(0xFF94A3B8);

  Widget _hero(BuildContext context, _GuideStep s) {
    final v = _visual(context, s.visual);
    if (v != null) return v;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: s.iconBg, borderRadius: BorderRadius.circular(16)),
      child: Center(
        child: s.icon.startsWith('icon_')
            ? AppIcon(s.icon, size: 32, color: s.iconTint)
            : Text(s.icon, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: s.iconTint)),
      ),
    );
  }

  Widget? _visual(BuildContext context, _Vis v) {
    switch (v) {
      case _Vis.none:
        return null;
      case _Vis.welcome:
        return _card(context, Column(children: [_legend(), const SizedBox(height: 12), _week('DDMMMBB')]));
      case _Vis.cycle:
        return _card(
          context,
          Column(children: [
            _legend(),
            const SizedBox(height: 12),
            _week('DDMMMDD', label: 'WEEK 1'),
            const SizedBox(height: 8),
            _week('MMDDDMM', label: 'WEEK 2'),
            const SizedBox(height: 10),
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.refresh, size: 15, color: Color(0xFF2563EB)),
              SizedBox(width: 6),
              Text('then it repeats…', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF2563EB))),
            ]),
            const SizedBox(height: 10),
            Opacity(opacity: 0.45, child: _week('DDMMMDD', label: 'WEEK 1 AGAIN')),
          ]),
        );
      case _Vis.tapDay:
        return _card(
          context,
          Column(children: [
            _week('DDNMMBB', ring: 2),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              _choice('Dad', _cDad, _cDadInk),
              _choice('Mom', _cMom, _cMomInk),
              _choice('Both', _cBoth, const Color(0xFF7E22CE)),
              _choice('None', _cNone, _muted),
            ]),
          ]),
        );
      case _Vis.times:
        return _card(
          context,
          Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: _cDad, borderRadius: BorderRadius.circular(12)),
              child: const Text('WED · Dad has the kids',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _cDadInk)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.access_time, size: 14, color: Color(0xFF16A34A)),
                SizedBox(width: 6),
                Text('3:00 PM  →  6:00 PM',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
              ]),
            ),
          ]),
        );
      case _Vis.special:
        return _card(
          context,
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Column(children: [
              Text('🎄', style: TextStyle(fontSize: 28)),
              SizedBox(height: 2),
              Text('Dec 25', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
            ]),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Icons.arrow_forward, size: 18, color: _muted)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: _cMom, borderRadius: BorderRadius.circular(12)),
              child: const Text('Always Mom', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _cMomInk)),
            ),
          ]),
        );
      case _Vis.live:
        return _card(
          context,
          Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _avatar('You', const Color(0xFF3B82F6)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Icons.sync_alt, size: 18, color: _muted)),
              _avatar('Co-parent', const Color(0xFFEC4899)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(20)),
              child: const Text('Both agree → official schedule',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
            ),
          ]),
        );
      case _Vis.conflict:
        return _card(
          context,
          Column(children: [
            _week('DDMMMDD', changed: {1}, conflict: {4}),
            const SizedBox(height: 12),
            Wrap(spacing: 14, alignment: WrapAlignment.center, children: [
              _dot(const Color(0xFFF59E0B), 'Your change'),
              _dot(const Color(0xFFEF4444), 'They\'re editing'),
            ]),
          ]),
        );
      case _Vis.menu:
        return _card(
          context,
          Column(mainAxisSize: MainAxisSize.min, children: [
            _menuRow('icon_calendar', 'Templates', const [Color(0xFF10B981), Color(0xFF059669)]),
            const SizedBox(height: 8),
            _menuRow('icon_sparkle', 'AI Assistant', const [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
            const SizedBox(height: 8),
            _menuRow('?', 'How it works', const [Color(0xFF3B82F6), Color(0xFF2563EB)]),
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Center(child: Icon(Icons.menu, color: Colors.white, size: 22)),
            ),
          ]),
        );
    }
  }

  Widget _card(BuildContext context, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0)),
        ),
        child: child,
      );

  Widget _legend() {
    Widget chip(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        ]);
    return Wrap(spacing: 14, runSpacing: 6, alignment: WrapAlignment.center, children: [
      chip(_cDad, 'Dad'),
      chip(_cMom, 'Mom'),
      chip(_cBoth, 'Both'),
    ]);
  }

  /// A 7-cell week. [code] is 7 chars from {D,M,B,N}. [ring] outlines one day;
  /// [changed]/[conflict] outline days yellow/red.
  Widget _week(String code, {String? label, int? ring, Set<int> changed = const {}, Set<int> conflict = const {}}) {
    const dow = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    Color bg(String c) => c == 'D' ? _cDad : c == 'M' ? _cMom : c == 'B' ? _cBoth : _cNone;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (label != null) ...[
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: _muted)),
        const SizedBox(height: 6),
      ],
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < 7 && i < code.length; i++) ...[
          Column(children: [
            Text(dow[i], style: const TextStyle(fontSize: 9, color: _muted)),
            const SizedBox(height: 3),
            Container(
              width: 26,
              height: 30,
              decoration: BoxDecoration(
                color: bg(code[i]),
                borderRadius: BorderRadius.circular(7),
                border: ring == i
                    ? Border.all(color: const Color(0xFF2563EB), width: 2.5)
                    : conflict.contains(i)
                        ? Border.all(color: const Color(0xFFEF4444), width: 2.5)
                        : changed.contains(i)
                            ? Border.all(color: const Color(0xFFF59E0B), width: 2.5)
                            : null,
              ),
            ),
          ]),
          if (i < 6) const SizedBox(width: 4),
        ],
      ]),
    ]);
  }

  Widget _choice(String label, Color bg, Color ink) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ink)),
      );

  Widget _avatar(String label, Color color) => Column(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)),
          child: Center(
              child: Text(label.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
      ]);

  Widget _dot(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: color, width: 2.5)),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
      ]);

  Widget _menuRow(String icon, String label, List<Color> grad) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(9), boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 1)),
            ]),
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grad),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: icon.startsWith('icon_')
                  ? AppIcon(icon, size: 18, color: Colors.white)
                  : Text(icon, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
}
