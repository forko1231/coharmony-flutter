import 'package:flutter/material.dart';

/// App-wide navigation hooks used by the push/notification layer (which has no
/// BuildContext of its own). The MAUI app reached the same surfaces through
/// `Shell.Current` / `Shell.GoToAsync`; here we expose a global navigator key
/// plus a tab switcher the [AppShell] registers.
class AppNavigation {
  AppNavigation._();

  /// Wired to `MaterialApp.navigatorKey` so the notification layer can push pages.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Registered by [AppShell]; switches the bottom-tab (0 Home, 1 Schedule,
  /// 2 Messager, 3 Payments, 4 Map). Null when the shell isn't mounted.
  static void Function(int index)? goToTab;

  /// True while a chat screen is in the foreground — used to suppress message
  /// banners (mirrors MAUI's `IsCurrentlyInChatInterface`).
  static bool inChat = false;

  /// LiveKit server URL, set once at startup by [ServiceLocator.init]. Exposed
  /// here so the BuildContext-less calling/CallKit layer can read it.
  static String livekitUrl = '';
}
