import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../navigation/app_navigator.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_palette.dart';

/// The Web / "server" OAuth client ID from Google Cloud Console → Credentials.
/// Passed to Google as the server client id so the returned ID token's audience
/// matches what the backend validates against `Authentication:Google:ClientIds`.
/// Provide at build time: `--dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com`.
const String kGoogleServerClientId =
    String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');

/// Apple + Google one-tap sign-in, side by side. SSO find-or-creates the account
/// server-side, so a single tap covers both "sign up" and "log in" — no need to
/// pick a screen first.
class SsoButtons extends StatefulWidget {
  const SsoButtons({super.key});

  @override
  State<SsoButtons> createState() => _SsoButtonsState();
}

class _SsoButtonsState extends State<SsoButtons> {
  bool _busy = false;

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final gsi = GoogleSignIn(
        scopes: const ['email'],
        serverClientId: kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
      );
      await gsi.signOut(); // always show the account picker
      final account = await gsi.signIn();
      if (account == null) return; // user cancelled
      final idToken = (await account.authentication).idToken;
      if (idToken == null || idToken.isEmpty) {
        _toast('Google sign-in failed (no token).');
        return;
      }
      final ok = await ServiceLocator.auth.signInWithGoogle(idToken);
      if (!mounted) return;
      if (ok) {
        await Preferences.setString('email', account.email);
        if (mounted) await routeAfterAuth(context);
      } else {
        _toast('Could not sign in with Google. Please try again.');
      }
    } catch (_) {
      _toast('Google sign-in error. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _signInWithApple() {
    // Apple is the next increment — it adds the "Hide My Email" contact-email step
    // in onboarding and the /api/auth/apple endpoint.
    _toast('Apple sign-in is coming soon.');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Apple is only shown on iOS (Android uses a clunky web flow + Google covers it).
        if (Platform.isIOS) ...[
          Expanded(
            child: _SsoButton(
              label: 'Apple',
              icon: Icons.apple,
              onTap: _busy ? null : _signInWithApple,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: _SsoButton(
            label: 'Google',
            icon: Icons.g_mobiledata,
            onTap: _busy ? null : _signInWithGoogle,
          ),
        ),
      ],
    );
  }
}

class _SsoButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _SsoButton({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: palette.textPrimary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }
}
