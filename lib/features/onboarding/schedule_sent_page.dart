import 'package:flutter/material.dart';
import '../../models/custody_models.dart';
import '../../navigation/app_navigator.dart';
import '../../services/analytics_service.dart';
import '../../services/onboarding_state.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/hero_orb.dart';
import 'onboarding_step_header.dart';
import 'proposal_preview_grid.dart';

/// Onboarding step 2.5 — "schedule sent" celebration — port of
/// `OnboardingScheduleSentPage.xaml(.cs)`.
///
/// Continue flips [OnboardingState.scheduleAcknowledged] so the router falls
/// through to subscription and never shows this page again. "Build a different
/// schedule" withdraws the active proposal, resets the flag, and re-enters the
/// router (which lands back on the template-apply step).
///
/// NOTE: the proposal-driven 4-week calendar preview is rendered by a shared
/// widget built during the schedule pass (reused by ScheduleReview + the editor);
/// the static preview card here is a placeholder until then.
class ScheduleSentPage extends StatefulWidget {
  const ScheduleSentPage({super.key});

  @override
  State<ScheduleSentPage> createState() => _ScheduleSentPageState();
}

class _ScheduleSentPageState extends State<ScheduleSentPage> {
  int? _proposalId;
  CustodyProposalDto? _proposal;
  String _subtitle = 'Your co-parent will be notified to review and respond.';
  bool _busy = false;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loadedOnce) return;
    _loadedOnce = true;
    // Personalize the subtitle with the partner email (best-effort).
    try {
      final info = await ServiceLocator.auth.getUserInfo();
      final partner = info?.partnerEmail;
      if (mounted && partner != null && partner.isNotEmpty) {
        setState(() => _subtitle = '$partner will be notified to review and respond.');
      }
    } catch (_) {/* default subtitle is fine */}
    // Fetch the active proposal so Redo can withdraw it + the preview can render.
    try {
      final active = await ServiceLocator.custodyProposal.getActiveProposal();
      if (mounted) {
        setState(() {
          _proposal = active?.proposal;
          _proposalId = active?.proposal?.proposalId;
        });
      }
    } catch (_) {/* preview/withdraw simply unavailable */}
  }

  Future<void> _continue() async {
    if (_busy) return;
    OnboardingState.scheduleAcknowledged = true;
    AnalyticsService.trackCustom('onboarding_schedule_acknowledged');
    await advanceOnboarding(context);
  }

  Future<void> _redo() async {
    if (_busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Build a different schedule?'),
        content: const Text(
            "We'll withdraw this proposal so your co-parent doesn't see it, and bring you back to "
            'pick a new starting point. You can always make smaller tweaks later from the Schedule tab.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep this one')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes, start over')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final id = _proposalId;
      if (id != null) {
        await ServiceLocator.custodyProposal.withdrawProposal(id);
      }
      // Reset the schedule step so the new submission routes through here again.
      OnboardingState.scheduleAcknowledged = false;
      AnalyticsService.trackCustom('onboarding_schedule_redo');
      if (!mounted) return;
      await advanceOnboarding(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Couldn't withdraw"),
          content: Text('$e'),
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
          Column(
            children: [
              const OnboardingStepHeader(step: 2, labelOverride: 'STEP 2 OF 3 COMPLETE'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        children: [
                          const HeroOrb(
                            gradient: [Color(0xFF10B981), Color(0xFF059669)],
                            haloSize: 140,
                            coreSize: 96,
                            coreRadius: 32,
                            child: Text('✓',
                                style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                          const SizedBox(height: 18),
                          Text('Schedule sent!',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                          const SizedBox(height: 8),
                          Text(_subtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15, color: palette.textSecondary)),
                          const SizedBox(height: 24),

                          // Schedule preview card
                          _card(
                            context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Your schedule',
                                              style: TextStyle(
                                                  fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                                          const SizedBox(height: 3),
                                          Text('Repeating pattern',
                                              style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                                        ],
                                      ),
                                    ),
                                    _chip('Dad', const Color(0xFFBFDBFE), const Color(0xFF1E40AF)),
                                    const SizedBox(width: 6),
                                    _chip('Mom', const Color(0xFFFCE7F3), const Color(0xFFBE185D)),
                                  ],
                                ),
                                if (_proposal != null) ...[
                                  const SizedBox(height: 16),
                                  ProposalPreviewGrid(
                                    patternLength: _proposal!.patternLength,
                                    days: _proposal!.days,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // What happens next
                          _card(
                            context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('What happens next',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                                const SizedBox(height: 16),
                                _nextRow(context, '✓', AppColors.iconBgGreen, AppColors.successGreen, 'If they accept',
                                    "The schedule goes live for both of you. You'll see it in the Schedule tab."),
                                const SizedBox(height: 14),
                                _nextRow(
                                    context,
                                    '↻',
                                    context.isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
                                    AppColors.warningAmber,
                                    'If they want changes',
                                    "They can counter-propose. You'll get a notification to review their changes."),
                                const SizedBox(height: 14),
                                _nextRow(context, '⚙', AppColors.iconBgBlue, AppColors.primaryBlue, 'Anytime later',
                                    'You can tweak the schedule, add holidays, or build a new pattern from the Schedule tab.'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Redo link
                          GestureDetector(
                            onTap: _redo,
                            child: Column(
                              children: [
                                Text('Not quite right?', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                                const SizedBox(height: 6),
                                const Text('↻  Build a different schedule',
                                    style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Footer
              Container(
                width: double.infinity,
                color: palette.background,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                child: GestureDetector(
                  onTap: _continue,
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primaryBlue.withValues(alpha: 0.35),
                            offset: const Offset(0, 6),
                            blurRadius: 12),
                      ],
                    ),
                    child: const Center(
                      child: Text('Continue to Subscription',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.palette.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.06),
                offset: const Offset(0, 4),
                blurRadius: 16),
          ],
        ),
        child: child,
      );

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
      );

  Widget _nextRow(BuildContext context, String glyph, Color bg, Color fg, String title, String body) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(glyph, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: fg))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const SizedBox(height: 2),
              Text(body, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
