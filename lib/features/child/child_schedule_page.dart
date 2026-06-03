import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';

/// Port of `Views/Child/ChildSchedulePage.xaml` — a read-only month calendar
/// shaded by custody assignment, a legend, and a tapped-day detail card. Stub data.
class ChildSchedulePage extends StatefulWidget {
  const ChildSchedulePage({super.key});

  @override
  State<ChildSchedulePage> createState() => _ChildSchedulePageState();
}

enum _P { dad, mom, shared }

class _ChildSchedulePageState extends State<ChildSchedulePage> {
  late int _year;
  late int _month;
  int? _selectedDay;

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
  }

  _P _assignment(int day) {
    final date = DateTime(_year, _month, day);
    final week = ((day + DateTime(_year, _month, 1).weekday % 7) / 7).floor();
    final weekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    if (weekend && week.isEven) return _P.shared;
    return week.isEven ? _P.dad : _P.mom;
  }

  ({Color bg, Color text}) _colors(_P p) => switch (p) {
        _P.dad => (bg: AppColors.iconBgBlue, text: const Color(0xFF1E40AF)),
        _P.mom => (bg: const Color(0xFFFCE7F3), text: const Color(0xFFBE185D)),
        _P.shared => (bg: AppColors.iconBgPurple, text: AppColors.accentPurple),
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _dayHeadersRow(context),
                      const SizedBox(height: 20),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final firstWeekday = DateTime(_year, _month, 1).weekday % 7;
    final today = DateTime.now();
    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const Expanded(child: SizedBox()));
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final c = _colors(_assignment(d));
      final isToday = today.year == _year && today.month == _month && today.day == d;
      final selected = _selectedDay == d;
      cells.add(Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _selectedDay = d),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? Border.all(color: AppColors.accentPurple, width: 2)
                  : (isToday ? Border.all(color: AppColors.primaryBlue, width: 2) : null),
            ),
            child: Center(
                child: Text('$d', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.text))),
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
    Widget chip(_P p, String label) {
      final c = _colors(p);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.text))),
        ),
      );
    }
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
              chip(_P.dad, 'Dad'),
              const SizedBox(width: 8),
              chip(_P.mom, 'Mom'),
              const SizedBox(width: 8),
              chip(_P.shared, 'Shared'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayDetail(BuildContext context) {
    final palette = context.palette;
    final p = _assignment(_selectedDay!);
    final who = switch (p) { _P.dad => "Dad's day", _P.mom => "Mom's day", _P.shared => 'Shared day' };
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
        ],
      ),
    );
  }
}
