import 'package:flutter/material.dart';
import '../../models/auth_models.dart';
import '../../navigation/app_navigator.dart';
import '../../services/analytics_service.dart';
import '../../services/onboarding_state.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../auth/landing_page.dart';
import 'child_app_shell.dart';

/// Port of `Views/Child/ChildInvitePage.xaml(.cs)` — shown when a child has pending
/// family invitation(s). Loads invites, lets the child accept (→ ChildAppShell) or
/// decline (→ re-route through onboarding when none remain).
class ChildInvitePage extends StatefulWidget {
  const ChildInvitePage({super.key});

  @override
  State<ChildInvitePage> createState() => _ChildInvitePageState();
}

class _ChildInvitePageState extends State<ChildInvitePage> {
  bool _loading = true;
  bool _busy = false;
  String _busyLabel = '';
  List<ChildInviteInfo> _invites = const [];

  static const _benefits = [
    'View the family custody schedule',
    'Message either parent',
    'See your family members',
    'Completely free — no subscription needed',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final resp = await ServiceLocator.auth.checkChildInvite();
      _invites = resp.hasInvites ? resp.invites : const [];
    } catch (_) {
      _invites = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(ChildInviteInfo invite) async {
    final parentName = invite.parentName ?? 'Unknown';
    var msg = 'You are about to join the family of:\n\nParent: $parentName';
    if (invite.otherParentName?.isNotEmpty ?? false) msg += '\nOther Parent: ${invite.otherParentName}';
    msg += "\n\nYou'll have access to the family custody schedule and can message either parent. "
        'This action can be reversed later from settings.\n\nAre you sure you want to join this family?';
    final confirm = await _confirm('Confirm Join Family', msg, 'Yes, Join Family');
    if (confirm != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyLabel = 'Joining family...';
    });
    try {
      final ok = await ServiceLocator.auth.acceptChildInvite(invite.parentEmail ?? '');
      if (ok) {
        AnalyticsService.trackChildJoined();
        await Preferences.setString('AccountType', 'child');
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ChildAppShell()),
          (route) => false,
        );
      } else {
        if (mounted) {
          setState(() => _busy = false);
          await _alert('Error', 'Failed to accept the invitation. Please try again.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        await _alert('Error', 'An error occurred. Please try again.');
      }
    }
  }

  Future<void> _decline(ChildInviteInfo invite) async {
    final parentName = invite.parentName ?? invite.parentEmail ?? 'this parent';
    final confirm = await _confirm('Decline Invitation',
        "Are you sure you want to decline the invitation from $parentName's family?\n\nYou can always be re-invited later.",
        'Decline');
    if (confirm != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyLabel = 'Declining invite...';
    });
    try {
      final ok = await ServiceLocator.auth.declineChildInvite(invite.parentEmail ?? '');
      if (!ok) {
        if (mounted) {
          setState(() => _busy = false);
          await _alert('Error', 'Failed to decline the invitation. Please try again.');
        }
        return;
      }
      final updated = await ServiceLocator.auth.checkChildInvite();
      if (!updated.hasInvites || updated.invites.isEmpty) {
        await _leaveChildRole();
      } else {
        if (mounted) {
          setState(() {
            _invites = updated.invites;
            _busy = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        await _alert('Error', 'An error occurred. Please try again.');
      }
    }
  }

  Future<void> _declineAll() async {
    final confirm = await _confirm('Decline All Invitations',
        'Are you sure you want to decline all family invitations? You can always be re-invited later.', 'Decline All');
    if (confirm != true || !mounted) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Declining all invites...';
    });
    try {
      for (final invite in List<ChildInviteInfo>.from(_invites)) {
        await ServiceLocator.auth.declineChildInvite(invite.parentEmail ?? '');
      }
      await _leaveChildRole();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        await _alert('Error', 'An error occurred. Please try again.');
      }
    }
  }

  /// Declined every invite — they aren't a child here after all. Clear the role and
  /// let the onboarding router send them back to role choice.
  Future<void> _leaveChildRole() async {
    await Preferences.setString('AccountType', '');
    OnboardingState.role = '';
    if (mounted) await advanceOnboarding(context);
  }

  Future<void> _signOut() async {
    final confirm = await _confirm('Sign Out', 'Are you sure you want to sign out?', 'Sign Out');
    if (confirm != true || !mounted) return;
    await ServiceLocator.auth.logout();
    await Preferences.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
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
    final multiple = _invites.length > 1;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
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
                              decoration: BoxDecoration(color: AppColors.iconBgGreen, borderRadius: BorderRadius.circular(24)),
                              child: const Center(child: AppIcon('icon_users', size: 40, color: AppColors.successGreen)),
                            ),
                            const SizedBox(height: 12),
                            Text("You've Been Invited!",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                            const SizedBox(height: 8),
                            Text(
                                multiple
                                    ? 'You have ${_invites.length} family invitations. Choose which family to join.'
                                    : 'A parent has invited you to join their family on CoHarmony.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, color: palette.textSecondary)),
                            const SizedBox(height: 24),
                            if (_invites.isEmpty)
                              Text('No invitations were found for your account.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 15, color: palette.textSecondary))
                            else
                              for (final inv in _invites) ...[
                                _inviteCard(context, inv),
                                const SizedBox(height: 16),
                              ],
                            _benefitsCard(context),
                            if (multiple) ...[
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _declineAll,
                                child: const Text('Decline All', style: TextStyle(fontSize: 14, color: AppColors.dangerRed)),
                              ),
                            ],
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
                color: Colors.black.withValues(alpha: 0.4),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(_busyLabel, style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _inviteCard(BuildContext context, ChildInviteInfo inv) {
    final palette = context.palette;
    final family = (inv.parentName?.isNotEmpty ?? false) ? "${inv.parentName}'s Family" : 'Family Invitation';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(family, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          if (inv.parentName?.isNotEmpty ?? false) ...[
            const SizedBox(height: 4),
            _detailRow(context, 'Parent:', inv.parentName!),
          ],
          if (inv.otherParentName?.isNotEmpty ?? false) ...[
            const SizedBox(height: 4),
            _detailRow(context, 'Other Parent:', inv.otherParentName!),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerRed,
                    side: const BorderSide(color: AppColors.dangerRed),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: () => _decline(inv),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.successGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: () => _accept(inv),
                  child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    final palette = context.palette;
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textSecondary)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: palette.textPrimary))),
      ],
    );
  }

  Widget _benefitsCard(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("What You'll Have Access To",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          const SizedBox(height: 16),
          for (final b in _benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: const BoxDecoration(color: AppColors.successGreen, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(b, style: TextStyle(fontSize: 14, color: palette.textSecondary))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
