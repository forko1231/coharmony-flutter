import 'package:shared_preferences/shared_preferences.dart';

/// Thin equivalent of MAUI's `Microsoft.Maui.Storage.Preferences.Default`,
/// backed by `shared_preferences`. Non-sensitive key/value app settings only —
/// secrets go through [SecureStorageService] instead.
///
/// Call [Preferences.init] once at startup (see `service_locator.dart`) so the
/// synchronous getters/setters match the MAUI call sites 1:1.
class Preferences {
  Preferences._();

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    final p = _prefs;
    if (p == null) {
      throw StateError('Preferences.init() must be awaited before use.');
    }
    return p;
  }

  static bool getBool(String key, [bool defaultValue = false]) =>
      _p.getBool(key) ?? defaultValue;
  static String getString(String key, [String defaultValue = '']) =>
      _p.getString(key) ?? defaultValue;
  static int getInt(String key, [int defaultValue = 0]) =>
      _p.getInt(key) ?? defaultValue;

  static Future<void> setBool(String key, bool value) => _p.setBool(key, value);
  static Future<void> setString(String key, String value) =>
      _p.setString(key, value);
  static Future<void> setInt(String key, int value) => _p.setInt(key, value);

  static bool containsKey(String key) => _p.containsKey(key);
  static Future<void> remove(String key) => _p.remove(key);

  /// Equivalent of MAUI `Preferences.Clear()` — wipes all stored app settings.
  static Future<void> clear() => _p.clear();
}
