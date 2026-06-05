import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../models/custody_models.dart';
import '../../models/location_models.dart';
import '../../navigation/app_navigator.dart';
import '../../services/analytics_service.dart';
import '../../services/custody_templates/custody_template.dart';
import '../../services/custody_templates/pending_template_service.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/skeleton.dart';
import '../ai/ai_chat_page.dart';
import 'templates/template_catalog_page.dart';
import 'custody_parent.dart';
import 'day_editor_view.dart';
import 'editor_models.dart';
import 'override_editor_view.dart';

/// Port of `Views/Schedule/CustodySchedule.xaml(.cs)` — the proposal-based custody
/// editor. Loads the active proposal + approved schedule, renders the repeating week
/// pattern (one card per week), and lets the user tap a day to edit (parent / handoff
/// time / location), long-press to mark a conflict (when reviewing a partner proposal),
/// and add holiday/one-off overrides. Save routes through create/counter/draft/new
/// proposal flows exactly as MAUI does; in onboarding mode it advances the router.
///
/// MAUI used a docked, retargeted sheet to dodge an iOS layout-loop hang; Flutter has
/// no such constraint, so each editor opens fresh in a modal bottom sheet (idiomatic
/// and equivalent in behavior).
class CustodySchedulePage extends StatefulWidget {
  const CustodySchedulePage({super.key});

  @override
  State<CustodySchedulePage> createState() => _CustodySchedulePageState();
}

