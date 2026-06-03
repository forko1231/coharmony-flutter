import 'package:flutter/material.dart';
import '../services/preferences.dart';

/// App-wide theme mode, persisted to [Preferences] under `app_theme`.
/// The MAUI Settings page persists "System"/"Light"/"Dark"; this mirrors that and
/// drives [MaterialApp.themeMode] reactively via [mode].
class ThemeController {
  ThemeController._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);
  static const _key = 'app_theme';

  /// The current selection as the label the Settings dropdown shows.
  static String get label => switch (mode.value) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };

  /// Load the persisted preference into [mode]. Call after Preferences.init().
  static void load() => mode.value = _fromLabel(Preferences.getString(_key, 'System'));

  static Future<void> setLabel(String label) async {
    mode.value = _fromLabel(label);
    await Preferences.setString(_key, label);
  }

  static ThemeMode _fromLabel(String l) => switch (l) {
        'Light' => ThemeMode.light,
        'Dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
