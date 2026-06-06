import 'package:flutter/material.dart';
import '../../../services/custody_templates/custody_template.dart';
import '../../../services/custody_templates/pending_template_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../widgets/app_header.dart';
import '../twelve_hour_time_picker.dart';

/// Template configuration — port of `TemplateConfigPage.xaml(.cs)`. Renders the chosen
/// template's questions and a LIVE 4-week preview that updates on every answer change.
/// On Apply: in onboarding mode it creates + submits the proposal and advances the
/// router; otherwise it stashes the result in [PendingTemplateService] and pops so the
/// editor picks it up on its next appearance.
class TemplateConfigPage extends StatefulWidget {
  const TemplateConfigPage({super.key, required this.template, this.presetAnswers});

  final CustodyTemplate template;
  final Map<String, String>? presetAnswers;

  @override
  State<TemplateConfigPage> createState() => _TemplateConfigPageState();
}

class _TemplateConfigPageState extends State<TemplateConfigPage> {
  final TemplateAnswers _answers = TemplateAnswers();
  final bool _busy = false; // apply is instant now (no proposal call); overlay kept inert

  // Preview colors mirror the editor legend.
  static const _dadBg = Color(0xFFBFDBFE);
  static const _dadFg = Color(0xFF1E40AF);
  static const _momBg = Color(0xFFFCE7F3);
  static const _momFg = Color(0xFFBE185D);
  static const _bothBg = Color(0xFFE9D5FF);
  static const _bothFg = Color(0xFF6B21A8);
  static const _noneBg = Color(0xFFF3F4F6);
  static const _noneFg = Color(0xFF9CA3AF);
  static const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    final preset = widget.presetAnswers;
    if (preset != null) {
      preset.forEach((k, v) {
        if (v.isNotEmpty) _answers[k] = v;
      });
    }
    for (final q in widget.template.questions) {
      if (!_answers.has(q.id) && (q.defaultValue?.isNotEmpty ?? false)) {
        _answers[q.id] = q.defaultValue!;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final t = widget.template;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Column(
            children: [
              AppHeader(
                title: t.name,
                subtitle: t.patternLengthWeeks == 1 ? '1-week pattern' : '${t.patternLengthWeeks}-week pattern',
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final q in t.questions) ...[
                            _questionCard(context, q),
                            const SizedBox(height: 12),
                          ],
                          _previewCard(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _actionBar(context),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Sending your schedule...', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Question cards ─────────────────────────────────────────────────────────────
  Widget _questionCard(BuildContext context, TemplateQuestion q) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.06),
              offset: const Offset(0, 4),
              blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          if (q.helpText?.isNotEmpty ?? false) ...[
            const SizedBox(height: 4),
            Text(q.helpText!, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
          ],
          const SizedBox(height: 12),
          switch (q.type) {
            QuestionType.parentChoice => _parentChoice(context, q),
            QuestionType.timeOfDay => _timePicker(context, q),
            QuestionType.dayOfWeek => _dayOfWeekChoice(context, q),
          },
        ],
      ),
    );
  }

  Widget _parentChoice(BuildContext context, TemplateQuestion q) {
    final aLabel = q.optionALabel ?? 'Dad';
    final bLabel = q.optionBLabel ?? 'Mom';
    final aValue = q.optionAValue ?? 'Husband';
    final bValue = q.optionBValue ?? 'Wife';
    return Row(
      children: [
        Expanded(child: _choiceBtn(context, aLabel, _answers.getOrDefault(q.id, '') == aValue, () {
          setState(() => _answers[q.id] = aValue);
        })),
        const SizedBox(width: 10),
        Expanded(child: _choiceBtn(context, bLabel, _answers.getOrDefault(q.id, '') == bValue, () {
          setState(() => _answers[q.id] = bValue);
        })),
      ],
    );
  }

  Widget _choiceBtn(BuildContext context, String label, bool selected, VoidCallback onTap) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : palette.surfaceInput,
          border: selected ? null : Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: selected ? Colors.white : palette.textPrimary)),
      ),
    );
  }

  Widget _timePicker(BuildContext context, TemplateQuestion q) {
    final current = _answers.getOrDefault(q.id, q.defaultValue ?? '17:00');
    final parts = current.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 17;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF374151) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TwelveHourTimePicker(
        value: TimeOfDay(hour: h, minute: m),
        onChanged: (t) {
          setState(() => _answers[q.id] =
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
        },
      ),
    );
  }

  Widget _dayOfWeekChoice(BuildContext context, TemplateQuestion q) {
    final palette = context.palette;
    final selected = _answers.getOrDefault(q.id, q.defaultValue ?? '0');
    return Row(
      children: [
        for (int i = 0; i < 7; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _answers[q.id] = i.toString()),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected == i.toString() ? AppColors.primaryBlue : palette.surfaceInput,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_dayNames[i].substring(0, 1),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: selected == i.toString() ? Colors.white : palette.textPrimary)),
              ),
            ),
          ),
          if (i < 6) const SizedBox(width: 4),
        ],
      ],
    );
  }

  // ── Live preview ─────────────────────────────────────────────────────────────
  Widget _previewCard(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
              offset: const Offset(0, 4),
              blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preview',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          const SizedBox(height: 2),
          Text('Your next 4 weeks with these settings',
              style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          const SizedBox(height: 12),
          ..._previewWeeks(),
        ],
      ),
    );
  }

  List<Widget> _previewWeeks() {
    final t = widget.template;
    List<GeneratedDay> days;
    try {
      days = t.buildPattern(_answers);
    } catch (_) {
      return [
        const Text('Answer the questions above to see your schedule.',
            style: TextStyle(fontSize: 13, color: _noneFg)),
      ];
    }

    final weeksToShow = 4 > t.patternLengthWeeks * 2 ? 4 : t.patternLengthWeeks * 2;
    final today = DateTime.now();
    final daysSinceSunday = today.weekday % 7; // Mon=1..Sun=7 → Sun=0
    final weekStart = DateTime(today.year, today.month, today.day).subtract(Duration(days: daysSinceSunday));

    final out = <Widget>[];
    for (int weekOffset = 0; weekOffset < weeksToShow; weekOffset++) {
      final patternWeek = weekOffset % t.patternLengthWeeks;
      final weekStartDate = weekStart.add(Duration(days: weekOffset * 7));
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Week of ${_monthAbbr[weekStartDate.month - 1]} ${weekStartDate.day}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _noneFg)),
            const SizedBox(height: 4),
            Row(
              children: [
                for (int d = 0; d < 7; d++) ...[
                  _previewDay(days, patternWeek, d, weekStartDate.add(Duration(days: d))),
                  if (d < 6) const SizedBox(width: 3),
                ],
              ],
            ),
          ],
        ),
      ));
    }
    return out;
  }

  Widget _previewDay(List<GeneratedDay> days, int patternWeek, int d, DateTime date) {
    GeneratedDay? assignment;
    for (final x in days) {
      if (x.weekIndex == patternWeek && x.dayIndex == d) {
        assignment = x;
        break;
      }
    }
    final name = assignment?.parentAssignment ?? 'None';
    final (bg, fg) = _colorsFor(name);

    final start = _parseTod(assignment?.transferTime);
    final end = _parseTod(assignment?.transferEndTime);
    Gradient? gradient;
    if (start != null) {
      final startP = ((start.hour * 60 + start.minute) / (24 * 60)).clamp(0.0, 1.0);
      final other = _otherParentColor(name);
      if (end != null && (end.hour * 60 + end.minute) > (start.hour * 60 + start.minute)) {
        final endP = ((end.hour * 60 + end.minute) / (24 * 60)).clamp(0.0, 1.0);
        gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg, bg, other, other, bg, bg],
          stops: _stops([0, startP - 0.001, startP, endP, endP + 0.001, 1]),
        );
      } else {
        gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg, bg, other, other],
          stops: _stops([0, startP - 0.001, startP, 1]),
        );
      }
    }

    return Expanded(
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: gradient == null ? bg : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_dayNames[d].substring(0, 1), style: TextStyle(fontSize: 9, color: fg)),
            Text('${date.day}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
          ],
        ),
      ),
    );
  }

  // ── Action bar ─────────────────────────────────────────────────────────────────
  Widget _actionBar(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      color: palette.surfaceElevated,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.textSecondary,
                side: BorderSide(color: palette.border, width: 2),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Cancel', style: TextStyle(fontSize: 15)),
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
              onPressed: _apply,
              child: const Text('Apply Template', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _apply() async {
    // Validate by trying to build — surfaces missing answers.
    try {
      widget.template.buildPattern(_answers);
    } catch (ex) {
      await _alert('Missing info', 'Please answer all questions before applying. ($ex)');
      return;
    }

    // Stash the chosen template + answers; whoever opened this (the live editor, or
    // onboarding's live editor) picks it up on return via PendingTemplateService and
    // applies it under the schedule lock. No proposals.
    PendingTemplateService.setResult(widget.template, _answers);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _alert(String title, String message) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );

  static (Color, Color) _colorsFor(String a) => switch (a) {
        'Husband' => (_dadBg, _dadFg),
        'Wife' => (_momBg, _momFg),
        'Both' => (_bothBg, _bothFg),
        _ => (_noneBg, _noneFg),
      };

  static Color _otherParentColor(String a) => switch (a) {
        'Husband' => _momBg,
        'Wife' => _dadBg,
        _ => _noneBg,
      };

  static TimeOfDay? _parseTod(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
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
}
