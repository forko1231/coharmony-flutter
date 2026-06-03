import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import 'auth_simple_input.dart';

/// Re-auth (enter current password) — faithful port of
/// `Views/Login/VerifyPasswordPage.xaml(.cs)`.
///
/// Verifies the typed password against the stored account email via
/// `login`, and on success returns it to the caller through
/// `Navigator.pop(context, password)` (MAUI used a TaskCompletionSource).
/// A plain back / dismiss returns `null`.
class VerifyPasswordPage extends StatefulWidget {
  const VerifyPasswordPage({super.key});

  @override
  State<VerifyPasswordPage> createState() => _VerifyPasswordPageState();
}

class _VerifyPasswordPageState extends State<VerifyPasswordPage> {
  final _password = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final password = _password.text;
    if (password.trim().isEmpty) {
      setState(() => _error = 'Please enter your password.');
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });

    final email = await ServiceLocator.secureStorage.getSecureEmail();
    final valid = await ServiceLocator.auth.login(email, password);
    if (!mounted) return;
    setState(() => _loading = false);

    if (valid) {
      Navigator.of(context).pop(password);
    } else {
      setState(() {
        _error = 'Incorrect password. Please try again.';
        _password.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(title: const Text('Verify Identity')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Verify Identity',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const SizedBox(height: 20),
              Text('Please enter your current password to continue.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: palette.textSecondary)),
              const SizedBox(height: 20),
              AuthSimpleInput(controller: _password, hint: 'Current password', isPassword: true),
              if (_error != null) ...[
                const SizedBox(height: 20),
                Text(_error!,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.dangerRed)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _loading ? null : _continue,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Continue', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
