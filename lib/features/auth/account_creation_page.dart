import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';
import '../../services/external_launcher.dart';
import '../../services/network_check.dart';
import '../../services/onboarding_state.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import 'verify_mfa_page.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_input_box.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_card.dart';

/// Sign-up screen — faithful port of `Views/Login/AccountCreation.xaml`.
/// Personal-info + account-details cards, a (client-side) password-strength
/// meter, terms acceptance, and a privacy reassurance card. Wired to
/// [AuthService.createAccount] + [PostAuthRouter] routing.
class AccountCreationPage extends StatefulWidget {
  const AccountCreationPage({super.key});

  @override
  State<AccountCreationPage> createState() => _AccountCreationPageState();
}

class _AccountCreationPageState extends State<AccountCreationPage> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscurePw = true;
  bool _obscureConfirm = true;
  bool _agreedTerms = false;
  int _strength = 0;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_first, _last, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _createAccount() async {
    final first = _first.text.trim();
    final last = _last.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final confirm = _confirm.text;

    if (first.isEmpty || last.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (_passwordScore(password) < 2) {
      setState(() => _error = 'Please choose a stronger password (mix letters, numbers or symbols).');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (!_agreedTerms) {
      setState(() => _error = 'Please accept the Terms and Privacy Policy.');
      return;
    }

    // Connectivity precheck (MAUI gates signup behind NetworkAccess).
    if (!await NetworkCheck.hasInternet(ServiceLocator.api.baseUrl)) {
      if (!mounted) return;
      setState(() => _error = 'No internet connection. Please check your network and try again.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Clear any previous session first (mirrors MAUI's RemoveTokenAsync before
      // signup) so a stale token from an earlier login can't leak into the new
      // account's first requests.
      await ServiceLocator.tokenService.removeToken();
      ServiceLocator.api.setAuthToken(null);

      // Phone is collected later in MAUI; pass empty to match the API signature.
      final ok = await ServiceLocator.auth.createAccount(email, password, first, last, '');
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Could not create your account. The email may already be in use.';
        });
        return;
      }

      // MAUI: register does NOT authenticate — log in to obtain a token before any
      // [Authorize] call (user/info, verification/send, partner/invite). Without this
      // every downstream request 401s and onboarding can't see the account's state.
      final loggedIn = await ServiceLocator.auth.login(email, password);
      if (!loggedIn) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Account created, but sign-in failed. Please try logging in.';
        });
        return;
      }

      AnalyticsService.trackSignupCompleted();

      // Fresh account → ensure it walks onboarding even if the email was reused.
      OnboardingState.reset(email);
      await Preferences.setString('email', email);

      if (!mounted) return;
      // New accounts are unverified — gate behind MFA to confirm email ownership
      // (mirrors MAUI's NavigateToVerificationAsync). The page sends the code, and on
      // success persists the email + runs PostAuthRouter.
      setState(() => _loading = false);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VerifyMfaPage(
          identifier: email,
          password: password,
          purpose: VerificationPurpose.newAccount,
          method: MfaMethod.email,
          forceMethod: true,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong creating your account. Please try again.';
      });
    }
  }

  /// Password strength 0–4 (length, mixed case, digit, symbol). Mirrors MAUI's
  /// scoring and is reused by both the meter and the submit-time gate.
  int _passwordScore(String pw) {
    int score = 0;
    if (pw.length >= 8) score++;
    if (RegExp(r'[a-z]').hasMatch(pw) && RegExp(r'[A-Z]').hasMatch(pw)) score++;
    if (RegExp(r'\d').hasMatch(pw)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) score++;
    return score;
  }

  static bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  void _onPasswordChanged(String pw) {
    setState(() => _strength = pw.isEmpty ? 0 : _passwordScore(pw).clamp(1, 4));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          AppHeader(
            title: 'Create Account',
            subtitle: 'Join CoHarmony™ to get started',
            padding: const EdgeInsets.fromLTRB(16, 12, 24, 16),
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Personal info
                  SectionCard(
                    iconName: 'icon_user',
                    iconBg: AppColors.iconBgBlue,
                    iconTint: AppColors.primaryBlue,
                    title: 'Personal Info',
                    subtitle: 'Tell us about yourself',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _labeledField('First Name', _first, 'First name')),
                        const SizedBox(width: 12),
                        Expanded(child: _labeledField('Last Name', _last, 'Last name')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Account details
                  SectionCard(
                    iconName: 'icon_lock',
                    iconBg: AppColors.iconBgGreen,
                    iconTint: AppColors.successGreen,
                    title: 'Account Details',
                    subtitle: 'Secure your account',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _labeledField('Email Address', _email, 'you@example.com',
                            keyboardType: TextInputType.emailAddress),
                        const SizedBox(height: 16),
                        // Password + strength
                        _label('Password'),
                        const SizedBox(height: 8),
                        AppInputBox(
                          child: AppTextField(
                            controller: _password,
                            hint: 'Create a password',
                            obscure: _obscurePw,
                            onChanged: _onPasswordChanged,
                            trailing: _eyeToggle(_obscurePw, () => setState(() => _obscurePw = !_obscurePw)),
                          ),
                        ),
                        // strength meter is set via a listener below
                        if (_password.text.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: List.generate(4, (i) {
                              final active = i < _strength;
                              return Expanded(
                                child: Container(
                                  height: 4,
                                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                                  decoration: BoxDecoration(
                                    color: active ? _strengthColor : palette.border,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 4),
                          Text(_strengthLabel,
                              style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                        ],
                        const SizedBox(height: 16),
                        _label('Confirm Password'),
                        const SizedBox(height: 8),
                        AppInputBox(
                          child: AppTextField(
                            controller: _confirm,
                            hint: 'Confirm your password',
                            obscure: _obscureConfirm,
                            trailing:
                                _eyeToggle(_obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Terms
                        AppInputBox(
                          strokeThickness: 1,
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _agreedTerms,
                                  activeColor: AppColors.primaryBlue,
                                  onChanged: (v) => setState(() => _agreedTerms = v ?? false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(fontSize: 14, color: palette.textPrimary),
                                    children: [
                                      const TextSpan(text: 'I agree to the '),
                                      TextSpan(
                                          text: 'Terms',
                                          style: const TextStyle(
                                              color: AppColors.primaryBlue,
                                              fontWeight: FontWeight.bold,
                                              decoration: TextDecoration.underline),
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () => ExternalLauncher.openUrl('https://co-harmony.com/Legal/Terms')),
                                      const TextSpan(text: ' and '),
                                      TextSpan(
                                          text: 'Privacy Policy',
                                          style: const TextStyle(
                                              color: AppColors.primaryBlue,
                                              fontWeight: FontWeight.bold,
                                              decoration: TextDecoration.underline),
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () => ExternalLauncher.openUrl('https://co-harmony.com/Legal/Privacy')),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          _errorBox(context, _error!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Privacy reassurance
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: palette.infoBg,
                      border: Border.all(color: AppColors.infoBlue),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: AppColors.infoBlue, borderRadius: BorderRadius.circular(12)),
                          child: const Center(child: AppIcon('icon_shield', size: 22, color: Colors.white)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Your data is secure',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: context.isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1))),
                              const SizedBox(height: 6),
                              Text('Encrypted and never sold to third parties',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: context.isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          BottomActionBar(
            child: PrimaryGradientButton(
              label: 'Create Account',
              iconName: 'icon_sparkle',
              loading: _loading,
              colors: const [AppColors.successGreen, AppColors.successGreenLight],
              onTap: _loading ? null : _createAccount,
            ),
          ),
        ],
      ),
    );
  }

  Color get _strengthColor => switch (_strength) {
        1 => AppColors.dangerRed,
        2 => AppColors.warningAmber,
        3 => AppColors.primaryBlue,
        _ => AppColors.successGreen,
      };

  String get _strengthLabel => switch (_strength) {
        1 => 'Weak password',
        2 => 'Fair password',
        3 => 'Good password',
        _ => 'Strong password',
      };

  Widget _label(String text) =>
      Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: context.palette.textPrimary));

  Widget _labeledField(String label, TextEditingController c, String hint, {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 8),
        AppInputBox(
          child: AppTextField(
            controller: c,
            hint: hint,
            keyboardType: keyboardType,
            onSubmitted: (_) {},
          ),
        ),
      ],
    );
  }

  Widget _eyeToggle(bool obscured, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AppIcon(obscured ? 'icon_eye_off' : 'icon_eye', size: 22, color: context.palette.textSecondary),
      );

  Widget _errorBox(BuildContext context, String message) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.errorBg,
        border: Border.all(color: palette.errorBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AppIcon('icon_alert', size: 18, color: AppColors.dangerRed),
          const SizedBox(width: 8),
          Flexible(
            child: Text(message,
                style: TextStyle(fontSize: 14, color: context.isDark ? AppColors.dangerRedLight : AppColors.dangerRed)),
          ),
        ],
      ),
    );
  }
}
