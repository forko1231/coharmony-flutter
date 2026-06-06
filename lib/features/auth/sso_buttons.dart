import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../navigation/app_navigator.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_palette.dart';

/// The Web / "server" OAuth client ID from Google Cloud Console → Credentials.
/// Passed to Google as the server client id so the returned ID token's audience
/// matches what the backend validates against `Authentication:Google:ClientIds`.
/// Provide at build time: `--dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com`.
const String kGoogleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '877762151190-uq4gdsd220frgoa7eko2gap3qjce0be8.apps.googleusercontent.com',
);

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
        // 'profile' makes Google put given_name/family_name in the ID token so the
        // backend can populate the user's name (without it, names come back blank).
        scopes: const ['email', 'profile'],
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
        // SSO implies "this is my device" — always keep me signed in (one-tap to
        // re-auth anyway). No checkbox; logout still force-clears this.
        await Preferences.setBool('RememberMe', true);
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

  Future<void> _signInWithApple() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final cred = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final idToken = cred.identityToken;
      if (idToken == null || idToken.isEmpty) {
        _toast('Apple sign-in failed (no token).');
        return;
      }
      // Name arrives only on the first sign-in; backend backfills it.
      final ok = await ServiceLocator.auth.signInWithApple(
        idToken,
        firstName: cred.givenName,
        lastName: cred.familyName,
      );
      if (!mounted) return;
      if (ok) {
        // Keep me signed in (see Google handler). The relay-email gate (if any) is
        // handled by the post-auth router via the server record — not touched here.
        await Preferences.setBool('RememberMe', true);
        if (mounted) await routeAfterAuth(context);
      } else {
        _toast('Could not sign in with Apple. Please try again.');
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) _toast('Apple sign-in error.');
    } catch (_) {
      _toast('Apple sign-in error. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
