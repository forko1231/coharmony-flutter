import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import '../../models/subscription_models.dart';
import '../../navigation/app_navigator.dart';
import '../../services/analytics_service.dart';
import '../../services/external_launcher.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../auth/landing_page.dart';

/// Subscription page — port of `Views/SubscriptionPage.xaml`. Status-driven
/// (mirrors MAUI `UpdateUI`): inactive states (None/Expired/Cancelled/PastDue)
/// show the paywall with the monthly + annual plan selector; active states
/// (Active/SharedActive/TrialActive/GracePeriod) show the status card +
/// subscription-management section (Manage Subscription + Continue to App).
///
/// Sign Out is wired here (matches the MAUI handler: force RememberMe off →
/// clear tokens/secrets/prefs → back to landing). Purchase (CTA) and Restore go
/// through the native IAP plugin. Legal links are native URL launches.
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key, this.isOnboarding = false});

  /// When shown as the 3rd onboarding step the header swaps the back button for a
  /// "STEP 3 OF 3" label + progress bars (mirrors MAUI's onboarding chrome).
  final bool isOnboarding;

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  bool _annual = true; // annual preselected (recommended)
  bool _busy = false;
  bool _loading = true; // first-load skeleton (mirrors SkeletonOverlay)
  SubscriptionInfo? _info; // current server status → drives which state renders
  StreamSubscription<({bool success, String message})>? _iapSub;

  @override
  void initState() {
    super.initState();
    _iapSub = ServiceLocator.iap.results.listen((r) async {
      if (!mounted) return;
      setState(() => _busy = false);
      if (r.success) {
        AnalyticsService.trackSubscriptionPurchased(Platform.isIOS ? 'apple_iap' : 'google_play');
      }
      await _alert(r.success ? 'Success' : 'Notice', r.message);
      // A successful purchase refreshes status → the page flips to management.
      if (r.success && mounted) await _loadStatus();
    });
    _loadStatus();
  }

  @override
  void dispose() {
    _iapSub?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final info = await ServiceLocator.subscription.getSubscriptionStatus();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// True for the states that show the active/management UI (mirrors MAUI
  /// `UpdateUI`: Active / SharedActive / TrialActive / GracePeriod). Also honors
  /// the server's authoritative `hasActiveSubscription` flag, so an active
  /// subscriber still gets the management view even if the status string the API
  /// returns isn't one of the mapped enums (otherwise it wrongly shows the paywall).
  bool get _isManaged {
    if (_info?.hasActiveSubscription == true) return true;
    switch (_info?.status) {
      case SubscriptionStatus.active:
      case SubscriptionStatus.sharedActive:
      case SubscriptionStatus.trialActive:
      case SubscriptionStatus.gracePeriod:
        return true;
      default:
        return false;
    }
  }

  /// (title, description, accent) for the status card — 1:1 with MAUI `UpdateUI`.
  ({String title, String desc, Color accent}) get _statusCopy {
    switch (_info?.status) {
      case SubscriptionStatus.active:
      case SubscriptionStatus.sharedActive:
        return (
          title: 'Premium Active',
          desc: 'You have full access to all CoHarmony features.',
          accent: const Color(0xFF10B981),
        );
      case SubscriptionStatus.trialActive:
        return (
          title: 'Free Trial Active',
          desc: "You're currently in your free trial period.",
          accent: const Color(0xFF8B5CF6),
        );
      case SubscriptionStatus.gracePeriod:
        return (
          title: 'Grace Period Active',
          desc: 'Please update your payment method to continue service.',
          accent: const Color(0xFFF59E0B),
        );
      default:
        return (
          title: 'Premium Active',
          desc: 'You have full access to all CoHarmony features.',
          accent: const Color(0xFF10B981),
        );
    }
  }

  Future<void> _purchase() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ServiceLocator.iap.buy(_annual ? SubscriptionPlan.annual : SubscriptionPlan.monthly);
    // Outcome arrives on the results stream (purchases complete asynchronously).
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ServiceLocator.iap.restore();
  }

  // ── Subscription management (port of OnManageSubscriptionClicked) ──────────

  Future<void> _manageSubscription() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Manage Subscription',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('View Details'),
              onTap: () => Navigator.of(sheetCtx).pop('details'),
            ),
            ListTile(
              title: const Text('Update Payment'),
              onTap: () => Navigator.of(sheetCtx).pop('payment'),
            ),
            ListTile(
              title: const Text('Cancel Subscription',
                  style: TextStyle(color: AppColors.dangerRed)),
              onTap: () => Navigator.of(sheetCtx).pop('cancel'),
            ),
            ListTile(
              title: const Text('Cancel'),
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'details':
        await _showSubscriptionDetails();
        break;
      case 'payment':
        await _updatePaymentMethod();
        break;
      case 'cancel':
        await _cancelSubscription();
        break;
    }
  }

  Future<void> _showSubscriptionDetails() async {
    final s = _info?.subscription;
    if (s == null) return;
    var details = 'Plan: ${s.type}\n'
        'Platform: ${s.platform}\n'
        'Price: ${s.currency} ${s.monthlyPrice.toStringAsFixed(2)}/month\n';
    if (s.nextBillingDate != null) {
      details += 'Next billing: ${_formatDate(s.nextBillingDate!)}\n';
    }
    await _alert('Subscription Details', details);
  }

  Future<void> _updatePaymentMethod() async {
    if (Platform.isIOS) {
      await _alert('Update Payment',
          'Please update your payment method through the App Store settings.');
    } else if (Platform.isAndroid) {
      await _alert('Update Payment',
          'Please update your payment method through Google Play settings.');
    } else {
      await _alert('Not Supported',
          "Payment method updates are managed through your platform's app store.");
    }
  }

  Future<void> _cancelSubscription() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Subscription'),
        content: const Text(
            "Are you sure you want to cancel your subscription? You'll continue to have access until the end of your billing period."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep Subscription')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes, Cancel')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    if (Platform.isIOS) {
      await _alert('Cancel Subscription',
          'Please cancel your subscription through the App Store settings.');
    } else if (Platform.isAndroid) {
      await _alert('Cancel Subscription',
          'Please cancel your subscription through Google Play settings.');
    } else {
      await _alert('Not Supported',
          "Subscription cancellation is managed through your platform's app store.");
    }
  }

  /// Continue to App — validates access then routes onward (mirrors MAUI
  /// `NavigateToMainAppAsync` → `OnboardingRouter.RouteToNextAsync`).
  Future<void> _continueToApp() async {
    if (_busy) return;
    setState(() => _busy = true);
    final (valid, message) = await ServiceLocator.subscription.validateSubscription();
    if (!mounted) return;
    setState(() => _busy = false);
    if (valid) {
      await routeAfterAuth(context);
    } else {
      await _alert('Subscription Required', message);
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String _formatDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';

  Future<void> _alert(String title, String message) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );

  static const _features = [
    ['Smart custody schedules', ' with templates and AI'],
    ['Secure messaging', ' with AI tone coaching'],
    ['Shared expenses', ' with auto-split tracking'],
    ['Encrypted file vault', ' for important documents'],
    ['Real-time sync', ' with your co-parent'],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          // Header — back button (default) OR step indicator (onboarding).
          Container(
            width: double.infinity,
            color: palette.surface,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.viewPaddingOf(context).top + 16, 24, 20),
            child: widget.isOnboarding
                ? Column(
                    children: [
                      const Text('STEP 3 OF 3',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                              color: AppColors.accentPurple)),
                      const SizedBox(height: 12),
                      Row(
                        children: const [
                          Expanded(child: _StepBar(AppColors.primaryBlue)),
                          SizedBox(width: 8),
                          Expanded(child: _StepBar(AppColors.successGreen)),
                          SizedBox(width: 8),
                          Expanded(child: _StepBar(AppColors.accentPurple)),
                        ],
                      ),
                    ],
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(child: AppIcon('icon_chevron_left', size: 22, color: palette.textSecondary)),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      // Hero
                      const SizedBox(height: 8),
                      _heroDiamond(),
                      const SizedBox(height: 18),
                      Text('CoHarmony Premium',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      const SizedBox(height: 8),
                      Text('Everything you need to co-parent with confidence.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, color: palette.textSecondary)),
                      const SizedBox(height: 24),

                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: CircularProgressIndicator(),
                        )
                      else if (_isManaged) ...[
                        _statusCard(context),
                        const SizedBox(height: 16),
                        _managementSection(context),
                      ] else ...[
                      // Pricing card
                      Container(
                        decoration: BoxDecoration(
                          color: palette.surfaceElevated,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.10),
                                offset: const Offset(0, 8),
                                blurRadius: 22),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Trial banner
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('🎉', style: TextStyle(fontSize: 16)),
                                  SizedBox(width: 8),
                                  Text('7 days free, cancel anytime',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _planCard(context, annual: true),
                                  const SizedBox(height: 10),
                                  _planCard(context, annual: false),
                                  const SizedBox(height: 22),
                                  for (final f in _features) ...[
                                    _featureRow(context, f[0], f[1]),
                                    const SizedBox(height: 14),
                                  ],
                                  const SizedBox(height: 8),
                                  _cta(context),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AppIcon('icon_lock', size: 12, color: palette.textSecondary),
                                      const SizedBox(width: 6),
                                      Text('Billed by Apple/Google. Cancel any time.',
                                          style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Restore + legal (Restore is iOS-only — App Store restore flow).
                      if (Platform.isIOS)
                        TextButton(
                          onPressed: _busy ? null : _restore,
                          child: const Text('Restore Previous Purchase',
                              style:
                                  TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                        ),
                      Text(
                          'By subscribing, you agree to our Terms and Privacy Policy. Subscription auto-renews unless cancelled at least 24 hours before the end of the period.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, height: 1.4, color: palette.textSecondary)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _legalLink(context, 'Privacy'),
                          Text(' · ', style: TextStyle(color: palette.textSecondary)),
                          _legalLink(context, 'Terms'),
                        ],
                      ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _signOut,
                        child: Text('Sign Out', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
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

  /// Active-status card (port of MAUI `StatusCard` + `SubscriptionDetailsLayout`):
  /// accent-bordered card with the status title, description, and plan details.
  Widget _statusCard(BuildContext context) {
    final palette = context.palette;
    final copy = _statusCopy;
    final s = _info?.subscription;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: copy.accent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: copy.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(copy.title,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(copy.desc, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
          if (s != null) ...[
            const SizedBox(height: 16),
            _detailLine('Plan: ${s.type}'),
            if (s.nextBillingDate != null) _detailLine('Next billing: ${_formatDate(s.nextBillingDate!)}'),
            _detailLine('Price: ${s.currency} ${s.monthlyPrice.toStringAsFixed(2)}/month'),
            _detailLine('Platform: ${s.platform}'),
          ],
        ],
      ),
    );
  }

  Widget _detailLine(String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text, style: TextStyle(fontSize: 14, color: context.palette.textPrimary)),
      );

  /// Management actions (port of MAUI `SubscriptionManagementSection` +
  /// `ContinueToAppButton`).
  Widget _managementSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: _busy ? null : _manageSubscription,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: const BorderSide(color: AppColors.primaryBlue),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          ),
          child: const Text('Manage Subscription',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _busy ? null : _continueToApp,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.35), offset: const Offset(0, 6), blurRadius: 12),
              ],
            ),
            child: Center(
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Continue to App',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ),
      ],
    );
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
    if (confirm != true) return;
    // Match MAUI: force RememberMe off so logout also wipes the saved email/password,
    // then clear all prefs and return to landing.
    await Preferences.setBool('RememberMe', false);
    await ServiceLocator.auth.logout();
    await Preferences.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }

  Widget _heroDiamond() => SizedBox(
        width: 120,
        height: 120,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0.2,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)]),
                  borderRadius: BorderRadius.circular(60),
                ),
              ),
            ),
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)]),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35), offset: const Offset(0, 8), blurRadius: 20),
                ],
              ),
              child: const Center(child: AppIcon('icon_diamond', size: 40, color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _planCard(BuildContext context, {required bool annual}) {
    final palette = context.palette;
    final selected = _annual == annual;
    final accent = AppColors.primaryBlue;
    return GestureDetector(
      onTap: () => setState(() => _annual = annual),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : (context.isDark ? const Color(0xFF1F2937) : Colors.white),
          border: Border.all(color: selected ? accent : palette.border, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Radio
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? accent : palette.border, width: 2),
              ),
              child: selected
                  ? Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(annual ? 'Annual' : 'Monthly',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                      if (annual) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.successGreen, borderRadius: BorderRadius.circular(8)),
                          child: const Text('SAVE 37%',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                  if (annual) ...[
                    const SizedBox(height: 2),
                    Text(r'$5.00/mo · billed yearly',
                        style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                  ],
                ],
              ),
            ),
            Text(annual ? r'$59.99/yr' : r'$7.99/mo',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(BuildContext context, String bold, String rest) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: AppColors.iconBgGreen, borderRadius: BorderRadius.circular(8)),
          child: const Center(
              child: Text('✓', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.successGreen))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                    text: bold,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                TextSpan(text: rest, style: TextStyle(fontSize: 15, color: palette.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cta(BuildContext context) => GestureDetector(
        onTap: _busy ? null : _purchase,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.35), offset: const Offset(0, 6), blurRadius: 12),
            ],
          ),
          child: Center(
            child: _busy
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Start 7-Day Free Trial',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      );

  Widget _legalLink(BuildContext context, String label) => GestureDetector(
        onTap: () => ExternalLauncher.openUrl(
            label == 'Privacy' ? 'https://co-harmony.com/Legal/Privacy' : 'https://co-harmony.com/Legal/Terms'),
        child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.palette.textSecondary)),
      );
}

/// One bar of the onboarding step indicator.
class _StepBar extends StatelessWidget {
  const _StepBar(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)));
}
