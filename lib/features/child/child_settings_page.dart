import 'package:flutter/material.dart';
import '../../models/auth_models.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_icon.dart';
import '../auth/landing_page.dart';

/// Port of `Views/Child/ChildSettingsPage.xaml(.cs)` — account overview (with a
/// "Child Account" badge), an app-theme picker (persisted via [ThemeController]), and a
/// danger zone: log out, or leave family (`removeChildStatus` → converts back to a
/// normal account → signs out).
class ChildSettingsPage extends StatefulWidget {
  const ChildSettingsPage({super.key});

  @override
  State<ChildSettingsPage> createState() => _ChildSettingsPageState();
}

class _ChildSettingsPageState extends State<ChildSettingsPage> {
  String _theme = ThemeController.label;
  UserInfo? _info;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      _info = await ServiceLocator.auth.getUserInfo();
    } catch (_) {
      // fall back to the email preference
    } finally {
      if (mounted) setState(() {});
    }
  }

  String get _name {
    final n = '${_info?.firstName ?? ''} ${_info?.lastName ?? ''}'.trim();
    return n.isNotEmpty ? n : 'Unknown';
  }

  String get _email => _info?.email ?? Preferences.getString('email', '');

  Future<void> _signOut() async {
    final confirm = await _confirm('Sign Out', 'Are you sure you want to sign out?', 'Yes');
    if (confirm != true || !mounted) return;
    // AuthService.logout() centralizes the full cleanup (WebSocket, push
    // unregistration, encryption keys, Preferences.clear()).
    await ServiceLocator.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }

  Future<void> _leaveFamily() async {
    final confirm = await _confirm(
        'Leave Family',
        'This will remove your child account status and convert your account back to a normal account. '
            'You will lose access to the family schedule and messages.\n\nAre you sure?',
        'Leave Family');
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final ok = await ServiceLocator.auth.removeChildStatus();
      if (ok) {
        if (!mounted) return;
        await _alert('Done', 'Your account has been converted back to a normal account. You will be signed out.');
        // Centralized cleanup (including Preferences.clear()) lives in logout().
        await ServiceLocator.auth.logout();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LandingPage()),
          (route) => false,
        );
      } else {
        if (mounted) {
          setState(() => _busy = false);
          await _alert('Error', 'Could not remove child status. Please try again.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        await _alert('Error', 'Something went wrong. Please try again.');
      }
    }
  }

  Future<void> _alert(String title, String message) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );

  Future<bool?> _confirm(String title, String message, String confirmLabel) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(confirmLabel)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Column(
            children: [
              _header(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _accountCard(context),
                          const SizedBox(height: 24),
                          _appSettings(context),
                          const SizedBox(height: 24),
                          _dangerZone(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      // Top inset accounts for the status bar / Dynamic Island.
      padding: EdgeInsets.fromLTRB(16, MediaQuery.viewPaddingOf(context).top + 12, 16, 16),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
              offset: const Offset(0, 4),
              blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: AppIcon('icon_chevron_left', size: 24, color: palette.textSecondary)),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text('Settings',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text('Manage your account', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) {
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

  Widget _accountCard(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      Row(
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
                Text(_name,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text(_email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.accentPurple, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Child Account',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _appSettings(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.iconBgGreen, borderRadius: BorderRadius.circular(12)),
                child: const Center(child: AppIcon('icon_gear', size: 22, color: AppColors.successGreen)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('App Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    Text('Customize your app experience',
                        style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(16)),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.isDark ? const Color(0xFF374151) : palette.surface,
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
                        ThemeController.setLabel(label);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dangerZone(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.iconBgRed, borderRadius: BorderRadius.circular(12)),
                child: const Center(child: AppIcon('icon_warning', size: 22, color: AppColors.dangerRed)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Danger Zone',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    Text('Account actions', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _dangerButton(context, 'icon_logout', 'Log Out', palette.textSecondary, _signOut),
          const SizedBox(height: 12),
          _dangerButton(context, 'icon_trash', 'Leave Family', AppColors.dangerRed, _leaveFamily),
        ],
      ),
    );
  }

  Widget _dangerButton(BuildContext context, String icon, String label, Color bg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
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
}
