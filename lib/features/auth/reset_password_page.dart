import 'dart:convert';

import 'package:flutter/material.dart';
import '../../navigation/app_navigator.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import 'auth_simple_input.dart';

/// Set new password — faithful port of `Views/Login/ResetPasswordPage.xaml(.cs)`.
///
/// Two modes mirror the two MAUI constructors:
///  * forgot-password reset — built with [email] + [code]; calls
///    `completePasswordReset` then auto-logs-in and routes.
///  * change-password (from Settings, already authenticated) — built via
///    [ResetPasswordPage.changePassword] with the verified [currentPassword];
///    calls `updateUserInfo(newPassword, currentPassword)` (server requires the
///    current password to authorize the change).
class ResetPasswordPage extends StatefulWidget {
  final String? email;
  final String? code;
  final bool isChangePassword;
  final String? currentPassword;

  const ResetPasswordPage({super.key, required this.email, required this.code})
      : isChangePassword = false,
        currentPassword = null;

  const ResetPasswordPage.changePassword({super.key, required this.currentPassword})
      : email = null,
        code = null,
        isChangePassword = true;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newPassword = _new.text;
    final confirm = _confirm.text;

    if (newPassword.trim().isEmpty || confirm.trim().isEmpty) {
      await _alert('Error', 'Please enter both password fields.');
      return;
    }
    if (newPassword != confirm) {
      await _alert('Error', 'Passwords do not match.');
      return;
    }
    if (newPassword.length < 8) {
      await _alert('Error', 'Password must be at least 8 characters long.');
      return;
    }

    setState(() => _loading = true);

    if (widget.isChangePassword) {
      await _changePassword(newPassword);
    } else {
      await _resetWithCode(newPassword);
    }
  }

  Future<void> _changePassword(String newPassword) async {
    // SECURITY: server requires the current password to authorize the change.
    final current = widget.currentPassword;
    if (current == null || current.isEmpty) {
      setState(() => _loading = false);
      await _alert('Error',
          'Current password missing. Please return to settings and try again.');
      return;
    }

    final result = await ServiceLocator.auth.updateUserInfo(
      newPassword: newPassword,
      currentPassword: current,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    final succeeded = !result.toLowerCase().contains('error') &&
        !result.toLowerCase().contains('"success":false');

    if (succeeded) {
      await _alert('Success',
          'Password changed successfully. Please log in with your new password.');
      if (!mounted) return;
      // Back to the login root — the token was cleared by updateUserInfo.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      // Surface the server message when present.
      var errorMsg = 'Failed to change password. Please try again.';
      try {
        final decoded = jsonDecode(result);
        if (decoded is Map && decoded['message'] is String) {
          errorMsg = decoded['message'] as String;
        }
      } catch (_) {}
      await _alert('Error', errorMsg);
    }
  }

  Future<void> _resetWithCode(String newPassword) async {
    final success = await ServiceLocator.auth
        .completePasswordReset(widget.email!, widget.code!, newPassword);
    if (!mounted) return;
    setState(() => _loading = false);

    if (!success) {
      await _alert('Error', 'Failed to reset password. Please try again.');
      return;
    }

    await _alert('Success',
        'Your password has been reset successfully. You will now be logged in.');

    // Attempt to log in with the new password, then route via the shared pipeline.
    final loggedIn =
        await ServiceLocator.auth.login(widget.email!, newPassword);
    if (!mounted) return;
    if (loggedIn) {
      await Preferences.setString('email', widget.email!);
      if (!mounted) return;
      await routeAfterAuth(context);
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
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
    final title = widget.isChangePassword ? 'Change Password' : 'Set New Password';
    final subtitle = widget.isChangePassword
        ? 'Enter your new password below.'
        : 'Please enter your new password below.';
    final buttonLabel = widget.isChangePassword ? 'Update Password' : 'Reset Password';

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const SizedBox(height: 20),
              Text(subtitle,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: palette.textPrimary)),
              const SizedBox(height: 20),
              AuthSimpleInput(controller: _new, hint: 'New Password', isPassword: true),
              const SizedBox(height: 20),
              AuthSimpleInput(controller: _confirm, hint: 'Confirm Password', isPassword: true),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(buttonLabel, style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
