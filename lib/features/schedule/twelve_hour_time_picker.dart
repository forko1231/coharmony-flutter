import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';

/// Port of the custom `TwelveHourTimePicker` control — a tappable field that
/// shows a 12-hour time and opens the platform time picker to change it.
class TwelveHourTimePicker extends StatelessWidget {
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;

  const TwelveHourTimePicker({super.key, required this.value, required this.onChanged});

  String _format(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: value);
        if (picked != null) onChanged(picked);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_format(value), style: TextStyle(fontSize: 15, color: palette.textPrimary)),
          Icon(Icons.access_time, size: 18, color: palette.textSecondary),
        ],
      ),
    );
  }
}