class _CustodySchedulePageState extends State<CustodySchedulePage> {
  static const _dayNames = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];
  static const _weekOptions = [1, 2, 3, 4, 6, 8];
  static const _onboardingKey = 'custody_onboarding_complete';

  CustodyProposalDto? _activeProposal;
  ApprovedScheduleResponse? _approvedSchedule;
  bool _hasActiveProposal = false;
  bool _isEditingCounterProposal = false;
  bool _hasLocalChanges = false;

  final Map<(int, int), ProposalDayDto> _localDayEdits = {};
  final Map<String, ProposalOverrideDto> _localOverrideEdits = {};

  int _patternLength = 1;
  bool _isOnboarding = false;
  List<PointOfInterest> _allPois = const [];
  String _currentUserEmail = '';

  bool _loading = true;
  bool _busy = false;
  String _busyLabel = 'Loading...';

  // Docked (non-modal) day/override editor: lives at the bottom of the page's Stack
  // so the calendar stays interactive above it (no modal barrier). The selected day
  // cell gets a blue highlight and the calendar auto-scrolls to keep it in view.
  final ScrollController _scrollCtrl = ScrollController();
  Widget? _dockedEditor;
  int? _selWeek;
  int? _selDay;
  final Map<int, GlobalKey> _weekKeys = {};

  @override
  void initState() {
    super.initState();
    _isOnboarding = PendingTemplateService.isOnboardingMode;
    _init();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Closes the docked editor and clears the cell highlight.
  void _closeSheet() {
    if (!mounted) return;
    setState(() {
      _dockedEditor = null;
      _selWeek = null;
      _selDay = null;
    });
  }

  /// Scrolls the selected week's card to the centre of the area still visible
  /// above the docked editor (mirrors MAUI's ScrollSelectedCellIntoView). The
  /// docked panel covers the lower ~55% of the screen, so centring within the
  /// full viewport (0.5) would hide the card behind it — 0.22 lands it in the
  /// middle of the visible upper band.
  void _scrollToWeek(int w) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _weekKeys[w]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: _dockedEditor != null ? 0.22 : 0.5,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _init() async {
    try {
      _currentUserEmail = await ServiceLocator.secureStorage.getSecureEmail();
      try {
        _allPois = await ServiceLocator.location.getPois();
      } catch (_) {/* continue without POIs */}
      await _loadProposalData();
      await _handlePendingHandoff();
    } catch (e) {
      if (mounted) await _alert('Error', 'Failed to load schedule: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
      if (mounted && !Preferences.getBool(_onboardingKey)) _showOnboarding();
    }
  }

  Future<void> _loadProposalData() async {
    final active = await ServiceLocator.custodyProposal.getActiveProposal();
    _hasActiveProposal = active?.hasActiveProposal ?? false;
    _activeProposal = active?.proposal;
    _approvedSchedule = await ServiceLocator.custodyProposal.getApprovedSchedule();

    _localDayEdits.clear();
    _localOverrideEdits.clear();
    _hasLocalChanges = false;
    _isEditingCounterProposal = false;

    if (_activeProposal != null) {
      _patternLength = _activeProposal!.patternLength;
    } else if ((_approvedSchedule?.patternLength ?? 0) > 0) {
      _patternLength = _approvedSchedule!.patternLength;
    } else {
      _patternLength = 1;
    }
    if (mounted) setState(() {});
  }

  // ── Pending template / raw-pattern handoff ──────────────────────────────────
  Future<void> _handlePendingHandoff() async {
    final raw = PendingTemplateService.tryConsumeRawPattern();
    if (raw != null) {
      _applyRawPattern(raw.length, raw.days);
      return;
    }
    final tpl = PendingTemplateService.tryConsume();
    if (tpl != null) {
      _applyTemplate(tpl.template, tpl.answers);
    }
  }

  // ── Day data resolution (local edits → proposal → approved → default) ────────
  ProposalDayDto _getDayData(int w, int d) {
    final local = _localDayEdits[(w, d)];
    if (local != null) return local;

    if (_activeProposal != null) {
      for (final pd in _activeProposal!.days) {
        if (pd.weekIndex == w && pd.dayIndex == d) return pd;
      }
    }
    if (_approvedSchedule != null) {
      for (final ad in _approvedSchedule!.days) {
        if (ad.weekIndex == w && ad.dayIndex == d) {
          return ProposalDayDto(
            weekIndex: w,
            dayIndex: d,
            parentAssignment: ad.parentAssignment,
            transferTime: ad.transferTime,
            transferEndTime: ad.transferEndTime,
            dayStatus: 'normal',
            transferLatitude: ad.transferLatitude,
            transferLongitude: ad.transferLongitude,
            transferLocationName: ad.transferLocationName,
            transferAddress: ad.transferAddress,
          );
        }
      }
    }
    return ProposalDayDto(weekIndex: w, dayIndex: d, parentAssignment: 'None', dayStatus: 'normal');
  }

  /// Pre-proposal baseline for change detection (approved first, else the proposal's
  /// stored previousAssignment). Mirrors MAUI's `GetBaselineDay`.
  ({String parent, String? time, String? endTime, double? lat, double? lng, String? locName, String? locAddr})
      _getBaselineDay(int w, int d) {
    if (_approvedSchedule != null) {
      for (final a in _approvedSchedule!.days) {
        if (a.weekIndex == w && a.dayIndex == d) {
          return (
            parent: a.parentAssignment,
            time: a.transferTime,
            endTime: a.transferEndTime,
            lat: a.transferLatitude,
            lng: a.transferLongitude,
            locName: a.transferLocationName,
            locAddr: a.transferAddress,
          );
        }
      }
    }
    if (_activeProposal != null) {
      for (final p in _activeProposal!.days) {
        if (p.weekIndex == w &&
            p.dayIndex == d &&
            p.isChangedFromPrevious &&
            (p.previousAssignment?.isNotEmpty ?? false)) {
          return (parent: p.previousAssignment!, time: null, endTime: null, lat: null, lng: null, locName: null, locAddr: null);
        }
      }
    }
    return (parent: 'None', time: null, endTime: null, lat: null, lng: null, locName: null, locAddr: null);
  }

  /// Diff baseline passed to the day editor = approved-schedule value (or null when
  /// there's no approved equivalent, so no "was X" rows show). Mirrors `GetApprovedDayBaseline`.
  DayBaseline? _getApprovedDayBaseline(int w, int d) {
    ApprovedDayDto? a;
    for (final x in _approvedSchedule?.days ?? const <ApprovedDayDto>[]) {
      if (x.weekIndex == w && x.dayIndex == d) {
        a = x;
        break;
      }
    }
    if (a == null) return null;
    return DayBaseline(
      parent: a.parentAssignment.isEmpty ? 'None' : a.parentAssignment,
      time: _parseTod(a.transferTime),
      endTime: _parseTod(a.transferEndTime),
      locName: a.transferLocationName,
      locAddr: a.transferAddress,
    );
  }

  // ── Apply a single day edit into the local draft ─────────────────────────────
  void _applyDayEdit(DayEditCommit c) {
    final b = _getBaselineDay(c.weekIndex, c.dayIndex);
    final newTime = _fmtTod(c.transferTime);
    final newEnd = _fmtTod(c.transferEndTime);
    final loc = c.location;
    final isChange = b.parent != c.parent ||
        (b.time ?? '') != (newTime ?? '') ||
        (b.endTime ?? '') != (newEnd ?? '') ||
        b.lat != loc?.latitude ||
        b.lng != loc?.longitude ||
        (b.locName ?? '') != (loc?.name ?? '') ||
        (b.locAddr ?? '') != (loc?.address ?? '');

    if (_hasActiveProposal && !(_activeProposal?.isCurrentUserProposer ?? false) && isChange) {
      if (!_isEditingCounterProposal) {
        _isEditingCounterProposal = true;
        _hasLocalChanges = true;
      }
    }

    final current = _getDayData(c.weekIndex, c.dayIndex);
    _localDayEdits[(c.weekIndex, c.dayIndex)] = ProposalDayDto(
      weekIndex: c.weekIndex,
      dayIndex: c.dayIndex,
      parentAssignment: c.parent,
      transferTime: newTime,
      transferEndTime: newEnd,
      dayStatus: current.hasConflict ? 'conflict' : (isChange ? 'changed' : 'normal'),
      isChangedFromPrevious: isChange,
      previousAssignment: isChange ? b.parent : null,
      hasConflict: current.hasConflict,
      conflictReason: current.conflictReason,
      conflictMarkedBy: current.conflictMarkedBy,
      transferLatitude: loc?.latitude,
      transferLongitude: loc?.longitude,
      transferLocationName: loc?.name,
      transferAddress: loc?.address,
    );
    _hasLocalChanges = true;
    if (mounted) setState(() {});
  }

  // ── Conflict marking (partner-proposal mode) ─────────────────────────────────
  Future<void> _toggleConflict(int w, int d) async {
    final current = _getDayData(w, d);
    if (current.hasConflict) {
      final clear = await _confirm('Clear Conflict',
          'This day is marked as a conflict. Do you want to clear the conflict?', 'Clear');
      if (clear != true) return;
      _localDayEdits[(w, d)] = ProposalDayDto(
        weekIndex: w,
        dayIndex: d,
        parentAssignment: current.parentAssignment,
        transferTime: current.transferTime,
        dayStatus: 'normal',
        hasConflict: false,
        isChangedFromPrevious: current.isChangedFromPrevious,
        previousAssignment: current.previousAssignment,
        transferLatitude: current.transferLatitude,
        transferLongitude: current.transferLongitude,
        transferLocationName: current.transferLocationName,
        transferAddress: current.transferAddress,
      );
    } else {
      final reason = await _prompt('Mark Conflict', 'Why is this day a conflict?',
          'e.g., Work commitment, prior plans...');
      if (reason == null) return;
      _localDayEdits[(w, d)] = ProposalDayDto(
        weekIndex: w,
        dayIndex: d,
        parentAssignment: current.parentAssignment,
        transferTime: current.transferTime,
        dayStatus: 'conflict',
        hasConflict: true,
        conflictReason: reason,
        conflictMarkedBy: _currentUserEmail,
        isChangedFromPrevious: current.isChangedFromPrevious,
        previousAssignment: current.previousAssignment,
        transferLatitude: current.transferLatitude,
        transferLongitude: current.transferLongitude,
        transferLocationName: current.transferLocationName,
        transferAddress: current.transferAddress,
      );
    }
    _hasLocalChanges = true;
    _isEditingCounterProposal = true;
    if (mounted) setState(() {});
  }

  // ── Override (special day) aggregation ───────────────────────────────────────
  List<ProposalOverrideDto> _displayOverrides() {
    final all = <String, ProposalOverrideDto>{};

    for (final ovr in _approvedSchedule?.overrides ?? const <ApprovedOverrideDto>[]) {
      all[ovr.dateKey] = ProposalOverrideDto(
        dateKey: ovr.dateKey,
        month: ovr.month,
        day: ovr.day,
        parentAssignment: ovr.parentAssignment,
        transferTime: ovr.transferTime,
        description: ovr.description,
        isAnnual: ovr.isAnnual,
        alternationMode: ovr.alternationMode,
        alternationStartParent: ovr.alternationStartParent,
        overrideStatus: 'normal',
        transferLatitude: ovr.transferLatitude,
        transferLongitude: ovr.transferLongitude,
        transferLocationName: ovr.transferLocationName,
        transferAddress: ovr.transferAddress,
      );
    }
    for (final ovr in _activeProposal?.overrides ?? const <ProposalOverrideDto>[]) {
      all[ovr.dateKey] = ovr;
    }

    final originalKeysToRemove = <String>{};
    for (final entry in _localOverrideEdits.entries) {
      final v = entry.value;
      if ((v.originalDateKey?.isNotEmpty ?? false) && v.originalDateKey != entry.key) {
        originalKeysToRemove.add(v.originalDateKey!);
      }
      all[entry.key] = v;
    }
    for (final k in originalKeysToRemove) {
      all.remove(k);
    }

    final display = all.entries.where((e) {
      if (!e.value.isMarkedForDeletion) return true;
      final keyToCheck = e.value.originalDateKey ?? e.key;
      return _isOverrideFromApprovedSchedule(keyToCheck);
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return [for (final e in display) e.value];
  }

  bool _isOverrideFromApprovedSchedule(String dateKey) =>
      _approvedSchedule?.overrides.any((o) => o.dateKey == dateKey) ?? false;

  bool _isExistingOverride(String dateKey) {
    if (_approvedSchedule?.overrides.any((o) => o.dateKey == dateKey) ?? false) return true;
    if (_activeProposal?.overrides.any((o) => o.dateKey == dateKey) ?? false) return true;
    return false;
  }

  ProposalOverrideDto _getExistingOverrideData(String dateKey) {
    final local = _localOverrideEdits[dateKey];
    if (local != null) return local;
    for (final o in _activeProposal?.overrides ?? const <ProposalOverrideDto>[]) {
      if (o.dateKey == dateKey) return o;
    }
    for (final o in _approvedSchedule?.overrides ?? const <ApprovedOverrideDto>[]) {
      if (o.dateKey == dateKey) {
        return ProposalOverrideDto(
          dateKey: o.dateKey,
          month: o.month,
          day: o.day,
          parentAssignment: o.parentAssignment,
          transferTime: o.transferTime,
          description: o.description,
          isAnnual: o.isAnnual,
          alternationMode: o.alternationMode,
          alternationStartParent: o.alternationStartParent,
          overrideStatus: 'normal',
          transferLatitude: o.transferLatitude,
          transferLongitude: o.transferLongitude,
          transferLocationName: o.transferLocationName,
          transferAddress: o.transferAddress,
        );
      }
    }
    final parts = dateKey.split('-');
    return ProposalOverrideDto(
      dateKey: dateKey,
      month: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 1,
      day: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1,
      parentAssignment: 'None',
      overrideStatus: 'normal',
    );
  }

  Future<void> _handleOverrideResult(OverrideDayEditResult r) async {
    final lookupKey = r.originalDateKey ?? r.dateKey;
    final isExisting = _isExistingOverride(lookupKey);
    final isNewOverride = !isExisting && !_localOverrideEdits.containsKey(lookupKey);
    final dateWasChanged = r.dateWasChanged;

    String? trueOriginalDateKey = r.originalDateKey;
    if (r.originalDateKey != null && _localOverrideEdits.containsKey(r.originalDateKey)) {
      final existingLocal = _localOverrideEdits[r.originalDateKey]!;
      trueOriginalDateKey = existingLocal.originalDateKey ?? r.originalDateKey;
    }

    bool hasActualChanges = true;
    if (isExisting) {
      final original = _getExistingOverrideData(lookupKey);
      hasActualChanges = original.parentAssignment != r.parent ||
          original.transferTime != _fmtTod(r.transferTime) ||
          original.description != r.description ||
          original.isAnnual != r.isAnnual ||
          (original.alternationMode) != r.alternationMode ||
          original.alternationStartParent != r.alternationStartParent ||
          original.transferLatitude != r.transferLocation?.latitude ||
          original.transferLongitude != r.transferLocation?.longitude ||
          dateWasChanged;
    }

    final newOverride = ProposalOverrideDto(
      dateKey: r.dateKey,
      originalDateKey: trueOriginalDateKey,
      month: r.selectedDate.month,
      day: r.selectedDate.day,
      parentAssignment: r.parent,
      transferTime: _fmtTod(r.transferTime),
      transferEndTime: _fmtTod(r.transferEndTime),
      description: r.description,
      isAnnual: r.isAnnual,
      holidayRule: r.holidayRule,
      alternationMode: r.alternationMode,
      alternationStartParent: r.alternationStartParent,
      overrideStatus: 'normal',
      isNewInThisVersion: isNewOverride,
      isChangedFromPrevious: isExisting && hasActualChanges,
      isMarkedForDeletion: false,
      transferLatitude: r.transferLocation?.latitude,
      transferLongitude: r.transferLocation?.longitude,
      transferLocationName: r.transferLocation?.name,
      transferAddress: r.transferLocation?.address,
    );

    if (dateWasChanged && r.originalDateKey != null) {
      _localOverrideEdits.remove(r.originalDateKey);
    }
    _localOverrideEdits[r.dateKey] = newOverride;
    _hasLocalChanges = true;
    if (_hasActiveProposal && !(_activeProposal?.isCurrentUserProposer ?? false)) {
      _isEditingCounterProposal = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _deleteOverride(String dateKey) async {
    final isApproved = _isOverrideFromApprovedSchedule(dateKey);
    final message = isApproved
        ? 'This will propose deleting this override day. Your partner will need to accept the change.'
        : 'Are you sure you want to delete this override day?';
    final confirm = await _confirm('Delete Override Day', message, isApproved ? 'Propose Deletion' : 'Delete');
    if (confirm != true) return;

    if (isApproved) {
      final ex = _getExistingOverrideData(dateKey);
      _localOverrideEdits[dateKey] = ProposalOverrideDto(
        dateKey: ex.dateKey,
        month: ex.month,
        day: ex.day,
        parentAssignment: ex.parentAssignment,
        transferTime: ex.transferTime,
        description: ex.description,
        isAnnual: ex.isAnnual,
        overrideStatus: 'deleted',
        isMarkedForDeletion: true,
        isChangedFromPrevious: true,
        transferLatitude: ex.transferLatitude,
        transferLongitude: ex.transferLongitude,
        transferLocationName: ex.transferLocationName,
        transferAddress: ex.transferAddress,
      );
    } else {
      _localOverrideEdits.remove(dateKey);
    }
    _hasLocalChanges = true;
    if (_hasActiveProposal && !(_activeProposal?.isCurrentUserProposer ?? false)) {
      _isEditingCounterProposal = true;
    }
    if (mounted) setState(() {});
  }

  void _undoDeleteOverride(String dateKey) {
    _localOverrideEdits.remove(dateKey);
    _hasLocalChanges = _localOverrideEdits.isNotEmpty || _localDayEdits.isNotEmpty;
    if (mounted) setState(() {});
  }

  // ── Template / raw pattern application ───────────────────────────────────────
  void _applyTemplate(CustodyTemplate template, TemplateAnswers answers) {
    try {
      final generated = template.buildPattern(answers);
      _patternLength = template.patternLengthWeeks;
      _localDayEdits.clear();
      _localOverrideEdits.clear();
      for (final day in generated) {
        _localDayEdits[(day.weekIndex, day.dayIndex)] = ProposalDayDto(
          weekIndex: day.weekIndex,
          dayIndex: day.dayIndex,
          parentAssignment: day.parentAssignment,
          transferTime: day.transferTime,
          transferEndTime: day.transferEndTime,
          dayStatus: 'normal',
          isChangedFromPrevious: true,
        );
      }
      _hasLocalChanges = true;
      if (mounted) setState(() {});
      if (!_isOnboarding) {
        _alert(template.name,
            'Template applied! Review the schedule below and tap Save when you\'re happy with it. You can tap any day to adjust.');
      }
    } catch (e) {
      _alert("Couldn't apply template", 'Something went wrong applying this template: $e');
    }
  }

  void _applyRawPattern(int patternLengthWeeks, List<RawPatternDay> days) {
    try {
      _patternLength = patternLengthWeeks;
      _localDayEdits.clear();
      _localOverrideEdits.clear();
      for (final d in days) {
        _localDayEdits[(d.weekIndex, d.dayIndex)] = ProposalDayDto(
          weekIndex: d.weekIndex,
          dayIndex: d.dayIndex,
          parentAssignment: d.parentAssignment,
          transferTime: d.transferTime,
          transferEndTime: d.transferEndTime,
          transferLocationName: d.locationName,
          transferAddress: d.locationAddress,
          transferLatitude: d.latitude,
          transferLongitude: d.longitude,
          dayStatus: 'normal',
          isChangedFromPrevious: true,
        );
      }
      _hasLocalChanges = true;
      if (mounted) setState(() {});
      if (!_isOnboarding) {
        _alert('AI pattern loaded',
            'Review the schedule below and tweak any day if you\'d like, then tap Save Schedule to send it to your co-parent.');
      }
    } catch (e) {
      _alert("Couldn't load pattern", 'Something went wrong: $e');
    }
  }

  // ── Save routing (port of OnSaveScheduleClicked) ─────────────────────────────
  UpdateDayRequest _dayReq(ProposalDayDto d, {bool full = true}) => UpdateDayRequest(
        weekIndex: d.weekIndex,
        dayIndex: d.dayIndex,
        parentAssignment: d.parentAssignment,
        transferTime: d.transferTime,
        transferEndTime: d.transferEndTime,
        locationName: d.transferLocationName,
        locationAddress: d.transferAddress,
        latitude: d.transferLatitude,
        longitude: d.transferLongitude,
        dayStatus: full ? d.dayStatus : null,
        hasConflict: full ? d.hasConflict : false,
        conflictReason: full ? d.conflictReason : null,
        conflictMarkedBy: full ? d.conflictMarkedBy : null,
      );

  UpdateOverrideRequest _overrideReq(ProposalOverrideDto o) => UpdateOverrideRequest(
        dateKey: o.dateKey,
        originalDateKey: o.originalDateKey,
        month: o.month,
        day: o.day,
        parentAssignment: o.parentAssignment,
        transferTime: o.transferTime,
        transferEndTime: o.transferEndTime,
        description: o.description,
        isAnnual: o.isAnnual,
        holidayRule: o.holidayRule,
        alternationMode: o.alternationMode,
        alternationStartParent: o.alternationStartParent,
        locationName: o.transferLocationName,
        locationAddress: o.transferAddress,
        latitude: o.transferLatitude,
        longitude: o.transferLongitude,
        isMarkedForDeletion: o.isMarkedForDeletion,
      );

  Future<void> _onSave() async {
    final hasAnyChanges = _localDayEdits.isNotEmpty || _localOverrideEdits.isNotEmpty;
    final proposer = _activeProposal?.isCurrentUserProposer == true;
    final status = _activeProposal?.status;

    if (!_hasActiveProposal && !hasAnyChanges) {
      await _alert('No Changes', 'Please make changes to the schedule before submitting a proposal.');
      return;
    }
    if (_isEditingCounterProposal && !hasAnyChanges) {
      await _alert('No Changes',
          'Please make changes or mark conflicts before submitting a counter-proposal.\n\n• Tap a day to change the assignment\n• Long-press to mark as conflict');
      return;
    }
    if (_hasActiveProposal && proposer && status == 'submitted' && !hasAnyChanges) {
      await _alert('No Changes', 'Please make changes to the schedule before submitting a new proposal.');
      return;
    }

    final svc = ServiceLocator.custodyProposal;
    setState(() {
      _busy = true;
      _busyLabel = _isEditingCounterProposal ? 'Submitting counter-proposal...' : 'Saving...';
    });
    try {
      final reviewingPartnerProposal =
          _hasActiveProposal && _activeProposal != null && !_activeProposal!.isCurrentUserProposer;

      if (reviewingPartnerProposal && !_isEditingCounterProposal && !hasAnyChanges && _activeProposal != null) {
        // Saving the partner's proposal with no modifications is an AGREEMENT, not a
        // counter. Previously this fell through and submitted an identical
        // counter-proposal — confusing, especially during onboarding.
        final result = await svc.approveProposal(_activeProposal!.proposalId);
        if (result?.success == true) {
          AnalyticsService.trackCustom('schedule_accepted_unchanged');
          await _alert('Success', 'Schedule accepted!');
          await _exitAfterSave();
        } else {
          await _alert('Error', 'Failed to accept the schedule. Please try again.');
        }
      } else if ((_isEditingCounterProposal || reviewingPartnerProposal) && _activeProposal != null) {
        // Counter-proposal off the partner's proposal.
        final counter = await svc.createCounterProposal(_activeProposal!.proposalId);
        if (counter == null) {
          await _alert('Error', 'Failed to create counter-proposal');
          return;
        }
        final dayUpdates = [for (final d in _localDayEdits.values) _dayReq(d)];
        if (dayUpdates.isNotEmpty) {
          if (!await svc.updateDays(counter.proposalId, dayUpdates)) {
            await _alert('Error', 'Failed to save day changes');
            return;
          }
        }
        for (final ovr in _localOverrideEdits.values) {
          await svc.addOrUpdateOverride(counter.proposalId, _overrideReq(ovr));
        }
        final result = await svc.submitProposal(counter.proposalId);
        if (result?.success == true) {
          AnalyticsService.trackFirstScheduleCreated();
          await _alert('Success', 'Counter-proposal submitted successfully!');
          await _exitAfterSave();
        } else {
          await _alert('Error', 'Failed to submit counter-proposal');
        }
      } else if (_hasActiveProposal && proposer && status == 'draft') {
        // Update existing DRAFT, then submit.
        final dayUpdates = [for (final d in _localDayEdits.values) _dayReq(d)];
        if (dayUpdates.isNotEmpty) {
          if (!await svc.updateDays(_activeProposal!.proposalId, dayUpdates)) {
            await _alert('Error', 'Failed to save day changes');
            return;
          }
        }
        final result = await svc.submitProposal(_activeProposal!.proposalId);
        if (result?.success == true) {
          AnalyticsService.trackFirstScheduleCreated();
          await _alert('Success', 'Proposal submitted successfully!');
          await _exitAfterSave();
        } else {
          await _handleSubmitFailure();
        }
      } else if (_hasActiveProposal && proposer && status == 'submitted') {
        // Submitted proposal + more changes → create a NEW proposal carrying forward
        // the prior changed days/overrides plus local edits.
        final newProposal = await svc.createNewProposal(_patternLength);
        if (newProposal == null) {
          await _alert('Error', 'Failed to create new proposal');
          return;
        }
        final allDayUpdates = <UpdateDayRequest>[];
        for (final day in _activeProposal!.days.where((d) => d.isChangedFromPrevious)) {
          if (!_localDayEdits.containsKey((day.weekIndex, day.dayIndex))) {
            allDayUpdates.add(_dayReq(day, full: false));
          }
        }
        for (final d in _localDayEdits.values) {
          allDayUpdates.add(_dayReq(d));
        }
        if (allDayUpdates.isNotEmpty) {
          if (!await svc.updateDays(newProposal.proposalId, allDayUpdates)) {
            await _alert('Error', 'Failed to save day changes');
            return;
          }
        }
        final processed = <String>{};
        for (final ovr in _localOverrideEdits.values) {
          processed.add(ovr.dateKey);
          await svc.addOrUpdateOverride(newProposal.proposalId, _overrideReq(ovr));
        }
        for (final ovr in _activeProposal!.overrides
            .where((o) => o.isChangedFromPrevious || o.isNewInThisVersion || o.isMarkedForDeletion)) {
          if (!processed.contains(ovr.dateKey)) {
            await svc.addOrUpdateOverride(newProposal.proposalId, _overrideReq(ovr));
          }
        }
        final result = await svc.submitProposal(newProposal.proposalId);
        if (result?.success == true) {
          AnalyticsService.trackFirstScheduleCreated();
          await _alert('Success', 'New proposal submitted successfully!');
          await _exitAfterSave();
        } else {
          await _handleSubmitFailure();
        }
      } else {
        // No active proposal — create a new one with the local edits.
        final newProposal = await svc.createNewProposal(_patternLength);
        if (newProposal == null) {
          await _alert('Error', 'Failed to create proposal');
          return;
        }
        final dayUpdates = [for (final d in _localDayEdits.values) _dayReq(d)];
        if (dayUpdates.isNotEmpty) {
          if (!await svc.updateDays(newProposal.proposalId, dayUpdates)) {
            await _alert('Error', 'Failed to save day changes');
            return;
          }
        }
        for (final ovr in _localOverrideEdits.values) {
          await svc.addOrUpdateOverride(newProposal.proposalId, _overrideReq(ovr));
        }
        final result = await svc.submitProposal(newProposal.proposalId);
        if (result?.success == true) {
          AnalyticsService.trackFirstScheduleCreated();
          await _alert('Success', 'Proposal submitted successfully!');
          await _exitAfterSave();
        } else {
          await _handleSubmitFailure();
        }
      }
    } catch (e) {
      await _alert('Error', 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A submit failed. The most likely cause now is "first-submit-wins": the
  /// co-parent submitted their schedule first (both set up at once), so the server
  /// declined this competing one. Rather than an error, route into the EXISTING
  /// review flow — in onboarding that's the same path the router takes when the
  /// partner has a proposal (scheduleReview); elsewhere we reload into review mode.
  Future<void> _handleSubmitFailure() async {
    try {
      final active = await ServiceLocator.custodyProposal.getActiveProposal();
      final p = active?.proposal;
      if (active?.hasActiveProposal == true && p != null && !p.isCurrentUserProposer) {
        if (PendingTemplateService.isOnboardingMode) {
          if (mounted) await advanceOnboarding(context); // → scheduleReview
        } else if (mounted) {
          await _loadProposalData(); // reload into "Partner's Proposal" review mode
        }
        return;
      }
    } catch (_) {/* fall through to the generic error */}
    await _alert('Error', 'Failed to submit proposal');
  }

  Future<void> _exitAfterSave() async {
    if (PendingTemplateService.isOnboardingMode) {
      PendingTemplateService.clear();
      AnalyticsService.trackCustom('onboarding_manual_build_saved');
      if (mounted) await advanceOnboarding(context);
    } else {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  // ── Accept / Reject / Withdraw / Counter ─────────────────────────────────────
  Future<void> _accept() async {
    if (_activeProposal == null) return;
    if (await _confirm('Accept Proposal', 'Are you sure you want to accept all proposed changes?', 'Accept') != true) {
      return;
    }
    await _proposalAction(() => ServiceLocator.custodyProposal.approveProposal(_activeProposal!.proposalId),
        'Accepting proposal...', 'Proposal accepted and applied to schedule!', 'Failed to accept proposal');
  }

  Future<void> _reject() async {
    if (_activeProposal == null) return;
    if (await _confirm('Reject Proposal', 'Are you sure you want to reject all proposed changes?', 'Reject') != true) {
      return;
    }
    await _proposalAction(() => ServiceLocator.custodyProposal.rejectProposal(_activeProposal!.proposalId),
        'Rejecting proposal...', 'Proposal rejected!', 'Failed to reject proposal');
  }

  Future<void> _withdraw() async {
    if (_activeProposal == null) return;
    if (await _confirm('Withdraw Proposal', 'Are you sure you want to withdraw your proposal?', 'Withdraw') != true) {
      return;
    }
    await _proposalAction(() => ServiceLocator.custodyProposal.withdrawProposal(_activeProposal!.proposalId),
        'Withdrawing proposal...', 'Proposal withdrawn!', 'Failed to withdraw proposal');
  }

  Future<void> _proposalAction(
      Future<SuccessResponse?> Function() action, String busy, String okMsg, String failMsg) async {
    setState(() {
      _busy = true;
      _busyLabel = busy;
    });
    try {
      final result = await action();
      if (result?.success == true) {
        await _alert('Success', okMsg);
        if (mounted) Navigator.of(context).maybePop();
      } else {
        await _alert('Error', failMsg);
      }
    } catch (e) {
      await _alert('Error', '$failMsg: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startCounter() async {
    setState(() {
      _isEditingCounterProposal = true;
      _hasLocalChanges = true;
    });
    await _alert('Counter-Proposal Mode',
        "You're now in counter-proposal mode.\n\n• Tap any day to change the assignment\n• Long-press to mark as conflict\n• When ready, tap 'Submit Proposal'\n\nYour partner will see your modifications highlighted.");
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────
  static TimeOfDay? _parseTod(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String? _fmtTod(TimeOfDay? t) =>
      t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static CustodyParent _parentEnum(String p) => switch (p) {
        'Husband' => CustodyParent.dad,
        'Wife' => CustodyParent.mom,
        'Both' => CustodyParent.both,
        _ => CustodyParent.none,
      };

  static String _displayParent(String p) => switch (p) {
        'Husband' => 'Dad',
        'Wife' => 'Mom',
        'Both' => 'Both',
        _ => 'None',
      };

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

  Future<String?> _prompt(String title, String message, String placeholder) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(controller: ctrl, decoration: InputDecoration(hintText: placeholder)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _openAi() async {
    final ctx = PendingTemplateService.isOnboardingMode ? 'onboarding-schedule' : 'schedule';
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiChatPage(chatContext: ctx)));
    if (!mounted) return;
    await _handlePendingHandoff();
  }

  /// Opens the template catalog from the editor (outside onboarding) and applies
  /// the chosen template to the current schedule on return.
  Future<void> _openTemplates() async {
    PendingTemplateService.isOnboardingMode = false;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplateCatalogPage()));
    if (!mounted) return;
    await _handlePendingHandoff();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasApprovedOnly = (_approvedSchedule?.hasSchedule ?? false) &&
        !_hasActiveProposal &&
        !_isEditingCounterProposal &&
        !_hasLocalChanges;
    final showBanner = !_isOnboarding &&
        (_hasActiveProposal || _isEditingCounterProposal || _hasLocalChanges) &&
        !hasApprovedOnly;
    final showNotification = !_isOnboarding && _hasActiveProposal && _activeProposal != null;
    final patternEditable = !_hasActiveProposal || (_activeProposal?.isCurrentUserProposer == true);

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Column(
            children: [
              _header(context),
              Expanded(
                child: LoadingSwitcher(
                  loading: _loading,
                  skeleton: const SkeletonCalendar(),
                  child: SingleChildScrollView(
                        controller: _scrollCtrl,
                        padding: EdgeInsets.fromLTRB(20, 20, 20,
                            _dockedEditor != null ? MediaQuery.of(context).size.height * 0.55 + 40 : 100),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showBanner) ...[
                                  _proposalStatusBanner(context),
                                  const SizedBox(height: 20),
                                ],
                                // Always shown (mirrors MAUI's PatternConfigSection,
                                // which is disabled — not hidden — when reviewing a
                                // co-parent's proposal).
                                _patternConfig(context, patternEditable),
                                const SizedBox(height: 16),
                                _legendStrip(context),
                                const SizedBox(height: 16),
                                for (int w = 0; w < _patternLength; w++) ...[
                                  KeyedSubtree(
                                    key: _weekKeys.putIfAbsent(w, () => GlobalKey()),
                                    child: _weekCard(context, w),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                _specialDays(context),
                                if (showNotification) ...[
                                  const SizedBox(height: 20),
                                  _proposalNotification(context),
                                ],
                                const SizedBox(height: 20),
                                _actionButtons(context),
                              ],
                            ),
                          ),
                        ),
                      ),
                ),
              ),
            ],
          ),
          if (!_isOnboarding && _dockedEditor == null)
            Positioned(
              right: 20,
              bottom: 24,
              child: _EditorActionMenu(
                onAi: _openAi,
                onTemplates: _openTemplates,
                onHelp: _showOnboarding,
              ),
            ),
          if (_dockedEditor != null)
            Positioned(left: 0, right: 0, bottom: 0, child: _dockedPanel(context)),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(_busyLabel, style: const TextStyle(color: Colors.white)),
                    ],
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
    final (title, subtitle) = _headerText();
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.viewPaddingOf(context).top + 12, 20, 16),
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
          _smallSquare(
            context,
            bg: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
            child: AppIcon('icon_chevron_left', size: 22, color: palette.textSecondary),
            onTap: _onBack,
          ),
          Expanded(
            child: Column(
              children: [
                Text(title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 4),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    // Cap the wrapping — some subtitles are long and looked bad
                    // spilling onto 3+ lines on small screens.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          ),
          // Help lives in the hamburger menu now ("How it works") — keep a spacer
          // the width of the back button so the title stays centered.
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  (String, String) _headerText() {
    // Reviewing the co-parent's proposal during onboarding (they set up the schedule
    // first / you're both setting up together) — frame it as a shared review.
    if (_isOnboarding &&
        _hasActiveProposal &&
        _activeProposal != null &&
        !_activeProposal!.isCurrentUserProposer) {
      return ("Your co-parent's schedule", 'They set it up — review together, then continue');
    }
    if (_isOnboarding) return ('Your Schedule', 'Tap any day to change it · then continue');
    if (_hasActiveProposal && _activeProposal != null) {
      if (_activeProposal!.isCurrentUserProposer) {
        return (
          'Your Proposal',
          _activeProposal!.status == 'draft' ? 'Draft - Not yet submitted' : 'Awaiting partner response - Tap to modify'
        );
      }
      return ("Partner's Proposal", 'Review and respond to changes');
    }
    if (_isEditingCounterProposal) {
      return ('Counter-Proposal', 'Modify days to create your counter-proposal');
    }
    final hasApprovedOnly = (_approvedSchedule?.hasSchedule ?? false) && !_hasLocalChanges;
    if (hasApprovedOnly) {
      return ('Custody Schedule', 'Current approved schedule - Tap days to propose changes');
    }
    return ('Custody Schedule', 'Configure your custody pattern');
  }

  Future<void> _onBack() async {
    if (_hasLocalChanges) {
      final confirm = await _confirm(
          'Discard Changes?', 'You have unsaved changes. Are you sure you want to discard them?', 'Discard');
      if (confirm != true) return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Widget _smallSquare(BuildContext context,
      {required Color bg, required Widget child, required VoidCallback onTap, double radius = 12}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
        child: Center(child: child),
      ),
    );
  }

  // ── Proposal status banner ────────────────────────────────────────────────────
  Widget _proposalStatusBanner(BuildContext context) {
    final (statusTitle, statusSubtitle) = _bannerText();
    final version = _activeProposal != null ? 'v${_activeProposal!.version}' : '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEFF6FF),
        border: Border.all(color: AppColors.primaryBlue),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(10)),
            child: const Center(child: AppIcon('icon_edit', size: 20, color: AppColors.primaryBlue)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusTitle,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: context.isDark ? const Color(0xFF93C5FD) : AppColors.primaryBlue)),
                const SizedBox(height: 2),
                Text(statusSubtitle,
                    style: TextStyle(
                        fontSize: 12, color: context.isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1E40AF))),
              ],
            ),
          ),
          if (version.isNotEmpty)
            Text(version,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
        ],
      ),
    );
  }

  (String, String) _bannerText() {
    if (_activeProposal != null) {
      if (_activeProposal!.isCurrentUserProposer) {
        return _activeProposal!.status == 'draft'
            ? ('Draft Proposal', 'Tap days to modify before submitting')
            : ('Your Proposal Submitted', 'You can still modify and submit updated changes');
      }
      return ('Reviewing Proposal', 'Tap days to modify (creates counter-proposal), long-press for conflict');
    }
    if (_isEditingCounterProposal) {
      return ('Creating Counter-Proposal', 'Modify days, then submit your counter-proposal');
    }
    return ('Unsaved Changes', 'You have pending changes to submit');
  }

  // ── Pattern length ──────────────────────────────────────────────────────────
  Widget _patternConfig(BuildContext context, bool enabled) {
    final palette = context.palette;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text('Schedule repeats every',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _weekOptions.contains(_patternLength) ? _patternLength : 1,
                dropdownColor: palette.surfaceElevated,
                style: TextStyle(fontSize: 14, color: palette.textPrimary),
                items: [
                  for (final w in _weekOptions)
                    DropdownMenuItem(value: w, child: Text('$w ${w == 1 ? 'Week' : 'Weeks'}')),
                ],
                onChanged: enabled
                    ? (v) {
                        if (v == null) return;
                        setState(() {
                          _patternLength = v;
                          _hasLocalChanges = true;
                        });
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Legend strip ──────────────────────────────────────────────────────────────
  Widget _legendStrip(BuildContext context) {
    final palette = context.palette;
    Widget item(Color color, String label, {bool outline = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: outline ? Colors.transparent : color,
                border: outline ? Border.all(color: palette.border) : null,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
          ],
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        item(AppColors.parentDad, 'Dad'),
        item(AppColors.parentMom, 'Mom'),
        item(AppColors.parentBoth, 'Both'),
        item(Colors.transparent, 'None', outline: true),
      ],
    );
  }

  // ── Week card ───────────────────────────────────────────────────────────────
  Widget _weekCard(BuildContext context, int weekIndex) {
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
          if (_patternLength > 1) ...[
            Text('Week ${weekIndex + 1}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            const SizedBox(height: 8),
          ],
          // Day-name header row
          Row(
            children: [
              for (int i = 0; i < 7; i++) ...[
                Expanded(
                  child: Text(_dayNames[i].substring(0, 3),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: palette.textSecondary)),
                ),
                if (i < 6) const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int d = 0; d < 7; d++) ...[
                Expanded(child: _dayCell(context, weekIndex, d)),
                if (d < 6) const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCell(BuildContext context, int weekIndex, int dayIndex) {
    final data = _getDayData(weekIndex, dayIndex);
    final parent = data.parentAssignment;
    final hasConflict = data.hasConflict;
    final isChanged = data.isChangedFromPrevious;
    final start = _parseTod(data.transferTime);
    final end = _parseTod(data.transferEndTime);
    final hasLocation =
        data.transferLatitude != null || (data.transferLocationName?.isNotEmpty ?? false);
    final partnerMode = _hasActiveProposal && !(_activeProposal?.isCurrentUserProposer ?? false);
    final selected = weekIndex == _selWeek && dayIndex == _selDay;
    final decoration = _cellDecoration(context, parent, start, end, hasConflict, isChanged);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _openDayEditor(weekIndex, dayIndex);
      },
      onLongPress: partnerMode
          ? () {
              HapticFeedback.mediumImpact();
              _toggleConflict(weekIndex, dayIndex);
            }
          : null,
      // AnimatedContainer crossfades the parent colour / border when a day is
      // reassigned or selected, instead of snapping.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        height: 64,
        padding: const EdgeInsets.all(4),
        decoration: selected
            ? decoration.copyWith(border: Border.all(color: AppColors.primaryBlue, width: 3))
            : decoration,
        child: Stack(
          children: [
            // Indicators (top center)
            if (hasConflict || isChanged)
              Align(
                alignment: Alignment.topCenter,
                child: Text(hasConflict ? '⚠️' : '✏️', style: const TextStyle(fontSize: 11)),
              ),
            // Hint for empty days
            if (parent == 'None' && !hasConflict && !isChanged)
              Center(
                child: Text('Tap to\nedit',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 9,
                        color: context.isDark ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF))),
              ),
            // Time / location mini-icons (bottom center)
            if (start != null || hasLocation)
              Align(
                alignment: Alignment.bottomCenter,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (start != null)
                      const AppIcon('icon_clock', size: 12, color: Color(0xFF111827)),
                    if (start != null && hasLocation) const SizedBox(width: 3),
                    if (hasLocation)
                      const AppIcon('icon_location', size: 12, color: Color(0xFF111827)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cellDecoration(
      BuildContext context, String parent, TimeOfDay? start, TimeOfDay? end, bool conflict, bool changed) {
    final palette = context.palette;
    Color borderColor;
    double borderWidth;
    if (conflict) {
      borderColor = const Color(0xFFEF4444);
      borderWidth = 3;
    } else if (changed) {
      borderColor = const Color(0xFFF59E0B);
      borderWidth = 2;
    } else {
      borderColor = palette.border;
      borderWidth = 1;
    }

    final base = _parentEnum(parent).fill; // transparent for None
    Color? solid;
    Gradient? gradient;

    if (conflict) {
      solid = const Color(0xFFFEE2E2).withValues(alpha: 0.5);
    } else if (start != null && parent != 'None' && parent != 'Both') {
      final startP = ((start.hour * 60 + start.minute) / (24 * 60)).clamp(0.0, 1.0);
      final from = base;
      final to = parent == 'Husband' ? AppColors.parentMom : AppColors.parentDad;
      if (end != null && (end.hour * 60 + end.minute) > (start.hour * 60 + start.minute)) {
        final endP = ((end.hour * 60 + end.minute) / (24 * 60)).clamp(0.0, 1.0);
        gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [from, from, to, to, from, from],
          stops: _stops([0, startP - 0.001, startP, endP, endP + 0.001, 1]),
        );
      } else {
        gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [from, from, to, to],
          stops: _stops([0, startP - 0.001, startP, 1]),
        );
      }
    } else {
      solid = base;
    }

    return BoxDecoration(
      color: solid,
      gradient: gradient,
      border: Border.all(color: borderColor, width: borderWidth),
      borderRadius: BorderRadius.circular(12),
    );
  }

  /// Clamp to [0,1] and force non-decreasing so Flutter accepts the gradient stops.
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

  // ── Special days ──────────────────────────────────────────────────────────────
  Widget _specialDays(BuildContext context) {
    final palette = context.palette;
    final overrides = _displayOverrides();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Special days',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    Text('Holidays and one-off overrides',
                        style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _openOverrideEditor(null),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.successGreen, borderRadius: BorderRadius.circular(18)),
                  child: const Center(child: AppIcon('icon_plus', size: 18, color: Colors.white)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (overrides.isEmpty)
            Text('No special days yet — tap + to add holidays or one-off changes.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: palette.textSecondary))
          else
            for (final o in overrides) ...[
              _overrideRow(context, o),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _overrideRow(BuildContext context, ProposalOverrideDto o) {
    final palette = context.palette;
    final deleted = o.isMarkedForDeletion;
    final conflict = o.hasConflict;
    final changed = o.isChangedFromPrevious || o.isNewInThisVersion;
    final dateLabel = '${_monthAbbrev(o.month)}\n${o.day}';
    final title = '${_monthName(o.month)} ${o.day} - ${_displayParent(o.parentAssignment)}';

    Color borderColor;
    double borderWidth;
    if (deleted) {
      borderColor = const Color(0xFFDC2626);
      borderWidth = 2;
    } else if (conflict) {
      borderColor = const Color(0xFFEF4444);
      borderWidth = 3;
    } else if (changed) {
      borderColor = const Color(0xFFF59E0B);
      borderWidth = 2;
    } else {
      borderColor = palette.border;
      borderWidth = 1;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: deleted ? const Color(0xFFFEE2E2).withValues(alpha: 0.5) : palette.surfaceInput,
        border: Border.all(color: borderColor, width: borderWidth),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: _parentEnum(o.parentAssignment).fill, borderRadius: BorderRadius.circular(8)),
            child: Center(
              child: Text(dateLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _parentEnum(o.parentAssignment).onFill)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: deleted ? const Color(0xFF9CA3AF) : palette.textPrimary,
                              decoration: deleted ? TextDecoration.lineThrough : null)),
                    ),
                    if (conflict && !deleted) const Text('  ⚠️', style: TextStyle(fontSize: 12)),
                    if (changed && !deleted) const Text('  ✏️', style: TextStyle(fontSize: 12)),
                    if (o.isAnnual && !deleted) ...[
                      const SizedBox(width: 4),
                      const AppIcon('icon_refresh', size: 14, color: Color(0xFF059669)),
                    ],
                  ],
                ),
                if (o.description?.isNotEmpty ?? false)
                  Text(o.description!,
                      style: TextStyle(
                          fontSize: 12,
                          color: deleted ? const Color(0xFF9CA3AF) : palette.textSecondary,
                          decoration: deleted ? TextDecoration.lineThrough : null)),
                if (deleted)
                  const Text('(Proposed Deletion)',
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFDC2626))),
              ],
            ),
          ),
          if (deleted)
            _roundBtn(const Color(0xFF059669), 'icon_refresh', () => _undoDeleteOverride(o.dateKey))
          else ...[
            _roundBtn(AppColors.primaryBlue, 'icon_edit', () => _openOverrideEditor(o.dateKey)),
            const SizedBox(width: 8),
            _roundBtn(const Color(0xFFEF4444), 'icon_trash', () => _deleteOverride(o.dateKey)),
          ],
        ],
      ),
    );
  }

  Widget _roundBtn(Color bg, String icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
          child: Center(child: AppIcon(icon, size: 18, color: Colors.white)),
        ),
      );

  // ── Proposal notification (accept/reject/counter) ──────────────────────────────
  Widget _proposalNotification(BuildContext context) {
    final p = _activeProposal!;
    final partner = !p.isCurrentUserProposer;
    final showAcceptReject = partner && !_isEditingCounterProposal;
    final showWithdraw = p.isCurrentUserProposer && p.status == 'submitted';

    final titleText = partner ? 'Partner Proposed Changes' : 'You Have Proposed Changes';
    final descText = partner
        ? (_isEditingCounterProposal
            ? "You're creating a counter-proposal. Submit when ready."
            : 'Review the changes. Tap a day to edit, long-press to mark as conflict.')
        : (p.status == 'draft'
            ? 'Your proposal is in draft. Make changes and submit when ready.'
            : 'Your proposal has been submitted. You can modify and submit a new version.');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF451A03) : AppColors.warningBgLight,
        border: Border.all(color: AppColors.warningAmber),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFFED7AA), borderRadius: BorderRadius.circular(12)),
                child: const Center(child: AppIcon('icon_alert', size: 20, color: AppColors.warningAmber)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titleText,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: context.isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E))),
                    const SizedBox(height: 4),
                    Text(descText,
                        style: TextStyle(
                            fontSize: 13, color: context.isDark ? const Color(0xFFFDE68A) : const Color(0xFFA16207))),
                  ],
                ),
              ),
            ],
          ),
          if (showAcceptReject) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _outlineBtn(context, 'Reject', AppColors.dangerRed, _reject)),
                const SizedBox(width: 8),
                Expanded(child: _outlineBtn(context, 'Counter', AppColors.warningAmber, _startCounter)),
                const SizedBox(width: 8),
                Expanded(child: _outlineBtn(context, 'Accept', AppColors.successGreen, _accept)),
              ],
            ),
          ],
          if (showWithdraw) ...[
            const SizedBox(height: 16),
            _outlineBtn(context, 'Withdraw Proposal', AppColors.dangerRed, _withdraw),
          ],
        ],
      ),
    );
  }

  Widget _outlineBtn(BuildContext context, String label, Color color, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color, width: 2),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      onPressed: onTap,
      child: Text(label,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
    );
  }

  // ── Action buttons ─────────────────────────────────────────────────────────────
  Widget _actionButtons(BuildContext context) {
    final palette = context.palette;
    final (saveText, saveColor) = _saveButton();
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.textSecondary,
              side: BorderSide(color: palette.border, width: 2),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            onPressed: _onBack,
            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: saveColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            onPressed: _onSave,
            child: Text(saveText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  (String, Color) _saveButton() {
    if (_isOnboarding) return ('Continue', const Color(0xFF10B981));
    if (_isEditingCounterProposal || _hasLocalChanges) return ('Submit Proposal', const Color(0xFFF59E0B));
    if (_hasActiveProposal && _activeProposal?.isCurrentUserProposer == true && _activeProposal?.status == 'draft') {
      return ('Submit Proposal', AppColors.primaryBlue);
    }
    return ('Save Schedule', AppColors.primaryBlue);
  }

  // ── Bottom sheets ─────────────────────────────────────────────────────────────
  void _openDayEditor(int weekIndex, int dayIndex) {
    final title = _patternLength > 1 ? 'Week ${weekIndex + 1} · ${_dayNames[dayIndex]}' : _dayNames[dayIndex];
    setState(() {
      _selWeek = weekIndex;
      _selDay = dayIndex;
      _dockedEditor = DayEditorView(
        // Unique key per (week, day) so switching days without closing the sheet
        // rebuilds the editor State (re-runs initState with the new day's data)
        // instead of reusing the previous day's stale fields.
        key: ValueKey('day-$weekIndex-$dayIndex'),
        weekIndex: weekIndex,
        dayIndex: dayIndex,
        title: title,
        data: _getDayData(weekIndex, dayIndex),
        baseline: _getApprovedDayBaseline(weekIndex, dayIndex),
        pois: _allPois,
        onCommit: _applyDayEdit,
        onClose: _closeSheet,
      );
    });
    _scrollToWeek(weekIndex);
  }

  void _openOverrideEditor(String? existingDateKey) {
    final existing = existingDateKey != null ? _getExistingOverrideData(existingDateKey) : null;
    OverrideBaseline? baseline;
    if (existingDateKey != null) {
      for (final appr in _approvedSchedule?.overrides ?? const <ApprovedOverrideDto>[]) {
        if (appr.dateKey == existingDateKey) {
          baseline = OverrideBaseline(
            parent: appr.parentAssignment.isEmpty ? 'None' : appr.parentAssignment,
            time: _parseTod(appr.transferTime),
            endTime: null, // approved override DTO carries no end time
            locName: appr.transferLocationName,
            locAddr: appr.transferAddress,
          );
          break;
        }
      }
    }
    _showSheet(
      OverrideEditorView(
        key: ValueKey('override-${existingDateKey ?? 'new'}'),
        existingDateKey: existingDateKey,
        existing: existing,
        baseline: baseline,
        pois: _allPois,
        onApply: (r) {
          _closeSheet();
          _handleOverrideResult(r);
        },
        onClose: _closeSheet,
      ),
    );
  }

  void _showSheet(Widget child) {
    setState(() => _dockedEditor = child);
  }

  /// The docked editor panel: a bottom-anchored, NON-modal sheet (no barrier) so the
  /// calendar above stays scrollable/tappable. Capped height + scrolls internally;
  /// rides above the keyboard via viewInsets.
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
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(3)),
                  ),
                  _dockedEditor ?? const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showOnboarding() {
    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (_) => const _OnboardingDialog(),
    ).then((_) => Preferences.setBool(_onboardingKey, true));
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static String _monthName(int m) => _months[(m.clamp(1, 12)) - 1];
  static String _monthAbbrev(int m) => _monthName(m).substring(0, 3);
}

