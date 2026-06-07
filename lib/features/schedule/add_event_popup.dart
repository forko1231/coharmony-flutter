import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import 'twelve_hour_time_picker.dart';

/// Result of the add/edit-event dialog — port of `AddEventPopupResult`.
class AddEventResult {
  const AddEventResult({
    required this.eventName,
    required this.startTime,
    required this.endTime,
    required this.repeatPattern,
    this.repeatEndDate,
    this.visibleToKids = true,
  });
  final String eventName;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String repeatPattern; // "none" | "weekly" | ...
  final DateTime? repeatEndDate;
  final bool visibleToKids; // also shown on linked kids' calendars
}

/// Port of `AddEventPopupView.xaml(.cs)` — a centered dialog for creating/editing an
/// event. Returns an [AddEventResult] via `Navigator.pop` (null on cancel).
class AddEventPopup extends StatefulWidget {
  const AddEventPopup({
    super.key,
    this.isEdit = false,
    this.initialName,
    this.initialStart,
    this.initialEnd,
    this.initialRepeat,
    this.initialRepeatEnd,
    this.initialVisibleToKids = true,
  });

  final bool isEdit;
  final String? initialName;
  final TimeOfDay? initialStart;
  final TimeOfDay? initialEnd;
  final String? initialRepeat;
  final DateTime? initialRepeatEnd;
  final bool initialVisibleToKids;

  /// Present the dialog; resolves to the entered event (or null if cancelled).
  static Future<AddEventResult?> show(
    BuildContext context, {
    bool isEdit = false,
    String? initialName,
    TimeOfDay? initialStart,
    TimeOfDay? initialEnd,
    String? initialRepeat,
    DateTime? initialRepeatEnd,
    bool initialVisibleToKids = true,
  }) =>
      showDialog<AddEventResult>(
        context: context,
        builder: (_) => AddEventPopup(
          isEdit: isEdit,
          initialName: initialName,
          initialStart: initialStart,
          initialEnd: initialEnd,
          initialRepeat: initialRepeat,
          initialRepeatEnd: initialRepeatEnd,
          initialVisibleToKids: initialVisibleToKids,
        ),
      );

  @override
  State<AddEventPopup> createState() => _AddEventPopupState();
}

class _AddEventPopupState extends State<AddEventPopup> {
  late final TextEditingController _name;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late String _repeat;
  late DateTime _repeatEnd;
  late bool _visibleToKids;

  static const _repeatOptions = ['none', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly', 'biyearly'];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _start = widget.initialStart ?? const TimeOfDay(hour: 8, minute: 0);
    _end = widget.initialEnd ?? const TimeOfDay(hour: 17, minute: 0);
    final r = (widget.initialRepeat ?? 'none').toLowerCase();
    _repeat = _repeatOptions.contains(r) ? r : 'none';
    _repeatEnd = widget.initialRepeatEnd ?? DateTime.now().add(const Duration(days: 30));
    _visibleToKids = widget.initialVisibleToKids;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static int _toMin(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _save() async {
    var name = _name.text.trim();
    if (name.isEmpty) name = 'Event';
    if (_toMin(_end) <= _toMin(_start)) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Invalid time range'),
          content: const Text('End time must be after start time.'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(AddEventResult(
      eventName: name,
      startTime: _start,
      endTime: _end,
      repeatPattern: _repeat,
      repeatEndDate: _repeat == 'none' ? null : _repeatEnd,
      visibleToKids: _visibleToKids,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      backgroundColor: palette.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(12)),
                      child: const Center(child: AppIcon('icon_calendar', size: 24, color: AppColors.primaryBlue)),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.isEdit ? 'Edit Event' : 'New Event',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                  ],
                ),
                const SizedBox(height: 20),
                Container(height: 1, color: palette.border),
                const SizedBox(height: 16),
                _label(context, 'Event Name'),
                const SizedBox(height: 8),
                _inputBox(context, _entry(context, 'Enter event name')),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(context, 'Start Time'),
                          const SizedBox(height: 8),
                          _inputBox(context,
                              TwelveHourTimePicker(value: _start, onChanged: (t) => setState(() => _start = t))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(context, 'End Time'),
                          const SizedBox(height: 8),
                          _inputBox(context,
                              TwelveHourTimePicker(value: _end, onChanged: (t) => setState(() => _end = t))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _label(context, 'Repeat Pattern'),
                const SizedBox(height: 8),
                _inputBox(
                  context,
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _repeat,
                      isExpanded: true,
                      dropdownColor: palette.surfaceElevated,
                      style: TextStyle(fontSize: 14, color: palette.textPrimary),
                      items: [for (final r in _repeatOptions) DropdownMenuItem(value: r, child: Text(r))],
                      onChanged: (v) => setState(() => _repeat = v ?? 'none'),
                    ),
                  ),
                ),
                if (_repeat != 'none') ...[
                  const SizedBox(height: 16),
                  _label(context, 'Repeating End Date'),
                  const SizedBox(height: 8),
                  _inputBox(
                    context,
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _repeatEnd,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(DateTime.now().year + 10),
                        );
                        if (picked != null) setState(() => _repeatEnd = picked);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              '${_repeatEnd.year}-${_repeatEnd.month.toString().padLeft(2, '0')}-${_repeatEnd.day.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 14, color: palette.textPrimary)),
                          Icon(Icons.calendar_today, size: 16, color: palette.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // Show on kids' calendars (off for adult-only events).
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.child_care, size: 20, color: palette.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Show to kids',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                            Text('Appears on your children\'s calendar',
                                style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _visibleToKids,
                        activeThumbColor: AppColors.primaryBlue,
                        onChanged: (v) => setState(() => _visibleToKids = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(height: 1, color: palette.border),
                const SizedBox(height: 16),
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
                        child: const Text('Cancel', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.successGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        onPressed: _save,
                        child: const Text('Save Event', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) =>
      Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary));

  Widget _inputBox(BuildContext context, Widget child) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(12)),
      child: child,
    );
  }

  Widget _entry(BuildContext context, String hint) {
    final palette = context.palette;
    return TextField(
      controller: _name,
      style: TextStyle(fontSize: 14, color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: palette.textSecondary),
        border: InputBorder.none,
        isDense: true,
      ),
    );
  }
}
