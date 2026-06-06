import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import 'account_creation_page.dart';
import 'login_page.dart';
import 'sso_buttons.dart';

/// Landing / welcome screen — faithful port of `Views/Login/MainPage.xaml`.
/// Hero (logo + welcome card with three feature rows) over a pinned bottom
/// action panel (Sign In / Create Account).
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          // ── Hero content ──────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, MediaQuery.viewPaddingOf(context).top + 24, 24, 32),
              child: Column(
                children: [
                  // Logo card
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: palette.surfaceElevated,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: (context.isDark ? Colors.black : Colors.black)
                                .withValues(alpha: context.isDark ? 0.25 : 0.10),
                            offset: const Offset(0, 12),
                            blurRadius: 32,
                          ),
                        ],
                      ),
                      child: SvgPicture.asset(
                        'assets/images/logo.svg',
                        width: 160,
                        height: 160,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Welcome card
                  Container(
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
                      children: [
                        Text(
                          'Welcome to CoHarmony™',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Your family coordination platform',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, color: palette.textSecondary),
                        ),
                        const SizedBox(height: 20),
                        Container(height: 1, color: palette.border, margin: const EdgeInsets.symmetric(vertical: 8)),
                        const SizedBox(height: 12),
                        _FeatureRow(
                          icon: 'icon_calendar',
                          iconBg: AppColors.iconBgBlue,
                          iconTint: AppColors.primaryBlue,
                          title: 'Schedule Management',
                          subtitle: 'Coordinate custody schedules',
                        ),
                        const SizedBox(height: 16),
                        _FeatureRow(
                          icon: 'icon_chat',
                          iconBg: AppColors.iconBgGreen,
                          iconTint: AppColors.successGreen,
                          title: 'Secure Messaging',
                          subtitle: 'Encrypted family communication',
                        ),
                        const SizedBox(height: 16),
                        _FeatureRow(
                          icon: 'icon_money',
                          iconBg: AppColors.iconBgYellow,
                          iconTint: AppColors.warningAmber,
                          title: 'Financial Management',
                          subtitle: 'Track expenses and payments',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom action panel ───────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 40 + MediaQuery.viewPaddingOf(context).bottom),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // One-tap SSO (find-or-create, so no need to pick login vs signup)
                const SsoButtons(),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: Divider(color: palette.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or',
                          style: TextStyle(color: palette.textSecondary, fontSize: 13)),
                    ),
                    Expanded(child: Divider(color: palette.border)),
                  ],
                ),
                const SizedBox(height: 18),
                // Sign In (gradient)
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  },
                  child: Container(
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [AppColors.primaryBlue, AppColors.primaryBlueLight],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.35),
                          offset: const Offset(0, 6),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon('icon_lock', size: 20, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Sign In',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Create Account (outlined)
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountCreationPage()),
                    );
                  },
                  child: Container(
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: palette.border, width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon('icon_sparkle', size: 20, color: palette.textSecondary),
                        const SizedBox(width: 8),
                        Text('Create Account',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold, color: palette.textSecondary)),
                      ],
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
}

class _FeatureRow extends StatelessWidget {
  final String icon;
  final Color iconBg;
  final Color iconTint;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.iconBg,
    required this.iconTint,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceInput,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
            child: Center(child: AppIcon(icon, size: 28, color: iconTint)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
