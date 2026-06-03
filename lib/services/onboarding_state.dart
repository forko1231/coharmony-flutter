import 'preferences.dart';

/// Port of `Services/OnboardingState.cs`. Tracks post-signup onboarding progress,
/// backed by [Preferences]. Completion is scoped per-email so a new account on the
/// same device does not inherit a previous user's completion.
///
/// NOTE: reads the current user's email from the `email` preference (the auth/routing
/// layer sets it after login, matching MAUI). Account type lives in `AccountType`.
class OnboardingState {
  OnboardingState._();

  static const _keyCompleted = 'onboarding.completed';
  static const _keyCompletedForEmail = 'onboarding.completed_for_email';
  static const _keyStarted = 'onboarding.started_at';
  static const _keySchedulePromptShown =
      'onboarding.schedule_prompt_shown_after_partner_joined';
  static const _keyRole = 'onboarding.role';
  static const _keyTourSeen = 'onboarding.tour_seen';
  static const _keyScheduleAcknowledged = 'onboarding.schedule_acknowledged';

  static const _keySchemaVersion = 'onboarding.schema_version';
  static const _currentSchemaVersion = 3; // v3 = post-auth router refactor

  /// Call once on startup. Wipes completion if the stored schema is older than the
  /// current version so a changed flow re-runs. Idempotent.
  static void ensureSchemaUpToDate() {
    final stored = Preferences.getInt(_keySchemaVersion, 0);
    if (stored >= _currentSchemaVersion) return;
    Preferences.remove(_keyCompleted);
    Preferences.remove(_keyCompletedForEmail);
    Preferences.remove(_keyStarted);
    Preferences.remove(_keySchedulePromptShown);
    Preferences.setInt(_keySchemaVersion, _currentSchemaVersion);
  }

  /// True only when onboarding was completed for the email currently signed in.
  static bool get isCompleted {
    if (!Preferences.getBool(_keyCompleted, false)) return false;
    final currentEmail = Preferences.getString('email', '').trim();
    if (currentEmail.isEmpty) return false;
    final completedFor = Preferences.getString(_keyCompletedForEmail, '').trim();
    if (completedFor.isEmpty) return false;
    return completedFor.toLowerCase() == currentEmail.toLowerCase();
  }

  static bool get schedulePromptShownAfterPartnerJoined =>
      Preferences.getBool(_scopedKey(_keySchedulePromptShown), false);
  static set schedulePromptShownAfterPartnerJoined(bool v) =>
      Preferences.setBool(_scopedKey(_keySchedulePromptShown), v);

  /// "parent" | "child" | "" (empty = not yet chosen).
  static String get role => Preferences.getString(_scopedKey(_keyRole), '');
  static set role(String v) => Preferences.setString(_scopedKey(_keyRole), v);

  static bool get tourSeen => Preferences.getBool(_scopedKey(_keyTourSeen), false);
  static set tourSeen(bool v) => Preferences.setBool(_scopedKey(_keyTourSeen), v);

  static bool get scheduleAcknowledged =>
      Preferences.getBool(_scopedKey(_keyScheduleAcknowledged), false);
  static set scheduleAcknowledged(bool v) =>
      Preferences.setBool(_scopedKey(_keyScheduleAcknowledged), v);

  static void markStarted() {
    if (Preferences.getString(_keyStarted, '').isEmpty) {
      Preferences.setString(_keyStarted, DateTime.now().toUtc().toIso8601String());
    }
  }

  static void markCompleted() {
    final currentEmail = Preferences.getString('email', '').trim();
    Preferences.setString(_keyCompletedForEmail, currentEmail);
    Preferences.setBool(_keyCompleted, true);
  }

  /// Clears onboarding state for a freshly created account so it re-onboards. The
  /// global completion record is only cleared when it belongs to [email].
  static void reset([String? email]) {
    final target = (email ?? Preferences.getString('email', '')).trim();
    final completedFor = Preferences.getString(_keyCompletedForEmail, '').trim();
    if (target.isEmpty || completedFor.toLowerCase() == target.toLowerCase()) {
      Preferences.remove(_keyCompleted);
      Preferences.remove(_keyCompletedForEmail);
      Preferences.remove(_keyStarted);
    }
    Preferences.remove(_scopedKey(_keySchedulePromptShown, target));
    Preferences.remove(_scopedKey(_keyRole, target));
    Preferences.remove(_scopedKey(_keyTourSeen, target));
    Preferences.remove(_scopedKey(_keyScheduleAcknowledged, target));
    Preferences.remove(_keySchedulePromptShown);
  }

  static String _scopedKey(String baseKey, [String? email]) {
    final e = (email ?? Preferences.getString('email', '')).trim();
    return e.isEmpty ? baseKey : '$baseKey::${e.toLowerCase()}';
  }
}
