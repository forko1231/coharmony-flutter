import 'package:flutter/material.dart';
import '../../models/custody_models.dart';
import '../../models/location_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import 'editor_models.dart';
import 'twelve_hour_time_picker.dart';

/// The custody day editor — port of `DayEditorView.xaml(.cs)`. Parent chips, an
/// optional handoff time (start + optional end window), and an optional handoff
/// location, with per-field "was X · Revert" diff rows against [baseline].
///
/// MAUI built this once and retargeted it via `Load`; in Flutter it's shown fresh in
/// a bottom sheet per tap, so the constructor takes the day's data directly. Edits are
/// reported live via [onCommit] (mirroring MAUI's `EditCommitted`); the page owns the
/// draft + grid recolor. [onClose] dismisses.
class DayEditorView extends StatefulWidget {
  const DayEditorView({
    super.key,
    required this.weekIndex,
    required this.dayIndex,
    required this.title,
    required this.data,
    required this.baseline,
    required this.pois,
    required this.onCommit,
    required this.onClose,
  });

  final int weekIndex;
  final int dayIndex;
  final String title;
  final ProposalDayDto data;
  final DayBaseline? baseline;
  final List<PointOfInterest> pois;
  final void Function(DayEditCommit) onCommit;
  final VoidCallback onClose;

  @override
  State<DayEditorView> createState() => _DayEditorViewState();
}

class _DayEditorViewState extends State<DayEditorView> {
  late String _selectedParent;
  bool _setTime = false;
  bool _setEnd = false;
  bool _setLoc = false;
  TimeOfDay _start = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 18, minute: 0);
  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();

  static const _chips = <(String, String, Color)>[
    ('Husband', 'Dad', Color(0xFF3B82F6)),
    ('Wife', 'Mom', Color(0xFFEC4899)),
    ('Both', 'Both', Color(0xFF8B5CF6)),
    ('None', 'None', Color(0xFF6B7280)),
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _selectedParent = d.parentAssignment.isEmpty ? 'None' : d.parentAssignment;
    final start = _parse(d.transferTime);
    final end = _parse(d.transferEndTime);
    _setTime = start != null;
    _start = start ?? const TimeOfDay(hour: 17, minute: 0);
    _setEnd = end != null;
    _end = end ?? const TimeOfDay(hour: 18, minute: 0);
    final hasLoc = (d.transferLocationName?.isNotEmpty ?? false) ||
        (d.transferAddress?.isNotEmpty ?? false);
    _setLoc = hasLoc;
    _nameCtrl.text = d.transferLocationName ?? '';
    _addrCtrl.text = d.transferAddress ?? '';
  }

  @override
  void dispose() {
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

  // ── Commit (mirrors MAUI Commit) ────────────────────────────────────────────
  void _commit({bool recolor = false}) {
    TimeOfDay? tt = _setTime ? _start : null;
    TimeOfDay? tet = (_setTime && _setEnd) ? _end : null;
    if (tt != null && tet != null && _toMin(tet) <= _toMin(tt)) tet = null;

    LocationData? loc;
    if (_setLoc) {
      final name = _nameCtrl.text.trim();
      final addr = _addrCtrl.text.trim();
      if (name.isNotEmpty || addr.isNotEmpty) {
        PointOfInterest? poi;
        for (final p in widget.pois) {
          if ((p.name == name || p.displayName == name) &&
              (addr.isEmpty || p.address == addr)) {
            poi = p;
            break;
          }
        }
        loc = poi != null
            ? LocationData(poi.latitude, poi.longitude, name, addr)
            : LocationData(null, null, name, addr);
      }
    }

    widget.onCommit(DayEditCommit(
      weekIndex: widget.weekIndex,
      dayIndex: widget.dayIndex,
      parent: _selectedParent,
      transferTime: tt,
      transferEndTime: tet,
      location: loc,
      recolor: recolor,
    ));
  }

  static int _toMin(TimeOfDay t) => t.hour * 60 + t.minute;

  void _selectParent(String key) {
    setState(() => _selectedParent = key);
    _commit(recolor: true);
  }

  // ── "was X · Revert" diff helpers ───────────────────────────────────────────
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
    _commit(recolor: true);
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
    _commit(recolor: true);
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
    _commit(recolor: true);
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
    _commit(recolor: true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final diff = _diff();
    final edited = diff.parent || diff.time || diff.loc;
    final b = widget.baseline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title,
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
          _commit(recolor: true);
        }, help: true),
        if (_setTime) ...[
          const SizedBox(height: 8),
          _pickerBox(context, TwelveHourTimePicker(value: _start, onChanged: (t) {
            setState(() => _start = t);
            _commit();
          })),
          const SizedBox(height: 8),
          _checkRow(context, 'Set end time (visit window)', _setEnd, (v) {
            setState(() => _setEnd = v);
            _commit(recolor: true);
          }),
          if (_setEnd) ...[
            const SizedBox(height: 6),
            _pickerBox(context, TwelveHourTimePicker(value: _end, onChanged: (t) {
              setState(() => _end = t);
              _commit();
            })),
          ],
        ],
        if (diff.time && b != null) _wasRow(context, 'was: ${_timeWas(b)}', _revertTime),
        const SizedBox(height: 12),
        // Handoff location
        _checkRow(context, 'Set handoff location', _setLoc, (v) {
          setState(() => _setLoc = v);
          _commit(recolor: true);
        }),
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
      ],
    );
  }

  static String _timeWas(DayBaseline b) {
    if (b.time == null) return 'no handoff time';
    return b.endTime != null ? '${_fmt(b.time!)}–${_fmt(b.endTime!)}' : _fmt(b.time!);
  }

  static String _locWas(DayBaseline b) {
    final baseHasLoc = (b.locName?.isNotEmpty ?? false) || (b.locAddr?.isNotEmpty ?? false);
    if (!baseHasLoc) return 'no location';
    return (b.locName?.isNotEmpty ?? false) ? b.locName! : b.locAddr!;
  }

  Widget _chip(BuildContext context, (String, String, Color) c) {
    final palette = context.palette;
    final selected = _selectedParent == c.$1;
    final accent = c.$3;
    return GestureDetector(
      onTap: () => _selectParent(c.$1),
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
        onChanged: (_) {
          setState(() {}); // refresh diff rows
          _commit();
        },
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
