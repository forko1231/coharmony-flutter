import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';
import '../../services/custody_templates/pending_template_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/hero_orb.dart';
import '../ai/ai_chat_page.dart';
import '../schedule/custody_schedule_page.dart';
import '../schedule/templates/template_catalog_page.dart';
import 'onboarding_step_header.dart';

/// Onboarding step 2 — choose how to build the schedule — port of
/// `OnboardingTemplateApplyPage.xaml(.cs)`. Template card, AI card, build-from-scratch link.
///
/// All three paths open a builder that, on apply/save, creates the proposal and
/// re-enters the onboarding router. That onboarding-mode save routing (MAUI's
/// `PendingTemplateService.IsOnboardingMode`) lands in the schedule/template pass;
/// here we wire the navigations + analytics faithfully.
class TemplateApplyPage extends StatefulWidget {
  const TemplateApplyPage({super.key});

  @override
  State<TemplateApplyPage> createState() => _TemplateApplyPageState();
}

class _TemplateApplyPageState extends State<TemplateApplyPage> {
  @override
  void initState() {
    super.initState();
    // Same as MAUI's OnboardingTemplateApplyPage ctor: clear stale state and flag
    // onboarding mode so the template-apply / build-from-scratch paths create the
    // proposal and route back through the onboarding router (rather than popping to
    // the editor).
    PendingTemplateService.clear();
    PendingTemplateService.isOnboardingMode = true;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          const OnboardingStepHeader(step: 2),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      const HeroOrb(gradient: [Color(0xFF10B981), Color(0xFF059669)], icon: 'icon_calendar'),
                      const SizedBox(height: 20),
                      Text('Build your schedule',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 10),
                      Text('Pick the path that fits. Most parents start with a template — it takes about a minute.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, color: palette.textSecondary)),
                      const SizedBox(height: 32),

                      // Template card
                      _OptionCard(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const TemplateCatalogPage()),
                          );
                        },
                        surfaceColor: palette.surfaceElevated,
                        iconGradient: const [Color(0xFF10B981), Color(0xFF059669)],
                        icon: 'icon_calendar',
                        title: 'Pick a template',
                        titleColor: palette.textPrimary,
                        badge: 'POPULAR',
                        badgeBg: AppColors.iconBgGreen,
                        badgeFg: AppColors.successGreen,
                        description: '8 common patterns — 50/50, every other weekend, and more.',
                        descriptionColor: palette.textSecondary,
                        chevronColor: palette.textSecondary,
                      ),
                      const SizedBox(height: 14),

                      // AI card (gradient)
                      _OptionCard(
                        onTap: () {
                          AnalyticsService.trackCustom('onboarding_ai_path_opened');
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AiChatPage(chatContext: 'onboarding-schedule')),
                          );
                        },
                        cardGradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFEC4899)],
                        iconBgColor: const Color(0x40FFFFFF),
                        icon: 'icon_sparkle',
                        title: 'Describe it to AI',
                        titleColor: Colors.white,
                        badge: 'NEW',
                        badgeBg: const Color(0x33FFFFFF),
                        badgeFg: Colors.white,
                        description: 'Tell it your routine in plain English — it builds the schedule.',
                        descriptionColor: const Color(0xFFF3E8FF),
                        chevronColor: Colors.white,
                      ),
                      const SizedBox(height: 32),

                      GestureDetector(
                        onTap: () {
                          AnalyticsService.trackCustom('onboarding_manual_build_chosen');
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const CustodySchedulePage()),
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Build from scratch',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                            const SizedBox(width: 8),
                            Text('(advanced)', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                          ],
                        ),
                      ),
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
}

class _OptionCard extends StatelessWidget {
  final VoidCallback onTap;
  final Color? surfaceColor;
  final List<Color>? cardGradient;
  final List<Color>? iconGradient;
  final Color? iconBgColor;
  final String icon;
  final String title;
  final Color titleColor;
  final String badge;
  final Color badgeBg;
  final Color badgeFg;
  final String description;
  final Color descriptionColor;
  final Color chevronColor;

  const _OptionCard({
    required this.onTap,
    this.surfaceColor,
    this.cardGradient,
    this.iconGradient,
    this.iconBgColor,
    required this.icon,
    required this.title,
    required this.titleColor,
    required this.badge,
    required this.badgeBg,
    required this.badgeFg,
    required this.description,
    required this.descriptionColor,
    required this.chevronColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: surfaceColor,
          gradient: cardGradient != null
              ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cardGradient!)
              : null,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: (cardGradient != null ? const Color(0xFF8B5CF6) : Colors.black)
                  .withValues(alpha: cardGradient != null ? 0.35 : (context.isDark ? 0.5 : 0.08)),
              offset: Offset(0, cardGradient != null ? 8 : 6),
              blurRadius: 18,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconBgColor,
                gradient: iconGradient != null
                    ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: iconGradient!)
                    : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(child: AppIcon(icon, size: 28, color: Colors.white)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(8)),
                        child: Text(badge,
                            style: TextStyle(
                                fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1, color: badgeFg)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: TextStyle(fontSize: 13, color: descriptionColor)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text('›', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: chevronColor)),
          ],
        ),
      ),
    );
  }
}