// ── Onboarding walkthrough (8 steps) ─────────────────────────────────────────────
class _OnboardingDialog extends StatefulWidget {
  const _OnboardingDialog();

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  int _step = 0;

  static const _steps = <_OnbStep>[
    _OnbStep('?', AppColors.iconBgBlue, AppColors.primaryBlue, 'Your custody calendar',
        "This is where you build your kids' schedule. We'll show you how — with examples — in a few quick taps.",
        visual: _Vis.welcome, note: 'Tap the ? button anytime to replay this guide.'),
    _OnbStep('icon_refresh', AppColors.iconBgBlue, AppColors.primaryBlue, 'What is a "cycle"?',
        'A cycle is just a pattern that repeats — like the days of the week always go Mon, Tue… then start over. You set up one or two weeks, and they repeat forever.',
        visual: _Vis.cycle, note: 'Most families use a 1- or 2-week cycle.'),
    _OnbStep('icon_calendar', Color(0xFFFCE7F3), Color(0xFFBE185D), 'Tap a day to set it',
        'Tap any day, then choose who has the kids: Dad, Mom, Both, or None. The day changes colour right away.',
        visual: _Vis.tapDay),
    _OnbStep('icon_clock', AppColors.iconBgGreen, AppColors.successGreen, 'Set handoff times',
        'For each day you can set when custody starts and ends — so pickup and drop-off times are crystal clear.',
        visual: _Vis.times),
    _OnbStep('icon_gift', AppColors.iconBgRed, AppColors.dangerRed, 'Holidays & special days',
        'Special dates can override the normal pattern. For example: Christmas → always Mom, July 4th → always Dad.',
        visual: _Vis.special),
    _OnbStep('icon_handshake', AppColors.iconBgGreen, AppColors.successGreen, 'Both parents must agree',
        'When you save, it becomes a proposal. Nothing changes until your co-parent accepts it.',
        visual: _Vis.propose),
    _OnbStep('icon_alert', AppColors.iconBgYellow, AppColors.warningAmber, 'Changes & conflicts',
        'Disagree with a day? Tap it to change it (turns yellow) and send a counter-proposal, or long-press to flag a conflict (turns red).',
        visual: _Vis.conflict),
    _OnbStep('icon_sparkle', AppColors.iconBgPurple, AppColors.accentPurple, 'Need a hand? Use the menu',
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
                    onPressed: () => Navigator.of(context).pop(),
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

  Widget _hero(BuildContext context, _OnbStep s) {
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
      case _Vis.propose:
        return _card(
          context,
          Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _avatar('You', const Color(0xFF3B82F6)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Icons.send, size: 18, color: _muted)),
              _avatar('Co-parent', const Color(0xFFEC4899)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(20)),
              child: const Text('Waiting for them to accept',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
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
              _dot(const Color(0xFFEF4444), 'Conflict'),
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

/// Which example illustration a tutorial step shows (above the title).
enum _Vis { none, welcome, cycle, tapDay, times, special, propose, conflict, menu }

class _OnbStep {
  final String icon; // 'icon_*' name, or a literal glyph like '?'
  final Color iconBg;
  final Color iconTint;
  final String title;
  final String body;
  final String? note;
  final _Vis visual;
  const _OnbStep(this.icon, this.iconBg, this.iconTint, this.title, this.body,
      {this.note, this.visual = _Vis.none});
}

// ── Floating action menu (hamburger that opens upward) ───────────────────────────
/// Replaces the single AI FAB: a menu button that expands upward to expose the AI
/// assistant, the template catalog, and the how-it-works guide.
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
