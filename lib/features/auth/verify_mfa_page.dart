import 'dart:async';

import 'package:flutter/material.dart';
import '../../navigation/app_navigator.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_input_box.dart';
import '../../widgets/primary_button.dart';
import 'reset_password_page.dart';

/// Verification method — port of `VerifyMFA.MFAMethod`.
enum MfaMethod { email, sms, none }

/// Why we're verifying — port of `VerifyMFA.VerificationPurpose`.
enum VerificationPurpose {
  newAccount,
  changeEmail,
  changePhone,
  secureAction,
  passwordReset,
  login,
}

/// Two-factor verification — faithful port of `Views/Login/VerifyMFA.xaml(.cs)`.
///
/// Shared across flows (new-account, password-reset, change-email/phone,
/// secure-action, login MFA gate). On construction it configures its copy for
/// the [purpose], sends the code for the chosen [method], and runs a 60-second
/// resend countdown. On success it routes per purpose, mirroring
/// `HandleSuccessfulVerification`.
class VerifyMfaPage extends StatefulWidget {
  final String identifier; // email or phone being verified
  final String password; // legacy passthrough (unused by the verify calls)
  final VerificationPurpose purpose;
  final MfaMethod method;
  final bool forceMethod;
  final void Function(bool verified)? onComplete;

  const VerifyMfaPage({
    super.key,
    required this.identifier,
    this.password = '',
    this.purpose = VerificationPurpose.newAccount,
    this.method = MfaMethod.email,
    this.forceMethod = false,
    this.onComplete,
  });

  @override
  State<VerifyMfaPage> createState() => _VerifyMfaPageState();
}

class _VerifyMfaPageState extends State<VerifyMfaPage> {
  final _code = TextEditingController();
  String? _error;
  bool _verifying = false;

  MfaMethod _currentMethod = MfaMethod.none;

  // Resend countdown.
  Timer? _countdownTimer;
  int _countdownSeconds = 0;
  bool _canResend = true;
  bool _resending = false;

  // Purpose-driven copy (mirrors VerificationTitle / VerificationInstructions).
  String _title = 'Verification Required';
  String _instructions = 'Please verify your identity to continue';

