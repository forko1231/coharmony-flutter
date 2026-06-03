import 'package:flutter/material.dart';
import '../../navigation/app_navigator.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_input_box.dart';
import '../../widgets/primary_button.dart';
import 'forgot_password_page.dart';
import 'verify_mfa_page.dart';

/// Sign-in screen — faithful port of `Views/Login/Login.xaml`.
/// Wired to [AuthService.login] + [PostAuthRouter] routing.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _rememberMe = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Persist the RememberMe choice (read by logout) before authenticating.
      await Preferences.setBool('RememberMe', _rememberMe);

      final ok = await ServiceLocator.auth.login(email, password);
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Invalid email or password. Please try again.';
        });
        return;
      }

      // The routers read the signed-in email from this preference.
      await Preferences.setString('email', email);

      // MAUI policy (HandleSuccessfulLoginAsync): the DB is the source of truth for
      // "email verified". If already verified, skip MFA and route. Otherwise (or if
      // the check fails — FAIL-SAFE) gate behind an email MFA before routing.
      bool emailVerified = false;
      try {
        final info = await ServiceLocator.auth.getUserInfo();
        emailVerified = info?.emailConfirmed ?? false;
      } catch (_) {
        emailVerified = false;
      }
      if (!mounted) return;

      if (emailVerified) {
        await routeAfterAuth(context);
      } else {
        setState(() => _loading = false);
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VerifyMfaPage(
            identifier: email,
            password: password,
            purpose: VerificationPurpose.login,
            method: MfaMethod.email,
            forceMethod: true,
            onComplete: (verified) {
              if (verified && mounted) routeAfterAuth(context);
            },
          ),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong signing in. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          AppHeader(
            title: 'Welcome Back',
            subtitle: 'Sign in to your account',
            padding: const EdgeInsets.fromLTRB(16, 12, 24, 16),
            onBack: () => Navigator.of(context).maybePop(),
          ),

          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.05),
                      offset: const Offset(0, 8),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header icon + titles
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.iconBgBlue,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(child: AppIcon('icon_lock', size: 28, color: AppColors.primaryBlue)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Account Login',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                              const SizedBox(height: 4),
                              Text('Enter your credentials',
                                  style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Email
                    _FieldLabel('Email Address'),
                    const SizedBox(height: 10),
                    AppInputBox(
                      child: AppTextField(
                        controller: _email,
                        hint: 'Enter your email',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Password (label row + forgot link)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _FieldLabel('Password'),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordPage()),
                            );
                          },
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryBlue,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AppInputBox(
                      child: AppTextField(
                        controller: _password,
                        hint: 'Enter your password',
                        obscure: _obscure,
                        textInputAction: TextInputAction.done,
                        trailing: GestureDetector(
                          onTap: () => setState(() => _obscure = !_obscure),
                          child: AppIcon(_obscure ? 'icon_eye_off' : 'icon_eye', size: 22, color: palette.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Remember me
                    AppInputBox(
                      strokeThickness: 1,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: AppColors.primaryBlue,
                              onChanged: (v) => setState(() => _rememberMe = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Remember me on this device',
                              style: TextStyle(fontSize: 14, color: palette.textPrimary)),
                        ],
                      ),
                    ),

                    // Error
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: palette.errorBg,
                          border: Border.all(color: palette.errorBorder),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const AppIcon('icon_alert', size: 18, color: AppColors.dangerRed),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(_error!,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: context.isDark ? AppColors.dangerRedLight : AppColors.dangerRed)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Sign In button
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.10),
                  offset: const Offset(0, -6),
                  blurRadius: 20,
                ),
              ],
            ),
            child: PrimaryGradientButton(
              label: 'Sign In',
              iconName: 'icon_lock',
              loading: _loading,
              onTap: _loading ? null : _signIn,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.palette.textPrimary));
  }
}
