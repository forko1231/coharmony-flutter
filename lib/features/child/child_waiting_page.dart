import 'package:flutter/material.dart';
import '../../navigation/app_navigator.dart';
import '../../services/onboarding_state.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../auth/landing_page.dart';
import 'child_app_shell.dart';
import 'child_invite_page.dart';

/// Port of `Views/Child/ChildWaitingPage.xaml(.cs)` — shown to a child account not yet
/// added to a family. Refresh re-checks for an invite (→ invite page, or → ChildAppShell
/// if already accepted); "I'm not a child" clears the role and re-routes onboarding.
class ChildWaitingPage extends StatefulWidget {
  const ChildWaitingPage({super.key});

  @override
  State<ChildWaitingPage> createState() => _ChildWaitingPageState();
}

class _ChildWaitingPageState extends State<ChildWaitingPage> {
  bool _busy = false;
  String _status = 'Ask a parent to add you to their family. Once they do, your invite will show up here.';

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final invite = await ServiceLocator.auth.checkChildInvite();
      if (invite.hasInvites && !invite.isAccepted) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ChildInvitePage()),
          (route) => false,
        );
        return;
      } else if (invite.hasInvites && invite.isAccepted) {
        await Preferences.setString('AccountType', 'child');
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ChildAppShell()),
          (route) => false,
        );
        return;
      } else {
        setState(() => _status = 'No invite found yet. Ask a parent to add your account.');
      }
    } catch (_) {
      setState(() => _status = 'Error checking for invites. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Changed their mind about being a child — clear the role so the router sends them
  /// back to role choice.
  Future<void> _notAChild() async {
    OnboardingState.role = '';
    await advanceOnboarding(context);
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await ServiceLocator.auth.logout();
    await Preferences.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(color: AppColors.iconBgPurple, borderRadius: BorderRadius.circular(24)),
                        child: const Center(child: AppIcon('icon_users', size: 40, color: AppColors.accentPurple)),
                      ),
                      const SizedBox(height: 12),
                      Text('Waiting to Join a Family',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 8),
                      Text(_status,
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: palette.textSecondary)),
                      const SizedBox(height: 24),
                      _instructions(context),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        onPressed: _refresh,
                        child: const Text('Refresh', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.textSecondary,
                          side: BorderSide(color: palette.border),
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        onPressed: _notAChild,
                        child: const Text("I'm not a child", style: TextStyle(fontSize: 14)),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _signOut,
                        child: Text('Sign Out', style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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

  Widget _instructions(BuildContext context) {
    final palette = context.palette;
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(10)),
                child: Center(
                    child: Text(n,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryBlue))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: palette.textSecondary))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.12),
              offset: const Offset(0, 8),
              blurRadius: 24),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to Get Added',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          const SizedBox(height: 20),
          step('1', 'Ask a parent to open CoHarmony and go to Connections.'),
          step('2', "In the Family section, they'll enter your email address to add you."),
          step('3', 'Once added, tap Refresh below to see your invite and accept it.'),
        ],
      ),
    );
  }
}
