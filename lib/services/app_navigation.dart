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

  /// Fired by [AppShell] whenever the Messages tab is (re)selected. The shell keeps
  /// tab bodies alive in an IndexedStack, so MessagingPage's initState runs only once;
  /// this lets it re-fetch partner/contact state each time it's shown (e.g. after a
  /// co-parent accepts an invite). Registered by MessagingPage.
  static void Function()? onMessagesTabShown;

  /// True while a chat screen is in the foreground — used to suppress message
  /// banners (mirrors MAUI's `IsCurrentlyInChatInterface`).
  static bool inChat = false;

  /// LiveKit server URL, set once at startup by [ServiceLocator.init]. Exposed
  /// here so the BuildContext-less calling/CallKit layer can read it.
  static String livekitUrl = '';
}