  @override
  void initState() {
    super.initState();
    _configureForPurpose();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _configureForPurpose() {
    switch (widget.purpose) {
      case VerificationPurpose.newAccount:
        _title = 'Verify Your Account';
        _instructions =
            'A verification code has been sent. Please enter it below to verify your account.';
        _setVerificationMethod(widget.method);
        break;
      case VerificationPurpose.changeEmail:
        _title = 'Verify Email Address';
        _instructions =
            'A verification code has been sent to your new email. Please enter it below.';
        _setVerificationMethod(widget.method);
        break;
      case VerificationPurpose.changePhone:
        _title = 'Verify Phone Number';
        _instructions =
            'A verification code has been sent to your phone. Please enter it below.';
        _setVerificationMethod(widget.method);
        break;
      case VerificationPurpose.secureAction:
        _title = 'Security Verification';
        _instructions =
            'To continue, please verify your identity with a security code.';
        _checkAvailableVerificationMethods();
        break;
      case VerificationPurpose.login:
        _title = "Verify it's you";
        _instructions =
            'For your security, we sent a verification code to your email. Enter it to continue.';
        _setVerificationMethod(widget.method);
        break;
      case VerificationPurpose.passwordReset:
        // MAUI leaves the picker untouched here — the code was already sent by
        // ForgotPasswordPage's InitiatePasswordResetAsync, so we don't resend on
        // entry. The verify branch keys off the purpose, not _currentMethod.
        _title = 'Reset Password';
        _instructions =
            'Enter the verification code we emailed you to reset your password.';
        break;
    }
  }

  Future<void> _checkAvailableVerificationMethods() async {
    final info = await ServiceLocator.auth.getUserInfo();
    final emailVerified = info?.emailConfirmed ?? false;
    final phoneVerified = info?.phoneNumConfirmed ?? false;

    // (The in-UI method selector isn't part of this layout; we still pick the
    // correct default method to send through.)
    if (emailVerified) {
      _setVerificationMethod(MfaMethod.email);
    } else if (phoneVerified) {
      _setVerificationMethod(MfaMethod.sms);
    } else {
      _setVerificationMethod(MfaMethod.email);
    }
  }

  void _setVerificationMethod(MfaMethod method) {
    _currentMethod = method;
    switch (method) {
      case MfaMethod.email:
        _instructions =
            'A verification code has been sent to your email. Please enter it below.';
        _sendVerificationCodeToEmail();
        break;
      case MfaMethod.sms:
        _instructions =
            'A verification code has been sent to your phone. Please enter it below.';
        _sendVerificationCodeToSms();
        break;
      case MfaMethod.none:
        _currentMethod = MfaMethod.email;
        _instructions =
            'A verification code has been sent to your email. Please enter it below.';
        _sendVerificationCodeToEmail();
        break;
    }
  }

  Future<void> _sendVerificationCodeToEmail() async {
    final sent = await ServiceLocator.auth.sendVerificationCode();
    if (!mounted) return;
    if (!sent) {
      await _alert('Error',
          'Failed to send verification code to email. Please try again.');
      if (widget.purpose != VerificationPurpose.secureAction && mounted) {
        Navigator.of(context).maybePop();
      }
    } else {
      _startCountdown();
    }
  }

  Future<void> _sendVerificationCodeToSms() async {
    final sent =
        await ServiceLocator.auth.sendSmsVerificationCode(widget.identifier);
    if (!mounted) return;
    if (!sent) {
      await _alert(
          'Error', 'Failed to send SMS verification code. Please try again.');
      if (widget.purpose != VerificationPurpose.secureAction && mounted) {
        Navigator.of(context).maybePop();
      }
    } else {
      _startCountdown();
    }
  }

  // ---- Verify -------------------------------------------------------------

  Future<void> _onVerify() async {
    if (_verifying) return;
    setState(() => _error = null);

    final raw = _code.text;
    if (raw.trim().isEmpty) {
      setState(() => _error = 'Please enter the verification code.');
      return;
    }
    final code = raw.split('').where((c) => RegExp(r'\d').hasMatch(c)).join();
    if (code.length < 6) {
      setState(() => _error = 'Invalid verification code format.');
      return;
    }

    final remaining = await _getRemainingAttempts();
    if (remaining <= 0) {
      setState(() {
        _error = 'Too many failed attempts. Please request a new code.';
        _canResend = true;
      });
      return;
    }

    setState(() => _verifying = true);
    bool verified;
    if (widget.purpose == VerificationPurpose.passwordReset) {
      verified = await ServiceLocator.auth
          .verifyPasswordResetCode(widget.identifier, code);
    } else if (_currentMethod == MfaMethod.sms) {
      verified =
          await ServiceLocator.auth.verifySmsCode(widget.identifier, code);
    } else {
      verified = await ServiceLocator.auth.verifyEmailWithCode(code);
    }
    if (!mounted) return;
    setState(() => _verifying = false);

    if (verified) {
      await _resetAttempts();
      if (!mounted) return;
      await _handleSuccess(code);
    } else {
      final left = remaining - 1;
      await _updateRemainingAttempts(left);
      if (!mounted) return;
      setState(() {
        if (left <= 0) {
          _error = 'Too many failed attempts. Please request a new code.';
          _canResend = true;
        } else {
          _error = 'Invalid verification code. $left attempts remaining.';
        }
      });
    }
  }

  Future<void> _handleSuccess(String code) async {
    switch (widget.purpose) {
      case VerificationPurpose.newAccount:
        await _alert('Success', 'Your account has been verified successfully!');
        if (!mounted) return;
        // Auto-login: the account was already authenticated before this page,
        // so just persist the email and run the post-auth router.
        await Preferences.setString('email', widget.identifier);
        if (!mounted) return;
        await routeAfterAuth(context);
        break;
      case VerificationPurpose.changeEmail:
        await _alert('Success', 'Your email has been verified successfully!');
        widget.onComplete?.call(true);
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        break;
      case VerificationPurpose.changePhone:
        await _alert(
            'Success', 'Your phone number has been verified successfully!');
        widget.onComplete?.call(true);
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        break;
      case VerificationPurpose.secureAction:
        widget.onComplete?.call(true);
        if (mounted) Navigator.of(context).maybePop();
        break;
      case VerificationPurpose.login:
        if (widget.onComplete != null) {
          // Hand back to the login flow, which runs the post-auth routing.
          widget.onComplete!(true);
        } else {
          // Cold-start gate (restored session, no login page beneath us):
          // run the post-auth routing ourselves. The server marked the email
          // verified on success, so the router won't gate again.
          await routeAfterAuth(context);
        }
        break;
      case VerificationPurpose.passwordReset:
        // Carry the verified code to the reset page.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ResetPasswordPage(email: widget.identifier, code: code),
          ),
        );
        break;
    }
  }

  // ---- Resend + countdown -------------------------------------------------

  Future<void> _onSendNewCode() async {
    if (!_canResend || _resending) return;
    setState(() {
      _error = null;
      _resending = true;
    });

    bool sent;
    if (_currentMethod == MfaMethod.sms) {
      sent =
          await ServiceLocator.auth.sendSmsVerificationCode(widget.identifier);
    } else if (widget.purpose == VerificationPurpose.passwordReset) {
      sent = await ServiceLocator.auth.initiatePasswordReset(widget.identifier);
    } else {
      sent = await ServiceLocator.auth.sendVerificationCode();
    }
    if (!mounted) return;
    setState(() => _resending = false);

    if (sent) {
      await _resetAttempts();
      if (!mounted) return;
      _startCountdown();
    } else {
      setState(() => _error = _currentMethod == MfaMethod.sms
          ? 'Failed to send a new SMS code. Please try again.'
          : 'Failed to send a new email code. Please try again.');
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdownSeconds = 60;
      _canResend = false;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _countdownSeconds--;
        if (_countdownSeconds <= 0) {
          _countdownTimer?.cancel();
          _canResend = true;
        }
      });
    });
  }

  // ---- Attempt tracking (mirrors the SecureStorage counter) ---------------

  String get _attemptsKey =>
      'MFA_REMAINING_ATTEMPTS_${widget.identifier}_$_currentMethod';

  Future<int> _getRemainingAttempts() async {
    final s = await ServiceLocator.secureStorage.secureRetrieve(_attemptsKey, '');
    final n = int.tryParse(s);
    if (n != null) return n;
    await _updateRemainingAttempts(3);
    return 3;
  }

  Future<void> _updateRemainingAttempts(int attempts) =>
      ServiceLocator.secureStorage.secureStore(_attemptsKey, attempts.toString());

  Future<void> _resetAttempts() => _updateRemainingAttempts(3);

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
    final infoTitle = context.isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1);
    final infoBody = context.isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1);

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.viewPaddingOf(context).top + 16, 24, 20),
            decoration: BoxDecoration(
              color: palette.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
                  offset: const Offset(0, 4),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Column(
              children: [
                Text(_title,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 6),
                Text(_instructions,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: palette.textSecondary)),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                children: [
                  // 2FA card
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: palette.surfaceElevated,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.06),
                          offset: const Offset(0, 8),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                  color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(14)),
                              child: const Center(child: Text('🔐', style: TextStyle(fontSize: 24))),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Two-Factor Authentication',
                                      style: TextStyle(
                                          fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                                  const SizedBox(height: 4),
                                  Text('Enter the verification code sent to your device',
                                      style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text('Verification Code',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                        const SizedBox(height: 10),
                        AppInputBox(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: TextField(
                            controller: _code,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            onChanged: (v) {
                              // Auto-submit on a complete 6-digit entry.
                              if (v.length == 6) _onVerify();
                            },
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary),
                            cursorColor: palette.textPrimary,
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              counterText: '',
                              hintText: 'Enter 6-digit code',
                              hintStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPlaceholder),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        PrimaryGradientButton(
                          label: '✅ Verify Code',
                          height: 56,
                          loading: _verifying,
                          colors: const [AppColors.successGreen, AppColors.successGreenLight],
                          onTap: _verifying ? null : _onVerify,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: palette.errorBg,
                              border: Border.all(color: palette.errorBorder),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: context.isDark ? AppColors.dangerRedLight : const Color(0xFFDC2626))),
                          ),
                        ],
                        const SizedBox(height: 24),
                        // Resend section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: palette.surfaceInput,
                            border: Border.all(color: palette.border),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Text("Didn't receive the code?",
                                  style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryBlue,
                                  side: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
                                  minimumSize: const Size(0, 44),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                                ),
                                onPressed: (_canResend && !_resending) ? _onSendNewCode : null,
                                child: Text(
                                    _resending
                                        ? 'Sending...'
                                        : _canResend
                                            ? '📤 Send New Code'
                                            : 'Resend Code (${_countdownSeconds}s)',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Security info card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: palette.infoBg,
                      border: Border.all(color: AppColors.infoBlue),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration:
                                  BoxDecoration(color: AppColors.infoBlue, borderRadius: BorderRadius.circular(12)),
                              child: const Center(child: Text('🛡️', style: TextStyle(fontSize: 20))),
                            ),
                            const SizedBox(width: 12),
                            Text('Security Information',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: infoTitle)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final line in const [
                          '• Verification codes expire after 10 minutes',
                          "• Check your spam folder if you don't see the code",
                          '• Contact support if you continue having issues',
                        ]) ...[
                          Text(line, style: TextStyle(fontSize: 13, color: infoBody)),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
