import 'preferences.dart';

/// Port of `Services/AnalyticsService.cs`. Reports user-funnel conversion events.
///
/// In MAUI these go to Sentry as tagged messages; here the sink is pluggable so
/// the phase-3 telemetry layer (`sentry_flutter`) can wire [reporter] without
/// touching call sites. No-op until a reporter is set (matches the C# "no-op
/// when Sentry not configured"). `*Once` events dedupe via [Preferences], so
/// they survive restarts but reset on reinstall.
class AnalyticsService {
  AnalyticsService._();

  /// Phase-3 hook: `(conversionName, tags) => SentrySdk.captureMessage(...)`.
  static void Function(String conversionName, Map<String, String> tags)? reporter;

  static void trackSignupCompleted() => _trackOnce('signup_completed');
  static void trackCoParentInvited() => _track('coparent_invited');
  static void trackChildInvited() => _track('child_invited');
  static void trackCoParentJoined() => _track('coparent_joined');
  static void trackChildJoined() => _track('child_joined');
  static void trackFirstScheduleCreated() => _trackOnce('first_schedule_created');
  static void trackFirstMessageSent() => _trackOnce('first_message_sent');

  static void trackSubscriptionPurchased(String tier) =>
      _track('subscription_purchased', {'subscription_tier': tier});

  /// Generic conversion event — prefer the named methods to keep the taxonomy
  /// consistent.
  static void trackCustom(String eventName, {Map<String, String>? extraTags}) =>
      _track(eventName, extraTags ?? const {});

  static void _track(String conversionName, [Map<String, String> extraTags = const {}]) {
    final r = reporter;
    if (r == null) return; // no-op when telemetry not configured
    try {
      final tags = <String, String>{
        'event_type': 'conversion',
        'conversion_event': conversionName,
        ...extraTags,
      };
      r(conversionName, tags);
    } catch (_) {
      // Telemetry must never break the user flow.
    }
  }

  /// Fires only the first time per install (dedup via Preferences).
  static void _trackOnce(String conversionName,
      [Map<String, String> extraTags = const {}]) {
    final prefKey = 'analytics.tracked.$conversionName';
    try {
      if (Preferences.getBool(prefKey, false)) return;
      _track(conversionName, extraTags);
      Preferences.setBool(prefKey, true);
    } catch (_) {
      // Never let telemetry break the user flow.
    }
  }
}
