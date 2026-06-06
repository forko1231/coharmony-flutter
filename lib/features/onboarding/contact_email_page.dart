import 'package:flutter/material.dart';

import '../../navigation/app_navigator.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_input_box.dart';
import '../../widgets/primary_button.dart';

/// Shown right after an Apple "Hide My Email" sign-in: the account currently has a
/// @privaterelay.appleid.com address, which a co-parent can't use to find them. We
/// collect + verify a real email and the server swaps it in (then re-issues the token).
class ContactEmailPage extends StatefulWidget {
  const ContactEmailPage({super.key});

  @override
  State<ContactEmailPage> createState() => _ContactEmailPageState();
}

class _ContactEmailPageState extends State<ContactEmailPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ServiceLocator.auth.requestContactEmail(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _codeSent = true;
      } else {
        _error = "Couldn't send the code — check the address and try again.";
      }
    });
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code we emailed you.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ServiceLocator.auth.confirmContactEmail(code);
    if (!mounted) return;
    if (ok) {
      // Email is now real — continue into normal onboarding.
      if (mounted) await routeAfterAuth(context);
    } else {
      setState(() {
        _busy = false;
        _error = "That didn't work — check the code and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, MediaQuery.viewPaddingOf(context).top + 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text('One last thing',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const SizedBox(height: 12),
              Text(
                _codeSent
                    ? "Enter the 6-digit code we just emailed you."
                    : "You signed in with Apple's private email. So your co-parent can find and connect with you, add an email you actually check.",
                style: TextStyle(fontSize: 15, height: 1.45, color: palette.textSecondary),
              ),
              const SizedBox(height: 28),
              if (!_codeSent)
                AppInputBox(
                  child: AppTextField(
                    controller: _email,
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_busy) _send();
                    },
                  ),
                )
              else
                AppInputBox(
                  child: AppTextField(
                    controller: _code,
                    hint: 'Verification code',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_busy) _confirm();
                    },
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.dangerRed, fontSize: 14)),
              ],
              const Spacer(),
              if (_codeSent)
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _codeSent = false),
                  child: const Text('Use a different email'),
                ),
              PrimaryGradientButton(
                label: _codeSent ? 'Confirm' : 'Send code',
                loading: _busy,
                onTap: _busy ? null : (_codeSent ? _confirm : _send),
              ),
              SizedBox(height: 24 + MediaQuery.viewPaddingOf(context).bottom),
            ],
          ),
        ),
      ),
    );
  }
}
