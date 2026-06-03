import 'package:flutter/material.dart';
import '../../models/auth_models.dart';
import '../../navigation/app_navigator.dart';
import '../../services/analytics_service.dart';
import '../../services/onboarding_state.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_input_box.dart';
import 'onboarding_step_header.dart';

enum _InviteMode { send, accept, waiting }

/// Onboarding step 1 — connect with co-parent — faithful port of
/// `OnboardingPartnerInvitePage.xaml(.cs)`.
///
/// Three modes (only one visible): send invite / accept an incoming invite /
/// waiting after sending. On entry it checks for an incoming invite and picks
/// the mode. Send mode also collects optional child emails, fired best-effort
/// after the partner invite succeeds. No skip — a partner is required.
class PartnerInvitePage extends StatefulWidget {
  const PartnerInvitePage({super.key});

  @override
  State<PartnerInvitePage> createState() => _PartnerInvitePageState();
}

class _PartnerInvitePageState extends State<PartnerInvitePage> {
  _InviteMode _mode = _InviteMode.send;
  final _partnerEmail = TextEditingController();
  final List<TextEditingController> _childEmails = [];

  PartnerInviteInfo? _incomingInvite;
  bool _loading = false; // full-screen "checking / sending" overlay
  bool _busy = false; // disables the primary button
  String? _error;
  String _waitingEmail = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _partnerEmail.dispose();
    for (final c in _childEmails) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    OnboardingState.markStarted();
    AnalyticsService.trackCustom('onboarding_started');
    setState(() => _loading = true);
    try {
      _incomingInvite = await ServiceLocator.auth.checkForInvite();
    } catch (_) {
      _incomingInvite = null;
    }
    if (!mounted) return;
    final invite = _incomingInvite;
    setState(() {
      _loading = false;
      _mode = (invite != null && invite.valid && !invite.synced)
          ? _InviteMode.accept
          : _InviteMode.send;
    });
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  Future<void> _sendInvite() async {
    if (_busy) return;
    setState(() => _error = null);
    final email = _partnerEmail.text.trim();
    if (email.isEmpty) {
      setState(() => _error = "Please enter your co-parent's email.");
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _error = "That doesn't look like a valid email.");
      return;
    }

