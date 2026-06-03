// Core template types — port of `Services/CustodyTemplates/CustodyTemplate.cs`.
//
// A pre-built custody pattern users can pick from instead of configuring 28 cells by
// hand. Each template knows its pattern length, the questions it needs answered, and how
// to turn those answers into a list of day assignments the schedule editor can apply.

abstract class CustodyTemplate {
  /// Stable identifier — used by the AI tool, analytics, and registry lookups.
  String get id;

  /// Display name in the catalog (e.g. "Week on / Week off").
  String get name;

  /// One-line description for the catalog card.
  String get shortDescription;

  /// Category label shown on the card chip ("50/50", "Primary custody", etc.).
  String get category;

  /// Pattern length in weeks (1, 2, 3, 4, 6, or 8).
  int get patternLengthWeeks;

  /// The questions to ask before generating the pattern. Order matters.
  List<TemplateQuestion> get questions;

  /// Build the full day pattern from the user's answers — one entry per
  /// (week, day), i.e. [patternLengthWeeks] * 7 entries.
  List<GeneratedDay> buildPattern(TemplateAnswers answers);
}

enum QuestionType {
  /// Two-button choice (Dad/Mom). Answer is the "value" string ("Husband"/"Wife").
  parentChoice,

  /// 24-hour time string in HH:mm format (e.g. "17:00").
  timeOfDay,

  /// Day of week 0=Sunday..6=Saturday, stored as int.toString().
  dayOfWeek,
}

/// One question the template needs answered before it can build the pattern.
class TemplateQuestion {
  const TemplateQuestion({
    required this.id,
    required this.label,
    required this.type,
    this.helpText,
    this.defaultValue,
    this.optionALabel,
    this.optionBLabel,
    this.optionAValue,
    this.optionBValue,
  });

  final String id;
  final String label;
  final String? helpText;
  final QuestionType type;
  final String? defaultValue;

  /// For [QuestionType.parentChoice]: the two labels (default "Dad" and "Mom").
  final String? optionALabel;
  final String? optionBLabel;

  /// Internal model values that map to the labels (default "Husband" and "Wife").
  final String? optionAValue;
  final String? optionBValue;
}

/// User's answers to the template's questions, keyed by question id. Values are
/// always strings — convert as needed when consuming.
class TemplateAnswers {
  final Map<String, String> _values = {};

  String operator [](String questionId) => _values[questionId] ?? '';
  void operator []=(String questionId, String value) => _values[questionId] = value;

  bool has(String questionId) =>
      _values.containsKey(questionId) && (_values[questionId]?.isNotEmpty ?? false);

  String getOrDefault(String questionId, String fallback) {
    final v = _values[questionId];
    return (v != null && v.isNotEmpty) ? v : fallback;
  }

  int getIntOrDefault(String questionId, int fallback) {
    final v = _values[questionId];
    if (v == null) return fallback;
    return int.tryParse(v) ?? fallback;
  }

  Iterable<MapEntry<String, String>> get all => _values.entries;
}

/// One day in the generated pattern. The schedule editor converts these into
/// `UpdateDayRequest` objects when applying the template.
class GeneratedDay {
  const GeneratedDay({
    required this.weekIndex,
    required this.dayIndex,
    required this.parentAssignment, // "Husband" | "Wife" | "Both" | "None"
    this.transferTime, // "HH:mm" — only on changeover days
    this.transferEndTime, // optional window end
  });

  final int weekIndex;
  final int dayIndex;
  final String parentAssignment;
  final String? transferTime;
  final String? transferEndTime;
}
