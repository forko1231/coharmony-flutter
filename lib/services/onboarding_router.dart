import 'analytics_service.dart';
import 'auth_service.dart';
import 'live_schedule_service.dart';
import 'onboarding_state.dart';
import 'subscription_service.dart';

/// Where forced onboarding should send the user next. Idiomatic Flutter port of
/// `OnboardingRouter.RouteToNextAsync` — instead of imperatively swapping
/// `Application.Current.MainPage`, [OnboardingRouter.routeToNext] returns a
/// destination and the navigation layer reacts.
enum OnboardingDestination {
  roleChoice,
  partnerInvite,
  liveEditor,
  subscription,
  tour,
  mainApp,
}

/// Port of `Services/OnboardingRouter.cs`. Pure decision logic over the ported
/// services + [OnboardingState]. Order matches the C# router exactly.
class OnboardingRouter {
  OnboardingRouter(this._auth, this._live, this._subscription);

  final AuthService _auth;
  final LiveScheduleService _live;
  final SubscriptionService _subscription;

  Future<OnboardingDestination> routeToNext() async {
    if (OnboardingState.isCompleted) {
      return OnboardingDestination.mainApp;
    }

    // Already-established accounts shouldn't be re-onboarded. The server now holds
    // an OnboardingComplete flag (set on completion, or backfilled for accounts that
    // already have a partner + approved schedule), so a fresh install / new device
    // is recognized as done. We still gate the paywall separately below — being
    // onboarded doesn't grant a subscription.
    if (await _isAlreadyOnboarded()) {
      OnboardingState.markCompleted();
      _auth.markOnboardingComplete(); // persist server-side (fire-and-forget)
      if (!await _hasActiveSubscription()) return OnboardingDestination.subscription;
      return OnboardingDestination.mainApp;
    }

    // Step 0: role choice (parent vs child).
    if (OnboardingState.role.isEmpty) {
      return OnboardingDestination.roleChoice;
    }

    // Step 1: partner linked (incl. pending invite the user must ACCEPT first).
    if (!await _isPartnerLinked()) {
      return OnboardingDestination.partnerInvite;
    }

    // Step 2: the LIVE schedule. The user builds one shared schedule in the full live
    // editor and continues — the co-parent does NOT need to have joined or agreed yet
    // (agreement is a later, in-app step, not an onboarding gate). One-shot, gated on a
    // local acknowledgement set when the user taps Continue in the editor.
    if (!OnboardingState.scheduleAcknowledged) {
      return OnboardingDestination.liveEditor;
    }

    // Step 3: subscription (paywall last for conversion).
    if (!await _hasActiveSubscription()) {
      return OnboardingDestination.subscription;
    }

    // Step 4: feature tour (one-shot, informational).
    if (!OnboardingState.tourSeen) {
      return OnboardingDestination.tour;
    }

    // Done.
    return completeOnboarding();
  }

  /// Marks onboarding complete and returns the main-app destination (mirrors
  /// CompleteOnboardingAsync).
  OnboardingDestination completeOnboarding() {
    OnboardingState.markCompleted();
    _auth.markOnboardingComplete(); // persist to DB (fire-and-forget)
    AnalyticsService.trackCustom('onboarding_completed');
    return OnboardingDestination.mainApp;
  }

  /// Whether to show the "your co-parent joined — set up a schedule?" prompt for
  /// an already-onboarded user whose partner finally accepted (one-shot). The UI
  /// shows the alert and, if accepted, navigates to template apply.
  Future<bool> shouldPromptPostJoinSchedule() async {
    if (!OnboardingState.isCompleted) return false;
    if (OnboardingState.schedulePromptShownAfterPartnerJoined) return false;
    if (!await _isPartnerLinked()) return false; // still waiting

    bool hasSchedule = false;
    try {
      final r = await _live.get();
      hasSchedule = r.data?.days.isNotEmpty ?? false;
    } catch (_) {
      return false;
    }

    OnboardingState.schedulePromptShownAfterPartnerJoined = true;
    return !hasSchedule;
  }

  /// PartnerEmail is pre-populated for BOTH sides the moment an invite is sent, so
  /// its presence alone is NOT "linked". The invitee (InviteStatus "invited") must
  /// accept first; the inviter ("inviting") and confirmed ("true") proceed.
  /// Whether the account is already past onboarding. Trusts the server's
  /// OnboardingComplete flag first (set on completion, or backfilled for
  /// established accounts); falls back to inferring it from a linked partner + an
  /// approved schedule in case the server backfill hasn't run yet. Deliberately
  /// independent of subscription — the paywall is a SEPARATE gate, enforced by the
  /// caller. Conflating the two is exactly what dragged established-but-unsubscribed
  /// accounts back through onboarding (and mangled their schedule into a proposal).
  Future<bool> _isAlreadyOnboarded() async {
    try {
      final info = await _auth.getUserInfo();
      return info?.onboardingComplete == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isPartnerLinked() async {
    try {
      final info = await _auth.getUserInfo();
      if (info == null || (info.partnerEmail ?? '').isEmpty) return false;
      if ((info.inviteStatus ?? '').toLowerCase() == 'invited') return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasActiveSubscription() async {
    try {
      final status = await _subscription.getSubscriptionStatus();
      return status.hasActiveSubscription;
    } catch (_) {
      return false; // can't check → force the paywall
    }
  }
}
