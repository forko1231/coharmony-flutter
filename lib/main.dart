import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'features/auth/bootstrap_page.dart';
import 'services/analytics_service.dart';
import 'services/app_navigation.dart';
import 'services/service_locator.dart';
import 'services/telemetry_config.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/motion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialise the service layer (Preferences, secure storage, API client, all
  // services) before the first frame so screens can use ServiceLocator.* directly.
  await ServiceLocator.init();
  ThemeController.load(); // restore the persisted light/dark/system preference

  // Crash reporting + funnel analytics via Sentry (port of MAUI's UseSentry).
  // No-op when the DSN is empty. The AnalyticsService.reporter sink turns each
  // conversion event into a tagged Sentry message.
  if (TelemetryConfig.isSentryEnabled) {
    await SentryFlutter.init(
      (options) {
        options.dsn = TelemetryConfig.sentryDsn;
        options.environment = kReleaseMode ? 'production' : 'debug';
        options.debug = !kReleaseMode;
        options.release = TelemetryConfig.release;
        // Privacy: don't auto-attach user IPs / personal data.
        options.sendDefaultPii = false;
        // Group sessions per app foreground/background cycle for crash-free-rate.
        options.enableAutoSessionTracking = true;
        // Keep tracing/screenshots off (matches MAUI).
        options.tracesSampleRate = 0.0;
        options.attachScreenshot = false;
      },
      appRunner: () {
        AnalyticsService.reporter = _reportConversionToSentry;
        runApp(const CoHarmonyApp());
      },
    );
  } else {
    runApp(const CoHarmonyApp());
  }
}

/// Reports a conversion event to Sentry as a tagged Info-level message —
/// mirrors C# `AnalyticsService.Track` (`CaptureMessage("conversion: …")`).
void _reportConversionToSentry(String conversionName, Map<String, String> tags) {
  Sentry.captureMessage(
    'conversion: $conversionName',
    level: SentryLevel.info,
    withScope: (scope) {
      tags.forEach(scope.setTag);
    },
  );
}

/// App root. Hosts the theme and opens on the landing screen; the auth gate
/// routes onward via [PostAuthRouter] once the user signs in.
class CoHarmonyApp extends StatelessWidget {
  const CoHarmonyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, child) => MaterialApp(
        title: 'CoHarmony',
        navigatorKey: AppNavigation.navigatorKey,
        debugShowCheckedModeBanner: false,
        scrollBehavior: const AppScrollBehavior(),
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        // App-wide guard: cap how far the OS text-size / accessibility setting can
        // enlarge text. A large system font (common on parents'/grandparents'
        // phones) otherwise wraps and breaks fixed-height buttons and labels —
        // worst on small screens. 1.2x still honours some enlargement.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.2)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const BootstrapPage(),
      ),
    );
  }
}
