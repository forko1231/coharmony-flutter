import 'package:flutter/material.dart';

import '../../navigation/app_navigator.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import 'landing_page.dart';

/// First screen shown at launch. Mirrors MAUI's `MainPage.OnAppearing`
/// auto-login: if "Remember me" was chosen and a stored session can be
/// restored (valid or refreshable token), route straight into the app via the
/// post-auth router; otherwise fall through to the landing screen. Shows a
/// brief splash spinner while deciding.
class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    Widget next = const LandingPage();
    try {
      if (Preferences.getBool('RememberMe') &&
          await ServiceLocator.auth.tryRestoreSession()) {
        next = await resolveAfterAuth();
      }
    } catch (_) {
      // Any failure restoring/routing → land on the welcome screen (safe).
      next = const LandingPage();
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => next),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
