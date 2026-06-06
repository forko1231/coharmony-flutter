import 'package:flutter/material.dart';
import '../../models/custody_models.dart';
import '../../navigation/app_navigator.dart';
import '../../services/analytics_service.dart';
import '../../services/custody_templates/pending_template_service.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/hero_orb.dart';
import '../schedule/custody_schedule_page.dart';
import 'onboarding_step_header.dart';
import 'proposal_preview_grid.dart';

/// Onboarding step 2 — review a co-parent's proposed schedule — port of
/// `OnboardingScheduleReviewPage.xaml(.cs)`.
///
/// Loads the active proposal, shows a plain-English summary, and offers
/// Accept / Suggest-changes (counter) / Reject. Accept and Reject call the
/// proposal service and advance the router; counter / "see full details" open
/// the full editor (which carries the onboarding save-routing — wired in the
/// schedule pass).
///
/// NOTE: the 4-week calendar preview is rendered by the shared proposal-preview
/// widget built during the schedule pass; the legend + placeholder remain here.
class ScheduleReviewPage extends StatefulWidget {
  const ScheduleReviewPage({super.key});

  @override
  State<ScheduleReviewPage> createState() => _ScheduleReviewPageState();
}

class _ScheduleReviewPageState extends State<ScheduleReviewPage> {
  CustodyProposalDto? _proposal;
  String _summary = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // MAUI sets this in the review page ctor: countering a partner's proposal during
    // onboarding must route back through the onboarding router (so the second parent
    // doesn't skip the paywall), not just pop.
    PendingTemplateService.isOnboardingMode = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await ServiceLocator.custodyProposal.getActiveProposal();
      final proposal = resp?.proposal;
      if (proposal == null) {
        // No proposal — got here in error. Let the router send us elsewhere.
        if (mounted) await advanceOnboarding(context);
        return;
      }
      if (!mounted) return;
      setState(() {
        _proposal = proposal;
        _summary = _buildPlainEnglishSummary(proposal);
      });
    } catch (e) {
      if (!mounted) return;
      await _alert("Couldn't load", 'Trouble loading the schedule: $e');
    }
  }

  static String _buildPlainEnglishSummary(CustodyProposalDto p) {
    if (p.days.isEmpty) return 'Tap the buttons below to respond.';
    final husbandDays = p.days.where((d) => d.parentAssignment == 'Husband').length;
    final wifeDays = p.days.where((d) => d.parentAssignment == 'Wife').length;
    final bothDays = p.days.where((d) => d.parentAssignment == 'Both').length;
    final total = (husbandDays + wifeDays + bothDays).clamp(1, 1 << 31);
    final dadPct = (husbandDays * 100 / total).round();
    final momPct = (wifeDays * 100 / total).round();
    final weeks = p.patternLength == 1 ? '1-week' : '${p.patternLength}-week';
    return 'A $weeks repeating pattern. Dad has $dadPct% of the time, Mom has $momPct%. '
        'The schedule below shows how this lands on your next 4 weeks.';
  }

  Future<void> _accept() async {
    final proposal = _proposal;
    if (proposal == null || _busy) return;
    final confirmed = await _confirm(
      'Accept this schedule?',
      'This will make the schedule live for both you and your co-parent. You can propose changes later.',
      'Yes, accept',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await ServiceLocator.custodyProposal.approveProposal(proposal.proposalId);
      if (result?.success == true) {
        AnalyticsService.trackCustom('onboarding_proposal_accepted');
        if (!mounted) return;
        await advanceOnboarding(context);
      } else {
        if (!mounted) return;
        setState(() => _busy = false);
        await _alert("Couldn't accept", 'Something went wrong. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _alert("Couldn't accept", '$e');
    }
  }

  Future<void> _reject() async {
    final proposal = _proposal;
    if (proposal == null || _busy) return;
    final confirmed = await _confirm(
      'Reject this schedule?',
      "Your co-parent's proposal will be discarded. You'll then build your own schedule from scratch.",
      'Yes, reject',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ServiceLocator.custodyProposal.rejectProposal(proposal.proposalId);
      AnalyticsService.trackCustom('onboarding_proposal_rejected');
      if (!mounted) return;
      // After reject, re-enter the router — the no-schedule branch kicks in.
      await advanceOnboarding(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _alert("Couldn't reject", '$e');
    }
  }

  void _counter() {
    // Open the editor with the partner's pending proposal to mark conflicts / edit
    // days. Its save routes through the onboarding router (wired in the schedule pass).
    AnalyticsService.trackCustom('onboarding_proposal_counter_started');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustodySchedulePage()),
    );
  }

  void _seeFullDetails() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustodySchedulePage()),
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Column(
            children: [
              const OnboardingStepHeader(step: 2),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          const HeroOrb(
                            gradient: [Color(0xFF10B981), Color(0xFF059669)],
                            icon: 'icon_calendar',
                            haloSize: 100,
                            coreSize: 68,
                            coreRadius: 22,
                            iconSize: 32,
                          ),
                          const SizedBox(height: 20),
                          Text('Your co-parent suggested a schedule',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                          const SizedBox(height: 10),
                          Text('Review it together. Accept, suggest changes, or start over.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15, color: palette.textSecondary)),
                          const SizedBox(height: 24),

                          // Summary card
                          _card(
                            context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _cardHeader(context, '📋', AppColors.iconBgBlue, 'AT A GLANCE'),
                                const SizedBox(height: 12),
                                Text(_summary,
                                    style: TextStyle(fontSize: 16, height: 1.4, color: palette.textPrimary)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Preview card
                          _card(
                            context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _cardHeader(context, '📅', AppColors.iconBgGreen, 'NEXT 4 WEEKS'),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    _legend(context, const Color(0xFFBFDBFE), 'Dad'),
                                    const SizedBox(width: 14),
                                    _legend(context, const Color(0xFFFCE7F3), 'Mom'),
                                    const SizedBox(width: 14),
                                    _legend(context, const Color(0xFFE9D5FF), 'Both'),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (_proposal != null)
                                  ProposalPreviewGrid(
                                    patternLength: _proposal!.patternLength,
                                    days: _proposal!.days,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: _seeFullDetails,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: Text('See full details →',
                                  style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Sticky footer
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(24, 16, 24, 32 + MediaQuery.viewPaddingOf(context).bottom),
                decoration: BoxDecoration(
                  color: palette.surface,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
                        offset: const Offset(0, -4),
                        blurRadius: 16),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tintButton(context, 'Accept this schedule', AppColors.successGreen, Colors.white, 56, 28,
                        _accept, shadow: true),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _tintButton(
                            context,
                            'Suggest changes',
                            context.isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
                            AppColors.warningAmber,
                            48,
                            24,
                            _counter,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _tintButton(
                            context,
                            'Reject',
                            context.isDark ? const Color(0xFF1F1416) : const Color(0xFFFEE2E2),
                            AppColors.dangerRed,
                            48,
                            24,
                            _reject,
                          ),
                        ),
                      ],
                    ),
                  ],
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
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: context.palette.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.06),
                offset: const Offset(0, 4),
                blurRadius: 16),
          ],
        ),
        child: child,
      );

  Widget _cardHeader(BuildContext context, String emoji, Color bg, String label) => Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 14))),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: context.palette.textSecondary)),
        ],
      );

  Widget _legend(BuildContext context, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, color: context.palette.textSecondary)),
        ],
      );

  Widget _tintButton(BuildContext context, String label, Color bg, Color fg, double height, double radius,
          VoidCallback onTap,
          {bool shadow = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: shadow
                ? [BoxShadow(color: bg.withValues(alpha: 0.35), offset: const Offset(0, 6), blurRadius: 12)]
                : null,
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(fontSize: height >= 56 ? 16 : 14, fontWeight: FontWeight.bold, color: fg)),
          ),
        ),
      );
}
