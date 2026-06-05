// All available custody templates — port of `Services/CustodyTemplates/Templates.cs`.
// Add new ones to [Templates.all] and they appear in the catalog automatically.
// Order matters — most common arrangements first.

import 'custody_template.dart';

class Templates {
  Templates._();

  static final List<CustodyTemplate> all = <CustodyTemplate>[
    WeekOnWeekOff(),
    Schedule223(),
    Schedule3443(),
    Schedule2255(),
    EveryOtherWeekend(),
    EveryOtherWeekendPlusWednesday(),
    Schedule52(),
    Schedule43(),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared question builders — keep wording consistent across all templates.
// ─────────────────────────────────────────────────────────────────────────────

class CommonQuestions {
  CommonQuestions._();

  static TemplateQuestion startingParent([String label = 'Who has Week 1?']) =>
      TemplateQuestion(
        id: 'starting_parent',
        label: label,
        helpText: "We'll alternate from there.",
        type: QuestionType.parentChoice,
        defaultValue: 'Husband',
        optionALabel: 'Dad',
        optionAValue: 'Husband',
        optionBLabel: 'Mom',
        optionBValue: 'Wife',
      );

  static TemplateQuestion weekdayParent() => const TemplateQuestion(
        id: 'weekday_parent',
        label: 'Who has the kids on weekdays?',
        helpText: 'Monday through Friday.',
        type: QuestionType.parentChoice,
        defaultValue: 'Wife',
        optionALabel: 'Dad',
        optionAValue: 'Husband',
        optionBLabel: 'Mom',
        optionBValue: 'Wife',
      );

  static TemplateQuestion weekendParent() => const TemplateQuestion(
        id: 'weekend_parent',
        label: 'Who is the weekend parent?',
        helpText: 'They get alternating weekends. The other parent has weekdays.',
        type: QuestionType.parentChoice,
        defaultValue: 'Husband',
        optionALabel: 'Dad',
        optionAValue: 'Husband',
        optionBLabel: 'Mom',
        optionBValue: 'Wife',
      );

  static TemplateQuestion changeoverDay() => const TemplateQuestion(
        id: 'changeover_day',
        label: 'Which day do you switch?',
        helpText: 'The day the kids move from one parent to the other each cycle.',
        type: QuestionType.dayOfWeek,
        defaultValue: '0', // 0 = Sunday
      );

  static TemplateQuestion handoffTime({
    String id = 'handoff_time',
    String label = 'Handoff time',
    String defaultTime = '17:00',
  }) =>
      TemplateQuestion(
        id: id,
        label: label,
        helpText: 'When the kids switch from one parent to the other.',
        type: QuestionType.timeOfDay,
        defaultValue: defaultTime,
      );
}

/// The "other" parent.
String _other(String parent) => switch (parent) {
      'Husband' => 'Wife',
      'Wife' => 'Husband',
      _ => parent,
    };

// ─────────────────────────────────────────────────────────────────────────────
// Pattern construction from a "nights" array.
//
// CANONICAL MEANING (matches the MANUAL builder, the renderer, and how real-world
// custody is counted — by overnights):
//   parentAssignment[day] = the parent who has the child that day / that overnight.
//   transferTime          = the handoff time on a changeover day (when that parent
//                           took over from the day before).
//
// The array declares who the child is with each day; a transfer is marked only when
// that changes from the previous day. (Previously the day was coloured by the
// PREVIOUS night, which shifted every template one day off from its own question and
// from the manual editor — e.g. "Mom has Mon-Tue" painted Tue-Wed.)
// ─────────────────────────────────────────────────────────────────────────────

class PatternHelpers {
  PatternHelpers._();

  /// [nights][i] = the parent who has the child on day i (length = weeks×7).
  /// Index 0 = Week 0 Sunday, 1 = Mon, ... 6 = Sat, 7 = Week 1 Sunday, etc.
  ///
  /// [timeForTransferDay] returns the handoff time ("HH:mm") for a changeover-day
  /// index; only consulted on transfer days.
  static List<GeneratedDay> fromNights(
      List<String> nights, String Function(int) timeForTransferDay) {
    final n = nights.length;
    final days = <GeneratedDay>[];
    for (int d = 0; d < n; d++) {
      final dayParent = nights[d]; // who has this day / overnight
      final prevDay = nights[(d - 1 + n) % n]; // the day before (wraps the cycle)

      // A real handoff happens only when the parent changes from the day before.
      final isTransfer = prevDay != dayParent && prevDay != 'None' && dayParent != 'None';

      days.add(GeneratedDay(
        weekIndex: d ~/ 7,
        dayIndex: d % 7,
        parentAssignment: dayParent,
        transferTime: isTransfer ? timeForTransferDay(d) : null,
      ));
    }
    return days;
  }

  /// Adds whole hours to an "HH:mm" string, clamped to the same day.
  static String addHours(String hhmm, double hours) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return hhmm;
    var total = (h * 60 + m) + (hours * 60).round();
    const maxMinutes = 23 * 60 + 59; // 23.99h ≈ 23:59
    if (total > maxMinutes) total = maxMinutes;
    if (total < 0) total = 0;
    final hh = (total ~/ 60).toString().padLeft(2, '0');
    final mm = (total % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Week on / Week off — 2 weeks, 50/50
// ─────────────────────────────────────────────────────────────────────────────

class WeekOnWeekOff extends CustodyTemplate {
  @override
  String get id => 'week-on-week-off';
  @override
  String get name => 'Week on / Week off';
  @override
  String get shortDescription =>
      'Each parent has the kids for a full week, then switches.';
  @override
  String get category => '50/50';
  @override
  int get patternLengthWeeks => 2;

  @override
  List<TemplateQuestion> get questions => [
        CommonQuestions.startingParent('Who has the kids first?'),
        CommonQuestions.changeoverDay(),
        CommonQuestions.handoffTime(label: 'Handoff time'),
      ];

  @override
  List<GeneratedDay> buildPattern(TemplateAnswers a) {
    final p1 = a.getOrDefault('starting_parent', 'Husband');
    final p2 = _other(p1);
    final t = a.getOrDefault('handoff_time', '17:00');
    var c = int.tryParse(a.getOrDefault('changeover_day', '0')) ?? 0;
    if (c < 0 || c > 6) c = 0;

    // p1 sleeps the 7 nights beginning on the chosen changeover day; p2 the next 7.
    final nights = List<String>.filled(14, '');
    for (int d = 0; d < 14; d++) {
      final offset = (d - c + 14) % 14; // nights since most recent changeover
      nights[d] = offset < 7 ? p1 : p2;
    }
    return PatternHelpers.fromNights(nights, (_) => t);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. 2-2-3 schedule — 2 weeks, 50/50
// ─────────────────────────────────────────────────────────────────────────────

class Schedule223 extends CustodyTemplate {
  @override
  String get id => 'schedule-2-2-3';
  @override
  String get name => '2-2-3 schedule';
  @override
  String get shortDescription => 'Switch every 2-3 days, alternating weekends.';
  @override
  String get category => '50/50';
  @override
  int get patternLengthWeeks => 2;

  @override
  List<TemplateQuestion> get questions => [
        CommonQuestions.startingParent('Who has Mon-Tue of Week 1?'),
        CommonQuestions.handoffTime(),
      ];

  @override
  List<GeneratedDay> buildPattern(TemplateAnswers a) {
    final p1 = a.getOrDefault('starting_parent', 'Husband');
    final p2 = _other(p1);
    final t = a.getOrDefault('handoff_time', '17:00');

    final nights = <String>[
      //  Sun  Mon  Tue  Wed  Thu  Fri  Sat
      p2, p1, p1, p2, p2, p1, p1, // Week 0
      p1, p2, p2, p1, p1, p2, p2, // Week 1
    ];
    return PatternHelpers.fromNights(nights, (_) => t);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. 3-4-4-3 schedule — 2 weeks, 50/50
// ─────────────────────────────────────────────────────────────────────────────

class Schedule3443 extends CustodyTemplate {
  @override
  String get id => 'schedule-3-4-4-3';
  @override
  String get name => '3-4-4-3 schedule';
  @override
  String get shortDescription =>
      'Longer stretches than 2-2-3 — easier on younger kids.';
  @override
  String get category => '50/50';
  @override
  int get patternLengthWeeks => 2;

  @override
  List<TemplateQuestion> get questions => [
        CommonQuestions.startingParent('Who has Sun-Tue of Week 1?'),
        CommonQuestions.handoffTime(),
      ];

  @override
  List<GeneratedDay> buildPattern(TemplateAnswers a) {
    final p1 = a.getOrDefault('starting_parent', 'Husband');
    final p2 = _other(p1);
    final t = a.getOrDefault('handoff_time', '17:00');

    final nights = <String>[
      //  Sun  Mon  Tue  Wed  Thu  Fri  Sat
      p1, p1, p1, p2, p2, p2, p2, // Week 0:  p1×3, p2×4
      p1, p1, p1, p1, p2, p2, p2, // Week 1:  p1×4, p2×3
    ];
    return PatternHelpers.fromNights(nights, (_) => t);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. 2-2-5-5 schedule — 2 weeks, 50/50, predictable weekdays
// ─────────────────────────────────────────────────────────────────────────────

class Schedule2255 extends CustodyTemplate {
  @override
  String get id => 'schedule-2-2-5-5';
  @override
  String get name => '2-2-5-5 schedule';
  @override
  String get shortDescription =>
      'Same weekdays every week, weekends alternate. Great consistency for school.';
  @override
  String get category => '50/50';
  @override
  int get patternLengthWeeks => 2;

  @override
  List<TemplateQuestion> get questions => [
        const TemplateQuestion(
          id: 'mon_tue_parent',
          label: 'Who has Monday-Tuesday every week?',
          helpText:
              'The other parent gets Wednesday-Thursday every week. Weekends alternate.',
          type: QuestionType.parentChoice,
          defaultValue: 'Husband',
          optionALabel: 'Dad',
          optionAValue: 'Husband',
          optionBLabel: 'Mom',
          optionBValue: 'Wife',
        ),
        const TemplateQuestion(
          id: 'first_weekend_parent',
          label: 'Who has the first weekend (Fri-Sun)?',
          type: QuestionType.parentChoice,
          defaultValue: 'Husband',
          optionALabel: 'Dad',
          optionAValue: 'Husband',
          optionBLabel: 'Mom',
          optionBValue: 'Wife',
        ),
        CommonQuestions.handoffTime(),
      ];

  @override
  List<GeneratedDay> buildPattern(TemplateAnswers a) {
    final monTue = a.getOrDefault('mon_tue_parent', 'Husband');
    final wedThu = _other(monTue);
    final firstWeekend = a.getOrDefault('first_weekend_parent', 'Husband');
    final secondWeekend = _other(firstWeekend);
    final t = a.getOrDefault('handoff_time', '17:00');

    final nights = <String>[
      //  Sun           Mon     Tue     Wed     Thu     Fri            Sat
      secondWeekend, monTue, monTue, wedThu, wedThu, firstWeekend, firstWeekend, // Week 0
      firstWeekend, monTue, monTue, wedThu, wedThu, secondWeekend, secondWeekend, // Week 1
    ];
    return PatternHelpers.fromNights(nights, (_) => t);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Every other weekend — 2 weeks, primary custody
// ─────────────────────────────────────────────────────────────────────────────

class EveryOtherWeekend extends CustodyTemplate {
  @override
  String get id => 'every-other-weekend';
  @override
  String get name => 'Every other weekend';
  @override
  String get shortDescription =>
      'One parent weekdays, other gets every other Fri-Sun.';
  @override
  String get category => 'Primary custody';
  @override
  int get patternLengthWeeks => 2;

  @override
  List<TemplateQuestion> get questions => [
        CommonQuestions.weekendParent(),
        CommonQuestions.handoffTime(
            id: 'friday_handoff_time', label: 'Friday pickup time', defaultTime: '17:00'),
        CommonQuestions.handoffTime(
            id: 'sunday_handoff_time', label: 'Sunday return time', defaultTime: '18:00'),
      ];

  @override
  List<GeneratedDay> buildPattern(TemplateAnswers a) {
    final weekendParent = a.getOrDefault('weekend_parent', 'Husband');
    final weekdayParent = _other(weekendParent);
    final friT = a.getOrDefault('friday_handoff_time', '17:00');
    final sunT = a.getOrDefault('sunday_handoff_time', '18:00');

    final nights = <String>[
      //  Sun           Mon            Tue            Wed            Thu            Fri            Sat
      weekdayParent, weekdayParent, weekdayParent, weekdayParent, weekdayParent, weekendParent, weekendParent, // Week 0
      weekdayParent, weekdayParent, weekdayParent, weekdayParent, weekdayParent, weekdayParent, weekdayParent, // Week 1
    ];
    return PatternHelpers.fromNights(nights, (d) => switch (d) {
          5 => friT,
          7 => sunT,
          _ => friT,
        });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Every other weekend + Wednesday — 2 weeks, primary custody + midweek visit
// ─────────────────────────────────────────────────────────────────────────────

class EveryOtherWeekendPlusWednesday extends CustodyTemplate {
  @override
  String get id => 'every-other-weekend-wed';
  @override
  String get name => 'Every other weekend + Wednesday';
  @override
  String get shortDescription =>
      'Like every-other-weekend, plus a midweek evening with the other parent.';
  @override
  String get category => 'Primary custody';
  @override
  int get patternLengthWeeks => 2;

  @override
  List<TemplateQuestion> get questions => [
        CommonQuestions.weekendParent(),
        CommonQuestions.handoffTime(
            id: 'friday_handoff_time', label: 'Friday pickup time', defaultTime: '17:00'),
        CommonQuestions.handoffTime(
            id: 'sunday_handoff_time', label: 'Sunday return time', defaultTime: '18:00'),
        CommonQuestions.handoffTime(
            id: 'wed_handoff_time', label: 'Wednesday visit start', defaultTime: '17:00'),
      ];

  @override
  List<GeneratedDay> buildPattern(TemplateAnswers a) {
    final weekendParent = a.getOrDefault('weekend_parent', 'Husband');
    final weekdayParent = _other(weekendParent);
    final friT = a.getOrDefault('friday_handoff_time', '17:00');
    final sunT = a.getOrDefault('sunday_handoff_time', '18:00');
    final wedT = a.getOrDefault('wed_handoff_time', '17:00');
    final wedEnd = PatternHelpers.addHours(wedT, 3); // 3-hour dinner window

    final nights = <String>[
      weekdayParent, weekdayParent, weekdayParent, weekdayParent, weekdayParent, weekendParent, weekendParent, // Week 0
      weekdayParent, weekdayParent, weekdayParent, weekdayParent, weekdayParent, weekdayParent, weekdayParent, // Week 1
    ];
    final days = PatternHelpers.fromNights(nights, (d) => switch (d) {
          5 => friT, // Fri0 pickup
          7 => sunT, // Sun1 return
          _ => friT,
        });

    // Wednesday dinner visit each week: a within-day window (no overnight change).
    days[3] = GeneratedDay(
      weekIndex: 0,
      dayIndex: 3,
      parentAssignment: weekdayParent,
      transferTime: wedT,
      transferEndTime: wedEnd,
    );
    days[10] = GeneratedDay(
      weekIndex: 1,
      dayIndex: 3,
      parentAssignment: weekdayParent,
      transferTime: wedT,
      transferEndTime: wedEnd,
    );
    return days;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. 5-2 schedule — 1 week
// ─────────────────────────────────────────────────────────────────────────────

class Schedule52 extends CustodyTemplate {
  @override
  String get id => 'schedule-5-2';
  @override
  String get name => '5-2 schedule';
  @override
  String get shortDescription =>
      'One parent has weekdays, the other has weekends. Same every week.';
  @override
  String get category => 'Predictable';
  @override
  int get patternLengthWeeks => 1;

  @override
  List<TemplateQuestion> get questions => [
        CommonQuestions.weekdayParent(),
        CommonQuestions.handoffTime(
            id: 'friday_handoff_time', label: 'Friday handoff time', defaultTime: '17:00'),
        CommonQuestions.handoffTime(
            id: 'sunday_handoff_time', label: 'Sunday handoff time', defaultTime: '18:00'),
      ];

  @override
  List<GeneratedDay> buildPattern(TemplateAnswers a) {
    final weekday = a.getOrDefault('weekday_parent', 'Wife');
    final weekend = _other(weekday);
    final friT = a.getOrDefault('friday_handoff_time', '17:00');
    final sunT = a.getOrDefault('sunday_handoff_time', '18:00');

    final nights = <String>[
      //  Sun      Mon      Tue      Wed      Thu      Fri      Sat
      weekday, weekday, weekday, weekday, weekday, weekend, weekend,
    ];
    return PatternHelpers.fromNights(nights, (d) => switch (d) {
          5 => friT,
          0 => sunT,
          _ => friT,
        });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. 4-3 schedule — 1 week
// ─────────────────────────────────────────────────────────────────────────────

class Schedule43 extends CustodyTemplate {
  @override
  String get id => 'schedule-4-3';
  @override
  String get name => '4-3 schedule';
  @override
  String get shortDescription =>
      'One parent has Sun-Wed (4 days), the other has Thu-Sat (3 days). Same every week.';
  @override
  String get category => 'Predictable';
  @override
  int get patternLengthWeeks => 1;

  @override
  List<TemplateQuestion> get questions => [
        const TemplateQuestion(
          id: 'four_day_parent',
          label: 'Who has the 4 days (Sun-Wed)?',
          helpText: 'The other parent gets Thursday through Saturday.',
          type: QuestionType.parentChoice,
          defaultValue: 'Wife',
          optionALabel: 'Dad',
          optionAValue: 'Husband',
          optionBLabel: 'Mom',
          optionBValue: 'Wife',
        ),
        CommonQuestions.handoffTime(
            id: 'thu_handoff_time', label: 'Thursday handoff time', defaultTime: '17:00'),
        CommonQuestions.handoffTime(
            id: 'sun_handoff_time', label: 'Sunday handoff time', defaultTime: '18:00'),
      ];

  @override
  List<GeneratedDay> buildPattern(TemplateAnswers a) {
    final fourDay = a.getOrDefault('four_day_parent', 'Wife');
    final threeDay = _other(fourDay);
    final thuT = a.getOrDefault('thu_handoff_time', '17:00');
    final sunT = a.getOrDefault('sun_handoff_time', '18:00');

    final nights = <String>[
      //  Sun      Mon      Tue      Wed      Thu       Fri       Sat
      fourDay, fourDay, fourDay, fourDay, threeDay, threeDay, threeDay,
    ];
    return PatternHelpers.fromNights(nights, (d) => switch (d) {
          0 => sunT,
          4 => thuT,
          _ => thuT,
        });
  }
}
