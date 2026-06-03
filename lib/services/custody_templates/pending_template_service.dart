import 'custody_template.dart';

/// One-shot result handoff between the template-flow pages and the
/// CustodySchedule editor — port of `Services/CustodyTemplates/PendingTemplateService.cs`.
///
/// Flow:
///   1. The editor (or onboarding) detects the empty state, calls [clear] then pushes
///      the template pages.
///   2. The user picks a template + answers; the config page calls [setResult] then pops.
///   3. The editor's "appeared again" path calls [tryConsume] to retrieve + clear it.
///
/// Also carries pre-built raw day lists (from the AI custom-pattern flow during
/// onboarding, where the AI returns a fully-formed day-by-day pattern that doesn't go
/// through a template) — see [setRawPattern] / [tryConsumeRawPattern].
///
/// C# guards every field with a lock; Dart runs on a single isolate so the static
/// holder is inherently safe without one.
class PendingTemplateService {
  PendingTemplateService._();

  static CustodyTemplate? _template;
  static TemplateAnswers? _answers;
  static bool _aiPathRequested = false;
  static int? _rawPatternLength;
  static List<RawPatternDay>? _rawPatternDays;

  /// When true, the template config page's Apply button creates the proposal via the
  /// API directly and dismisses (rather than just setting a result for the editor to
  /// pick up). Onboarding sets this; the regular editor flow leaves it false.
  static bool isOnboardingMode = false;

  static void clear() {
    _template = null;
    _answers = null;
    _aiPathRequested = false;
    isOnboardingMode = false;
    _rawPatternLength = null;
    _rawPatternDays = null;
  }

  /// Set when the user picks "Ask AI" on the start-choice page.
  static void requestAiPath() => _aiPathRequested = true;

  /// Atomically read + clear the AI-path request.
  static bool consumeAiPathRequest() {
    final result = _aiPathRequested;
    _aiPathRequested = false;
    return result;
  }

  static void setResult(CustodyTemplate template, TemplateAnswers answers) {
    _template = template;
    _answers = answers;
  }

  static bool get hasResult => _template != null && _answers != null;

  /// Atomically read the result and clear it. Returns null if none pending.
  static ({CustodyTemplate template, TemplateAnswers answers})? tryConsume() {
    if (_template == null || _answers == null) return null;
    final result = (template: _template!, answers: _answers!);
    _template = null;
    _answers = null;
    return result;
  }

  /// Stash a fully-formed day-by-day pattern (AI custom-pattern onboarding path).
  static void setRawPattern(int patternLengthWeeks, Iterable<RawPatternDay> days) {
    _rawPatternLength = patternLengthWeeks;
    _rawPatternDays = days.toList();
  }

  /// Atomically read + clear the pending raw pattern.
  static ({int length, List<RawPatternDay> days})? tryConsumeRawPattern() {
    if (_rawPatternLength == null || _rawPatternDays == null) return null;
    final result = (length: _rawPatternLength!, days: _rawPatternDays!);
    _rawPatternLength = null;
    _rawPatternDays = null;
    return result;
  }
}

/// Carrier shape for a single day in a pre-built pattern handed off via
/// [PendingTemplateService.setRawPattern]. Mirrors the AI's PatternDayArg.
class RawPatternDay {
  const RawPatternDay({
    required this.weekIndex,
    required this.dayIndex,
    this.parentAssignment = 'None',
    this.transferTime,
    this.transferEndTime,
    this.locationName,
    this.locationAddress,
    this.latitude,
    this.longitude,
  });

  final int weekIndex;
  final int dayIndex;
  final String parentAssignment;
  final String? transferTime;
  final String? transferEndTime;
  final String? locationName;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
}
