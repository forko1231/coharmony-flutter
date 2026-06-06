import 'package:flutter/material.dart';
import '../../models/custody_models.dart';
import '../../models/location_models.dart';
import '../../services/holiday_resolver.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import 'editor_models.dart';
import 'twelve_hour_time_picker.dart';

/// The custody override (special day) editor — port of `OverrideEditorView.xaml(.cs)`.
/// Holiday-or-manual date, parent chips, optional handoff time/window, optional
/// location, annual + alternating toggles, with "was X · Revert" diff against an
/// approved baseline. On Add/Update it raises [onApply] with an [OverrideDayEditResult].
class OverrideEditorView extends StatefulWidget {
  const OverrideEditorView({
    super.key,
    required this.existingDateKey,
    required this.existing,
    required this.baseline,
    required this.pois,
    required this.onApply,
    required this.onClose,
  });

  final String? existingDateKey;
  final ProposalOverrideDto? existing;
  final OverrideBaseline? baseline;
  final List<PointOfInterest> pois;
  final void Function(OverrideDayEditResult) onApply;
  final VoidCallback onClose;

  @override
  State<OverrideEditorView> createState() => _OverrideEditorViewState();
}

class _OverrideEditorViewState extends State<OverrideEditorView> {
  late DateTime _selectedDate;
  String _selectedParent = 'None';
  String? _selectedHolidayRule;
  bool _setTime = false;
  bool _setEnd = false;
  bool _setLoc = false;
  bool _isAnnual = false;
  bool _isAlternating = false;
  TimeOfDay _start = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 18, minute: 0);
  final _descCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static const _chips = <(String, String, Color)>[
    ('Husband', 'Dad', Color(0xFF3B82F6)),
    ('Wife', 'Mom', Color(0xFFEC4899)),
    ('Both', 'Both', Color(0xFF8B5CF6)),
    ('None', 'None', Color(0xFF6B7280)),
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    final ex = widget.existing;
    if (ex != null) {
      try {
        _selectedDate = DateTime(DateTime.now().year, ex.month, ex.day);
      } catch (_) {
        _selectedDate = DateTime.now();
      }
      _selectedParent = ex.parentAssignment.isEmpty ? 'None' : ex.parentAssignment;
      final start = _parse(ex.transferTime);
      final end = _parse(ex.transferEndTime);
      _setTime = start != null;
      _start = start ?? const TimeOfDay(hour: 17, minute: 0);
      _setEnd = end != null;
      _end = end ?? const TimeOfDay(hour: 18, minute: 0);
      _descCtrl.text = ex.description ?? '';
      _isAnnual = ex.isAnnual;
      _isAlternating = (ex.alternationMode) == 'alternating';
      _selectedHolidayRule = ex.holidayRule;
      final hasLoc =
          ex.transferLatitude != null || (ex.transferLocationName?.isNotEmpty ?? false);
      _setLoc = hasLoc;
      _nameCtrl.text = ex.transferLocationName ?? '';
      _addrCtrl.text = ex.transferAddress ?? '';
    }

    // Resolve holiday date if a rule is set.
    if (_selectedHolidayRule != null && _selectedHolidayRule!.isNotEmpty) {
      final resolved = HolidayResolver.resolveDate(_selectedHolidayRule, _selectedDate.year);
      if (resolved != null) _selectedDate = resolved;
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  static TimeOfDay? _parse(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static int _toMin(TimeOfDay t) => t.hour * 60 + t.minute;
  static String _monthDay(DateTime d) => '${_monthNames[d.month.clamp(1, 12) - 1]} ${d.day}';

  // ── Holiday / date ──────────────────────────────────────────────────────────
  Future<void> _pickHoliday() async {
    final holidays = HolidayResolver.getAllHolidays();
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
                title: const Text('None (pick a date)'),
                onTap: () => Navigator.of(ctx).pop('__none__')),
            for (final h in holidays)
              if (h.displayName.trim().isNotEmpty)
                ListTile(title: Text(h.displayName), onTap: () => Navigator.of(ctx).pop(h.rule)),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == '__none__') {
      setState(() => _selectedHolidayRule = null);
      return;
    }
    final resolved = HolidayResolver.resolveDate(choice, DateTime.now().year);
    setState(() {
      _selectedHolidayRule = choice;
      if (resolved != null) _selectedDate = resolved;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  // ── "was X · Revert" diff ─────────────────────────────────────────────────────
  static String _displayParent(String p) => switch (p) {
        'Husband' => 'Dad',
        'Wife' => 'Mom',
        'Both' => 'Both',
        _ => 'None',
      };

  static String _fmt(TimeOfDay t) {
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    var dh = t.hour % 12;
    if (dh == 0) dh = 12;
    return '$dh:${t.minute.toString().padLeft(2, '0')} $ampm';
  }

  ({bool parent, bool time, bool loc}) _diff() {
    final b = widget.baseline;
    if (b == null) return (parent: false, time: false, loc: false);
    TimeOfDay? curStart = _setTime ? _start : null;
    TimeOfDay? curEnd = (_setTime && _setEnd) ? _end : null;
    if (curStart != null && curEnd != null && _toMin(curEnd) <= _toMin(curStart)) {
      curEnd = null;
    }
    final curHasLoc =
        _setLoc && (_nameCtrl.text.trim().isNotEmpty || _addrCtrl.text.trim().isNotEmpty);
    final curLocName = curHasLoc ? _nameCtrl.text.trim() : '';
    final curLocAddr = curHasLoc ? _addrCtrl.text.trim() : '';
    return (
      parent: b.parent != _selectedParent,
      time: b.time != curStart || b.endTime != curEnd,
      loc: (b.locName ?? '') != curLocName || (b.locAddr ?? '') != curLocAddr,
    );
  }

  void _revertParent() {
    final b = widget.baseline;
    if (b == null) return;
    setState(() => _selectedParent = b.parent);
  }

  void _revertTime() {
    final b = widget.baseline;
    if (b == null) return;
    setState(() {
      _setTime = b.time != null;
      _start = b.time ?? const TimeOfDay(hour: 17, minute: 0);
      _setEnd = b.endTime != null;
      _end = b.endTime ?? const TimeOfDay(hour: 18, minute: 0);
    });
  }

  void _revertLocation() {
    final b = widget.baseline;
    if (b == null) return;
    final baseHasLoc = (b.locName?.isNotEmpty ?? false) || (b.locAddr?.isNotEmpty ?? false);
    setState(() {
      _setLoc = baseHasLoc;
      _nameCtrl.text = b.locName ?? '';
      _addrCtrl.text = b.locAddr ?? '';
    });
  }

  Future<void> _chooseExistingLocation() async {
    final names = <String>{
      for (final p in widget.pois)
        if ((p.displayName).trim().isNotEmpty) p.displayName.trim(),
    }.toList();
    if (names.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No Locations'),
          content: const Text('You have no saved locations yet. Create one on the map first.'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final n in names)
              ListTile(title: Text(n), onTap: () => Navigator.of(ctx).pop(n)),
          ],
        ),
      ),
    );
    if (choice == null) return;
    PointOfInterest? poi;
    for (final p in widget.pois) {
      if (p.displayName == choice) {
        poi = p;
        break;
      }
    }
    if (poi == null) return;
    setState(() {
      _nameCtrl.text = poi!.name.isNotEmpty ? poi.name : poi.displayName;
      _addrCtrl.text = poi.address ??
          '${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}';
    });
  }

  // ── Apply ─────────────────────────────────────────────────────────────────────
  Future<void> _apply() async {
    final date = _selectedDate;
    final dateKey = '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    TimeOfDay? tt = _setTime ? _start : null;
    TimeOfDay? tet = (_setTime && _setEnd) ? _end : null;
    if (tt != null && tet != null && _toMin(tet) <= _toMin(tt)) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Invalid time range'),
          content: const Text('Transfer end time must be after the transfer time.'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }

    LocationData? loc;
    if (_setLoc) {
      final nm = _nameCtrl.text.trim();
      final ad = _addrCtrl.text.trim();
      if (nm.isNotEmpty || ad.isNotEmpty) {
        PointOfInterest? poi;
        for (final p in widget.pois) {
          if ((p.name == nm || p.displayName == nm) && (ad.isEmpty || p.address == ad)) {
            poi = p;
            break;
          }
        }
        loc = poi != null
            ? LocationData(poi.latitude, poi.longitude, nm, ad)
            : LocationData(null, null, nm, ad);
      }
    }

    var altMode = 'fixed';
    String? altStart;
    if (_isAnnual && _isAlternating) {
      altMode = 'alternating';
      altStart = _selectedParent == 'None' ? 'Husband' : _selectedParent;
    }

    widget.onApply(OverrideDayEditResult(
      dateKey: dateKey,
      originalDateKey: widget.existingDateKey,
      selectedDate: date,
      parent: _selectedParent,
      transferTime: tt,
      transferEndTime: tet,
      description: _descCtrl.text.trim(),
      isAnnual: _isAnnual,
      alternationMode: altMode,
      alternationStartParent: altStart,
      transferLocation: loc,
      holidayRule: _selectedHolidayRule,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isEdit = widget.existingDateKey != null;
    final diff = _diff();
    final edited = diff.parent || diff.time || diff.loc;
    final b = widget.baseline;
    final hasHoliday = _selectedHolidayRule != null && _selectedHolidayRule!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(isEdit ? 'Edit special day' : 'Add a special day',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            ),
            if (edited)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.warningAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('Edited',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.warningAmber)),
              ),
            GestureDetector(
              onTap: widget.onClose,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('✕', style: TextStyle(fontSize: 18, color: palette.textSecondary)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Holiday selector
        _label(context, 'Holiday'),
        const SizedBox(height: 4),
        _tapField(
            context,
            hasHoliday ? HolidayResolver.getDisplayName(_selectedHolidayRule!) : 'None (pick a date below)',
            _pickHoliday),
        if (hasHoliday) ...[
          const SizedBox(height: 4),
          Text('Date: ${_monthDay(_selectedDate)} (auto each year)',
              style: TextStyle(fontSize: 12, color: palette.textSecondary)),
        ] else ...[
          const SizedBox(height: 10),
          _label(context, 'Date'),
          const SizedBox(height: 4),
          _tapField(context, _monthDay(_selectedDate), _pickDate),
        ],
        const SizedBox(height: 12),
        // Description
        _entryBox(context, 'Description (e.g. Christmas with Mom)', _descCtrl),
        const SizedBox(height: 12),
        // Parent chips
        Row(
          children: [
            for (int i = 0; i < _chips.length; i++) ...[
              Expanded(child: _chip(context, _chips[i])),
              if (i < _chips.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
        if (diff.parent && b != null) _wasRow(context, 'was: ${_displayParent(b.parent)}', _revertParent),
        const SizedBox(height: 12),
        // Handoff time
        _checkRow(context, 'Set handoff time', _setTime, (v) {
          setState(() {
            _setTime = v;
            if (!v) _setEnd = false;
          });
        }, help: true),
        if (_setTime) ...[
          const SizedBox(height: 8),
          _pickerBox(context, TwelveHourTimePicker(value: _start, onChanged: (t) => setState(() => _start = t))),
          const SizedBox(height: 8),
          _checkRow(context, 'Set end time (visit window)', _setEnd, (v) => setState(() => _setEnd = v)),
          if (_setEnd) ...[
            const SizedBox(height: 6),
            _pickerBox(context, TwelveHourTimePicker(value: _end, onChanged: (t) => setState(() => _end = t))),
          ],
        ],
        if (diff.time && b != null) _wasRow(context, 'was: ${_timeWas(b)}', _revertTime),
        const SizedBox(height: 12),
        // Handoff location
        _checkRow(context, 'Set handoff location', _setLoc, (v) => setState(() => _setLoc = v)),
        if (_setLoc) ...[
          const SizedBox(height: 8),
          _entryBox(context, 'Location name (e.g. School)', _nameCtrl),
          const SizedBox(height: 8),
          _entryBox(context, 'Address (street, city, state)', _addrCtrl),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryBlueLight,
              side: const BorderSide(color: AppColors.primaryBlueLight),
              minimumSize: const Size(0, 42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: _chooseExistingLocation,
            child: const Text('Choose existing location', style: TextStyle(fontSize: 13)),
          ),
        ],
        if (diff.loc && b != null) _wasRow(context, 'was: ${_locWas(b)}', _revertLocation),
        const SizedBox(height: 12),
        // Annual + alternating
        _checkRow(context, 'Repeats every year', _isAnnual, (v) {
          setState(() {
            _isAnnual = v;
            if (!v) _isAlternating = false;
          });
        }),
        if (_isAnnual)
          _checkRow(context, 'Alternate between parents each year', _isAlternating,
              (v) => setState(() => _isAlternating = v)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.textSecondary,
                  side: BorderSide(color: palette.border, width: 2),
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                ),
                onPressed: widget.onClose,
                child: const Text('Cancel', style: TextStyle(fontSize: 15)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.successGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                ),
                onPressed: _apply,
                child: Text(isEdit ? 'Update' : 'Add',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _timeWas(OverrideBaseline b) {
    if (b.time == null) return 'no handoff time';
    return b.endTime != null ? '${_fmt(b.time!)}–${_fmt(b.endTime!)}' : _fmt(b.time!);
  }

  static String _locWas(OverrideBaseline b) {
    final baseHasLoc = (b.locName?.isNotEmpty ?? false) || (b.locAddr?.isNotEmpty ?? false);
    if (!baseHasLoc) return 'no location';
    return (b.locName?.isNotEmpty ?? false) ? b.locName! : b.locAddr!;
  }

  Widget _label(BuildContext context, String text) => Text(text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textSecondary));

  Widget _tapField(BuildContext context, String text, VoidCallback onTap) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF111827) : Colors.white,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: palette.textPrimary))),
            Icon(Icons.expand_more, size: 18, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, (String, String, Color) c) {
    final palette = context.palette;
    final selected = _selectedParent == c.$1;
    final accent = c.$3;
    return GestureDetector(
      onTap: () => setState(() => _selectedParent = c.$1),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : palette.surfaceInput,
          border: Border.all(color: selected ? accent : palette.border, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(c.$2,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: selected ? accent : palette.textSecondary)),
      ),
    );
  }

  Widget _wasRow(BuildContext context, String text, VoidCallback onRevert) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.warningAmber)),
          ),
          GestureDetector(
            onTap: onRevert,
            child: const Text('Revert',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryBlueLight)),
          ),
        ],
      ),
    );
  }

  Widget _checkRow(BuildContext context, String label, bool value, ValueChanged<bool> onChanged,
      {bool help = false}) {
    final palette = context.palette;
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: palette.textPrimary))),
        if (help)
          GestureDetector(
            onTap: () => _showTimeHelp(context),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Center(
                  child: Text('?',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryBlueLight))),
            ),
          ),
      ],
    );
  }

  Widget _pickerBox(BuildContext context, Widget child) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF111827) : Colors.white,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  Widget _entryBox(BuildContext context, String hint, TextEditingController ctrl) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF111827) : Colors.white,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: ctrl,
        style: TextStyle(fontSize: 14, color: palette.textPrimary),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: palette.textPlaceholder),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }

  void _showTimeHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Handoff time'),
        content: const Text(
            "Set when the assigned parent's custody begins on this day. Optionally set an end time to define a visit window that returns to the other parent."),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it'))],
      ),
    );
  }
}
