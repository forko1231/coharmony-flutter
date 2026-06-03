import 'package:flutter/material.dart';

import '../../models/custody_models.dart';
import '../../theme/app_palette.dart';

/// Read-only week-grid preview of a custody proposal's repeating pattern, used on
/// the onboarding review + sent screens. Renders [patternLength] week rows of
/// seven day cells, coloured by parent assignment with a transfer-time gradient
/// (matching the schedule editor / dashboard). Pure presentation — no state.
class ProposalPreviewGrid extends StatelessWidget {
  const ProposalPreviewGrid({super.key, required this.patternLength, required this.days});

  final int patternLength;
  final List<ProposalDayDto> days;

  // Light custody tints (match the onboarding legend).
  static const _dad = Color(0xFFBFDBFE);
  static const _mom = Color(0xFFFCE7F3);
  static const _both = Color(0xFFE9D5FF);
  static const _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  static Color? _solid(String parent) => switch (parent.toLowerCase()) {
        'husband' => _dad,
        'wife' => _mom,
        'both' => _both,
        _ => null,
      };

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

  ProposalDayDto? _dayFor(int week, int dow) {
    for (final d in days) {
      if (d.weekIndex == week && d.dayIndex == dow) return d;
    }
    return null;
  }

  BoxDecoration _decoration(BuildContext context, ProposalDayDto? day) {
    final palette = context.palette;
    final base = day == null ? null : _solid(day.parentAssignment);
    final radius = BorderRadius.circular(6);
    if (base == null) {
      return BoxDecoration(color: palette.surfaceInput, borderRadius: radius);
    }
    final parent = day!.parentAssignment.toLowerCase();
    final start = _parseTod(day.transferTime);
    final end = _parseTod(day.transferEndTime);
    if (start != null && parent != 'both') {
      final startP = ((start.hour * 60 + start.minute) / 1440).clamp(0.0, 1.0);
      final to = parent == 'husband' ? _mom : _dad;
      if (end != null && (end.hour * 60 + end.minute) > (start.hour * 60 + start.minute)) {
        final endP = ((end.hour * 60 + end.minute) / 1440).clamp(0.0, 1.0);
        return BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [base, base, to, to, base, base],
            stops: _stops([0, startP - 0.001, startP, endP, endP + 0.001, 1]),
          ),
        );
      }
      return BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [base, base, to, to],
          stops: _stops([0, startP - 0.001, startP, 1]),
        ),
      );
    }
    return BoxDecoration(color: base, borderRadius: radius);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final weeks = patternLength < 1 ? 1 : patternLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final l in _dayLabels)
              Expanded(
                child: Center(
                  child: Text(l,
                      style: TextStyle(
                          fontSize: 11, height: 1.0, fontWeight: FontWeight.bold, color: palette.textSecondary)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (int w = 0; w < weeks; w++) ...[
          if (weeks > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text('Week ${w + 1}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: palette.textSecondary)),
            ),
          Row(
            children: [
              for (int d = 0; d < 7; d++) ...[
                Expanded(
                  child: Container(
                    height: 34,
                    decoration: _decoration(context, _dayFor(w, d)),
                  ),
                ),
                if (d < 6) const SizedBox(width: 4),
              ],
            ],
          ),
          if (w < weeks - 1) const SizedBox(height: 4),
        ],
      ],
    );
  }
}
