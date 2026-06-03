import 'package:flutter/material.dart';
import '../../navigation/app_navigator.dart';
import '../../services/analytics_service.dart';
import '../../services/onboarding_state.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../child/child_app_shell.dart';
import '../child/child_invite_page.dart';
import '../child/child_waiting_page.dart';

/// Onboarding step 0 — parent vs child — port of `OnboardingRoleChoicePage.xaml`.
///
/// Persists the selection in [OnboardingState.role] (shown exactly once per
/// account). Parents continue through `advanceOnboarding`; children branch out
/// to the child invite/waiting/shell path, bypassing the parent paywall.
class RoleChoicePage extends StatefulWidget {
  const RoleChoicePage({super.key});

  @override
  State<RoleChoicePage> createState() => _RoleChoicePageState();
}

class _RoleChoicePageState extends State<RoleChoicePage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    OnboardingState.markStarted();
  }

  Future<void> _chooseParent() async {
    if (_busy) return;
    OnboardingState.role = 'parent';
    AnalyticsService.trackCustom('onboarding_role_parent');
    await advanceOnboarding(context);
  }

  Future<void> _chooseChild() async {
    if (_busy) return;
    OnboardingState.role = 'child';
    AnalyticsService.trackCustom('onboarding_role_child');
    setState(() => _busy = true);
    try {
      final childInvite = await ServiceLocator.auth.checkChildInvite();
      if (!mounted) return;
      Widget dest;
      if (childInvite.hasInvites && !childInvite.isAccepted && childInvite.invites.isNotEmpty) {
        dest = const ChildInvitePage();
      } else if (childInvite.hasInvites && childInvite.isAccepted) {
        dest = const ChildAppShell();
      } else {
        dest = const ChildWaitingPage();
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => dest),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error'),
          content: const Text('An error occurred. Please try again.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                // Hero
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(24)),
                  child: const Center(child: AppIcon('icon_users', size: 40, color: AppColors.primaryBlue)),
                ),
                const SizedBox(height: 12),
                Text('Welcome to CoHarmony',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 12),
                Text("Who's using this app?",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: palette.textSecondary)),
                const SizedBox(height: 32),

                // Parent card (gradient)
                _ChoiceCard(
                  onTap: _chooseParent,
                  gradient: const [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                  iconBg: const Color(0x33FFFFFF),
                  iconTint: Colors.white,
                  title: "I'm a Parent",
                  titleColor: Colors.white,
                  description: 'Set up custody schedules and co-parent with your partner.',
                  descriptionColor: const Color(0xFFE0E7FF),
                ),
                const SizedBox(height: 16),

                // Child card (surface)
                _ChoiceCard(
                  onTap: _chooseChild,
                  surfaceColor: palette.surfaceElevated,
                  iconBg: AppColors.iconBgPurple,
                  iconTint: AppColors.accentPurple,
                  title: "I'm a Child",
                  titleColor: palette.textPrimary,
                  description: "Join a family that's already using CoHarmony — it's free.",
                  descriptionColor: palette.textSecondary,
                ),
                  ],
                ),
              ),
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final VoidCallback onTap;
  final List<Color>? gradient;
  final Color? surfaceColor;
  final Color iconBg;
  final Color iconTint;
  final String title;
  final Color titleColor;
  final String description;
  final Color descriptionColor;

  const _ChoiceCard({
    required this.onTap,
    this.gradient,
    this.surfaceColor,
    required this.iconBg,
    required this.iconTint,
    required this.title,
    required this.titleColor,
    required this.description,
    required this.descriptionColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: surfaceColor,
          gradient: gradient != null
              ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient!)
              : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (gradient != null ? const Color(0xFF8B5CF6) : Colors.black)
                  .withValues(alpha: gradient != null ? 0.30 : (context.isDark ? 0.25 : 0.08)),
              offset: Offset(0, gradient != null ? 6 : 4),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(16)),
              child: Center(child: AppIcon('icon_users', size: 32, color: iconTint)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: titleColor)),
                  const SizedBox(height: 4),
                  Text(description, style: TextStyle(fontSize: 14, color: descriptionColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
