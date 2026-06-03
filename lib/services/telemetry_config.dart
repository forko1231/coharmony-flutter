/// Port of `Services/TelemetryConfig.cs`. Central place for crash-reporting /
/// analytics keys.
class TelemetryConfig {
  TelemetryConfig._();

  /// DSN from the Sentry project. Safe to commit — DSNs are public client keys;
  /// they only allow sending events to the project, not reading them.
  static const String sentryDsn =
      'https://43205176bc633cef70c382b272669c0e@o4511431204667392.ingest.us.sentry.io/4511431207223296';

  static bool get isSentryEnabled => sentryDsn.trim().isNotEmpty;

  /// Release identifier reported to Sentry (matches MAUI `coharmony@{version}`).
  static const String release = 'coharmony@1.0.0';
}