    setState(() {
      _busy = true;
      _loading = true;
    });
    try {
      // SMART: if the entered email matches an incoming invite, auto-accept instead.
      final invite = _incomingInvite;
      if (invite != null &&
          invite.valid &&
          !invite.synced &&
          (invite.inviterEmail ?? '').toLowerCase() == email.toLowerCase()) {
        final accepted = await ServiceLocator.auth.acceptInvite();
        if (accepted) {
          AnalyticsService.trackCustom('onboarding_partner_invite_accepted');
          if (!mounted) return;
          await advanceOnboarding(context);
          return;
        }
      }

      final result = await ServiceLocator.auth.invitePartner(email);
      final ok = result.isNotEmpty &&
          (result.toLowerCase().contains('success') || result.toLowerCase().contains('sent'));
      if (!mounted) return;
      if (ok) {
        AnalyticsService.trackCustom('onboarding_partner_invite_sent');
        // Best-effort child invites — never block the partner-invite success.
        await _sendPendingChildInvites();
        if (!mounted) return;
        setState(() {
          _waitingEmail = email;
          _mode = _InviteMode.waiting;
        });
      } else {
        setState(() => _error = result.isEmpty
            ? "Couldn't send invite. Please check the email and try again."
            : result);
      }
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't send invite: $e");
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _acceptIncoming() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _loading = true;
    });
    try {
      final accepted = await ServiceLocator.auth.acceptInvite();
      if (!mounted) return;
      if (accepted) {
        AnalyticsService.trackCustom('onboarding_partner_invite_accepted');
        await advanceOnboarding(context);
      } else {
        await _alert('Couldn\'t connect', 'Something went wrong. Please try again.');
      }
    } catch (e) {
      if (mounted) await _alert("Couldn't connect", '$e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _continueAfterSent() async {
    // Invite sent but partner hasn't accepted — move on; the router handles it.
    await advanceOnboarding(context);
  }

  /// Sends any pending child invites collected on this page. Blank/invalid emails
  /// are skipped; failures are swallowed (re-invite later from Family).
  Future<void> _sendPendingChildInvites() async {
    var sent = 0;
    for (final c in _childEmails) {
      final childEmail = c.text.trim();
      if (childEmail.isEmpty || !_isValidEmail(childEmail)) continue;
      try {
        final result = await ServiceLocator.auth.inviteChild(childEmail);
        if (result.isNotEmpty &&
            (result.toLowerCase().contains('success') || result.toLowerCase().contains('sent'))) {
          sent++;
        }
      } catch (_) {/* best-effort */}
    }
    if (sent > 0) {
      AnalyticsService.trackCustom('onboarding_child_invites_sent',
          extraTags: {'count': sent.toString()});
    }
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
              const OnboardingStepHeader(step: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: switch (_mode) {
                        _InviteMode.send => _buildSend(context),
                        _InviteMode.accept => _buildAccept(context),
                        _InviteMode.waiting => _buildWaiting(context),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_loading)
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

  // ── Send-invite mode ────────────────────────────────────────────────────────
  Widget _buildSend(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        const SizedBox(height: 12),
        const _HeroOrb(gradient: [Color(0xFF3B82F6), Color(0xFF6366F1)], icon: 'icon_users'),
        const SizedBox(height: 20),
        Text('Bring your co-parent in',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        const SizedBox(height: 10),
        Text("CoHarmony works best when you're both connected. We'll send them an invite to get started.",
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: palette.textSecondary)),
        const SizedBox(height: 32),

        // Email card
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _overline(context, "CO-PARENT'S EMAIL"),
              const SizedBox(height: 14),
              AppInputBox(
                strokeThickness: 1,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: AppTextField(
                    controller: _partnerEmail, hint: 'partner@example.com', keyboardType: TextInputType.emailAddress),
              ),
              const SizedBox(height: 14),
              // Important warning
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
                  border: Border.all(color: context.isDark ? const Color(0xFF92400E) : const Color(0xFFFCD34D)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⚠️', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Important',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: context.isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E))),
                          const SizedBox(height: 2),
                          Text(
                              "Your co-parent needs to sign up for CoHarmony using this exact email. We'll link your accounts the moment they do.",
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.isDark ? const Color(0xFFFCD34D) : const Color(0xFF78350F))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Invite kids (optional)
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _overline(context, 'INVITE YOUR KIDS (OPTIONAL)'),
              const SizedBox(height: 4),
              Text(
                  "They'll get a free child account where they can see the schedule and message you. They sign up with the email you enter here.",
                  style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              const SizedBox(height: 14),
              for (int i = 0; i < _childEmails.length; i++) ...[
                Row(
                  children: [
                    Expanded(
                      child: AppInputBox(
                        strokeThickness: 1,
                        child: AppTextField(
                            controller: _childEmails[i], hint: 'child@example.com', keyboardType: TextInputType.emailAddress),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: palette.textSecondary),
                      onPressed: () => setState(() => _childEmails.removeAt(i).dispose()),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              GestureDetector(
                onTap: () => setState(() => _childEmails.add(TextEditingController())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('+',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                      SizedBox(width: 6),
                      Text('Add a child',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        if (_error != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.errorBg,
              border: Border.all(color: palette.errorBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: context.isDark ? AppColors.dangerRedLight : AppColors.dangerRed)),
          ),
        ],
        _pillButton(context, 'Send Invite', AppColors.primaryBlue, _sendInvite),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon('icon_lock', size: 14, color: palette.textSecondary),
            const SizedBox(width: 8),
            Text('They\'ll only see what you choose to share',
                style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          ],
        ),
      ],
    );
  }

  // ── Accept-incoming mode ──────────────────────────────────────────────────
  Widget _buildAccept(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        const SizedBox(height: 12),
        const _HeroOrb(gradient: [Color(0xFF10B981), Color(0xFF059669)], icon: 'icon_users'),
        const SizedBox(height: 20),
        Text("You've been invited",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        const SizedBox(height: 10),
        Text('A co-parent has invited you to connect.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: palette.textSecondary)),
        const SizedBox(height: 32),
        _card(
          context,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF10B981), Color(0xFF059669)]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                    child: Text('✓', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        (_incomingInvite?.inviterName?.isNotEmpty ?? false)
                            ? _incomingInvite!.inviterName!
                            : (_incomingInvite?.inviterEmail ?? 'Your co-parent'),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    Text(_incomingInvite?.inviterEmail ?? '',
                        style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _pillButton(context, 'Accept & Connect', AppColors.successGreen, _acceptIncoming),
      ],
    );
  }

  // ── Waiting mode ────────────────────────────────────────────────────────────
  Widget _buildWaiting(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        const SizedBox(height: 12),
        const _HeroOrb(gradient: [Color(0xFFF59E0B), Color(0xFFF97316)], icon: 'icon_clock'),
        const SizedBox(height: 20),
        Text('Invite sent',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        const SizedBox(height: 10),
        Text('We sent an invite to $_waitingEmail.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: palette.textSecondary)),
        const SizedBox(height: 32),
        _card(
          context,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('💡', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Don't wait around",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Keep going — set up your schedule now. Your co-parent will see it the moment they join.',
                        style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _pillButton(context, 'Continue Setting Up', AppColors.primaryBlue, _continueAfterSent),
      ],
    );
  }

  // ── Shared bits ───────────────────────────────────────────────────────────
  Widget _card(BuildContext context, {required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
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

  Widget _overline(BuildContext context, String text) => Text(text,
      style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: context.palette.textSecondary));

  Widget _pillButton(BuildContext context, String label, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), offset: const Offset(0, 6), blurRadius: 12)],
          ),
          child: Center(
            child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      );
}

/// The gradient "orb" hero (soft halo + core with a white icon) used in each mode.
class _HeroOrb extends StatelessWidget {
  final List<Color> gradient;
  final String icon;
  const _HeroOrb({required this.gradient, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0.18,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
                borderRadius: BorderRadius.circular(60),
              ),
            ),
          ),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: gradient.first.withValues(alpha: 0.35), offset: const Offset(0, 8), blurRadius: 20)],
            ),
            child: Center(child: AppIcon(icon, size: 40, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
