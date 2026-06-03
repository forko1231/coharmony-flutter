import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import 'auth_simple_input.dart';
import 'verify_mfa_page.dart';

/// Forgot-password (request code) — faithful port of
/// `Views/Login/ForgotPasswordPage.xaml(.cs)`. Sends a reset code via
/// `initiatePasswordReset`, then pushes the MFA page in password-reset mode.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      await _alert('Error', 'Please enter your email address.');
      return;
    }

    setState(() => _loading = true);
    final success = await ServiceLocator.auth.initiatePasswordReset(email);
    if (!mounted) return;
    setState(() => _loading = false);

    if (success) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyMfaPage(
            identifier: email,
            purpose: VerificationPurpose.passwordReset,
            method: MfaMethod.email,
            forceMethod: true,
          ),
        ),
      );
    } else {
      await _alert('Error',
          'Failed to send verification code. Please check your email and try again.');
    }
  }

  Future<void> _alert(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reset Password',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const SizedBox(height: 20),
              Text('Enter your email address to receive a verification code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: palette.textPrimary)),
              const SizedBox(height: 20),
              AuthSimpleInput(controller: _email, hint: 'Email Address', keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _loading ? null : _sendCode,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send Code', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
