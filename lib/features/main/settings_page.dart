import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/auth_models.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_icon.dart';
import '../auth/landing_page.dart';
import '../auth/reset_password_page.dart';
import '../auth/verify_mfa_page.dart';
import '../auth/verify_password_page.dart';
import 'export_data_page.dart';
import 'partner_page.dart';

/// Settings — port of `Views/Main/Settings.xaml`. Account overview, personal
/// information (email/password), app settings (theme/notifications/tutorial),
/// connections, data export, and a danger zone. All actions are wired in phase 2.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifications = true;
  String _theme = ThemeController.label;
  UserInfo? _info;
  bool _loadingInfo = true;

  @override
  void initState() {
    super.initState();
    _notifications = Preferences.getBool('notifications_enabled', true);
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      _info = await ServiceLocator.auth.getUserInfo();
    } catch (_) {
      // leave null; UI falls back to the email preference
    } finally {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  String get _displayName {
    final f = _info?.firstName ?? '';
    final l = _info?.lastName ?? '';
    final name = '$f $l'.trim();
    return name.isNotEmpty ? name : 'Your Account';
  }

  String get _email => _info?.email ?? Preferences.getString('email', 'Not signed in');

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          AppHeader(
            title: 'Settings',
            subtitle: 'Manage your account and preferences',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _accountOverview(context),
                      const SizedBox(height: 24),
                      _personalInfo(context),
                      const SizedBox(height: 24),
                      _appSettings(context),
                      const SizedBox(height: 24),
                      _connections(context),
                      const SizedBox(height: 24),
                      _dataExport(context),
                      const SizedBox(height: 24),
                      _dangerZone(context),
                      const SizedBox(height: 24),
                      _versionInfo(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Account overview ───────────────────────────────────────────────────────
  Widget _accountOverview(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(18)),
            child: const Center(child: AppIcon('icon_user', size: 28, color: Colors.white)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_loadingInfo ? 'Account Overview' : _displayName,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 4),
                Text(_loadingInfo ? 'Loading user information...' : _email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Personal information ─────────────────────────────────────────────────────
  Widget _personalInfo(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(context,
              icon: 'icon_clipboard',
              iconBg: AppColors.iconBgBlue,
              iconTint: AppColors.primaryBlue,
              title: 'Personal Information',
              subtitle: 'Manage your account details'),
          const SizedBox(height: 20),
          // Email
          _inputBox(
            context,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email Address',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 8),
                      Text(_email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                      const SizedBox(height: 8),
                      if (_info?.emailConfirmed ?? false)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(color: AppColors.successGreen, borderRadius: BorderRadius.circular(8)),
                              child: Center(
                                  child: Container(
                                      width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
                            ),
                            const SizedBox(width: 8),
                            const Text('Verified', style: TextStyle(fontSize: 12, color: AppColors.successGreen)),
                          ],
                        )
                      else
                        const Text('Not verified', style: TextStyle(fontSize: 12, color: AppColors.warningAmber)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _pillButton(context, 'Change', AppColors.primaryBlue, _changeEmail),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Password
          _inputBox(
            context,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Password',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 8),
                      Text('••••••••••••',
                          style: TextStyle(fontSize: 14, fontFamily: 'monospace', color: palette.textSecondary)),
                      const SizedBox(height: 4),
                      Text('Last changed: Never', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _pillButton(context, 'Change', AppColors.primaryBlue, _changePassword),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── App settings ─────────────────────────────────────────────────────────────
  Widget _appSettings(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(context,
              icon: 'icon_gear',
              iconBg: AppColors.iconBgGreen,
              iconTint: AppColors.successGreen,
              title: 'App Settings',
              subtitle: 'Customize your app experience'),
          const SizedBox(height: 20),
          // Theme
          _inputBox(
            context,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('App Theme',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Choose between light and dark mode',
                          style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.isDark ? const Color(0xFF374151) : palette.surface,
                    border: Border.all(color: context.isDark ? const Color(0xFF4B5563) : palette.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _theme,
                      isDense: true,
                      dropdownColor: palette.surfaceElevated,
                      style: TextStyle(fontSize: 14, color: palette.textPrimary),
                      items: const [
                        DropdownMenuItem(value: 'System', child: Text('System')),
                        DropdownMenuItem(value: 'Light', child: Text('Light')),
                        DropdownMenuItem(value: 'Dark', child: Text('Dark')),
                      ],
                      onChanged: (v) {
                        final label = v ?? 'System';
                        setState(() => _theme = label);
                        ThemeController.setLabel(label); // persists + applies app-wide
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Notifications
          _inputBox(
            context,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notifications',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Receive app notifications',
                          style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                    ],
                  ),
                ),
                Switch(
                  value: _notifications,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.primaryBlue,
                  onChanged: (v) {
                    setState(() => _notifications = v);
                    Preferences.setBool('notifications_enabled', v);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Connections ──────────────────────────────────────────────────────────────
  Widget _connections(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(context,
              icon: 'icon_users',
              iconBg: AppColors.iconBgPurple,
              iconTint: AppColors.accentPurple,
              title: 'Connections',
              subtitle: 'Manage partner & legal representatives'),
          const SizedBox(height: 20),
          _inputBox(
            context,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PartnerPage()),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Partner & Lawyers',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 4),
                      Text('View and manage your connections',
                          style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _openButton(context, AppColors.accentPurple),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Data export ──────────────────────────────────────────────────────────────
  Widget _dataExport(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(context,
              icon: 'icon_export',
              iconBg: AppColors.iconBgCyan,
              iconTint: AppColors.infoBlue,
              title: 'Data Export',
              subtitle: 'Download your data as PDF reports'),
          const SizedBox(height: 20),
          _inputBox(
            context,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExportDataPage()),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Export Reports',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Custody, payments, messages & more',
                          style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _openButton(context, AppColors.primaryBlue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Danger zone ──────────────────────────────────────────────────────────────
  Widget _dangerZone(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(context,
              icon: 'icon_warning',
              iconBg: AppColors.iconBgRed,
              iconTint: AppColors.dangerRed,
              title: 'Danger Zone',
              subtitle: 'Risky actions that can affect your account'),
          const SizedBox(height: 20),
          _dangerButton(context, 'icon_logout', 'Log Out', palette.textSecondary, () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Log Out'),
                content: const Text('Are you sure you want to log out?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Log Out')),
                ],
              ),
            );
            if (confirmed != true) return;
            await ServiceLocator.auth.logout();
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LandingPage()),
              (route) => false,
            );
          }),
          const SizedBox(height: 12),
          _dangerButton(context, 'icon_trash', 'Delete Account', AppColors.dangerRed, _deleteAccount),
        ],
      ),
    );
  }

  // ── Account actions (re-auth + MFA gated) ────────────────────────────────

  /// Push the re-auth page and return the verified current password (or null).
  Future<String?> _reauth() async {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const VerifyPasswordPage()),
    );
  }

  /// Run the SecureAction MFA gate; resolves true once the code is verified.
  /// The MFA page pops itself on success, so awaiting the push is sufficient.
  Future<bool> _secureActionMfa(
      {required String email, required bool phoneConfirmed, required String password}) async {
    var verified = false;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerifyMfaPage(
          identifier: email,
          password: password,
          purpose: VerificationPurpose.secureAction,
          method: phoneConfirmed ? MfaMethod.sms : MfaMethod.email,
          onComplete: (s) => verified = s,
        ),
      ),
    );
    return verified;
  }

  Future<void> _changeEmail() async {
    final password = await _reauth();
    if (password == null || password.isEmpty || !mounted) return;

    final newEmail = await _promptEmail(Preferences.getString('email'));
    if (newEmail == null || !mounted) return;
    if (!_isValidEmail(newEmail)) {
      await _alert('Invalid Email', 'Please enter a valid email address.');
      return;
    }

    // SECURITY: server requires the verified current password for an email change.
    await ServiceLocator.auth.updateUserInfo(newEmail: newEmail, currentPassword: password);
    await Preferences.setString('email', newEmail);
    if (!mounted) return;

    await _alert('Verification Required', 'Please verify your new email address.');
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerifyMfaPage(
          identifier: newEmail,
          password: password,
          purpose: VerificationPurpose.changeEmail,
          method: MfaMethod.email,
          forceMethod: true,
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    final password = await _reauth();
    if (password == null || password.isEmpty || !mounted) return;

    final info = await ServiceLocator.auth.getUserInfo();
    if (info == null || !mounted) return;

    final verified = await _secureActionMfa(
        email: info.email ?? '', phoneConfirmed: info.phoneNumConfirmed, password: password);
    if (!verified || !mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResetPasswordPage.changePassword(currentPassword: password),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirm = await _confirm(
        'Delete Account',
        'Are you sure you want to delete your account? This action cannot be undone.',
        'Delete');
    if (confirm != true || !mounted) return;

    final password = await _reauth();
    if (password == null || password.isEmpty || !mounted) return;

    final info = await ServiceLocator.auth.getUserInfo();
    if (info == null || !mounted) return;

    final verified = await _secureActionMfa(
        email: info.email ?? '', phoneConfirmed: info.phoneNumConfirmed, password: password);
    if (!verified || !mounted) return;

    final deleted = await ServiceLocator.auth.deleteUserData('account');
    if (!mounted) return;
    if (deleted) {
      await _alert('Account Deleted', 'Your account has been successfully deleted.');
      await Preferences.clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingPage()),
        (route) => false,
      );
    } else {
      await _alert('Error', 'Failed to delete your account. Please try again later.');
    }
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  Future<String?> _promptEmail(String initial) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Email'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Please enter your new email address:'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String title, String message, String confirmLabel) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(confirmLabel)),
        ],
      ),
    );
  }

  Future<void> _alert(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _dangerButton(BuildContext context, String icon, String label, Color bg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: bg.withValues(alpha: 0.3), offset: const Offset(0, 4), blurRadius: 8),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  // ── Version info ─────────────────────────────────────────────────────────────
  Widget _versionInfo(BuildContext context) {
    final headerColor = context.isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1);
    final subColor = context.isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.isDark ? AppColors.infoBgDark : AppColors.infoBgLight,
        border: Border.all(color: AppColors.infoBlue),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.infoBlue, borderRadius: BorderRadius.circular(12)),
            child: const Center(child: AppIcon('icon_info', size: 22, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('App Information',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: headerColor)),
                const SizedBox(height: 2),
                Text('Version 1.0.0 • CoHarmony™ Family Coordination',
                    style: TextStyle(fontSize: 13, color: subColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared building blocks ───────────────────────────────────────────────────
  Widget _card(BuildContext context, {required Widget child}) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
              offset: const Offset(0, 8),
              blurRadius: 24),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader(BuildContext context,
      {required String icon,
      required Color iconBg,
      required Color iconTint,
      required String title,
      required String subtitle}) {
    final palette = context.palette;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
          child: Center(child: AppIcon(icon, size: 22, color: iconTint)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _inputBox(BuildContext context, {required Widget child, VoidCallback? onTap}) {
    final palette = context.palette;
    final box = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceInput,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(onTap: onTap, child: box);
  }

  Widget _pillButton(BuildContext context, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), offset: const Offset(0, 2), blurRadius: 4)],
        ),
        child: Center(
          child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }

  Widget _openButton(BuildContext context, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Open', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          SizedBox(width: 4),
          AppIcon('icon_arrow_right', size: 14, color: Colors.white),
        ],
      ),
    );
  }
}
