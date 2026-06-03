import 'analytics_service.dart';
import 'auth_service.dart';
import 'custody_proposal_service.dart';
import 'onboarding_state.dart';
import 'subscription_service.dart';

/// Where forced onboarding should send the user next. Idiomatic Flutter port of
/// `OnboardingRouter.RouteToNextAsync` — instead of imperatively swapping
/// `Application.Current.MainPage`, [OnboardingRouter.routeToNext] returns a
/// destination and the navigation layer reacts.
enum OnboardingDestination {
  roleChoice,
  partnerInvite,
  scheduleReview,
  templateApply,
  scheduleSent,
  subscription,
  tour,
  mainApp,
}

/// Port of `Services/OnboardingRouter.cs`. Pure decision logic over the ported
/// services + [OnboardingState]. Order matches the C# router exactly.
class OnboardingRouter {
  OnboardingRouter(this._auth, this._proposals, this._subscription);

  final AuthService _auth;
  final CustodyProposalService _proposals;
  final SubscriptionService _subscription;

  Future<OnboardingDestination> routeToNext() async {
    if (OnboardingState.isCompleted) {
      return OnboardingDestination.mainApp;
    }

    // Already-established accounts shouldn't be re-onboarded. MAUI relied on the
    // local completion flag persisting on the device the user onboarded with; a
    // fresh install (or the Flutter app on a device that onboarded via MAUI) has
    // no such flag, so we infer it from server state: a linked partner AND an
    // approved schedule means setup is genuinely done. Conservative on purpose —
    // a real mid-onboarding account has neither, so this never skips real setup.
    if (await _looksAlreadyOnboarded()) {
      return completeOnboarding();
    }

    // Step 0: role choice (parent vs child).
    if (OnboardingState.role.isEmpty) {
      return OnboardingDestination.roleChoice;
    }

    // Step 1: partner linked (incl. pending invite the user must ACCEPT first).
    if (!await _isPartnerLinked()) {
      return OnboardingDestination.partnerInvite;
    }

    // Step 2: schedule.
    var hasApproved = false;
    var partnerHasProposal = false;
    var userHasOwnProposal = false;
    try {
      final approved = await _proposals.getApprovedSchedule();
      final active = await _proposals.getActiveProposal();
      hasApproved = approved?.hasSchedule == true;
      final p = active?.proposal;
      final hasActive = active?.hasActiveProposal == true && p != null;
      partnerHasProposal = hasActive && !p.isCurrentUserProposer;
      userHasOwnProposal = hasActive && p.isCurrentUserProposer;
    } catch (_) {
      // network blip — treat as "no schedule"
    }

    // Partner sent a proposal the user needs to review.
    if (!hasApproved && partnerHasProposal) {
      return OnboardingDestination.scheduleReview;
    }

    // Nobody has any schedule activity yet — pick a starting point.
    if (!hasApproved && !partnerHasProposal && !userHasOwnProposal) {
      // TODO(template): PendingTemplateService.clear() once template state is ported.
      return OnboardingDestination.templateApply;
    }

    // Step 2.5: "schedule sent" confirmation after a fresh submit (one-shot).
    if (!hasApproved && userHasOwnProposal && !OnboardingState.scheduleAcknowledged) {
      return OnboardingDestination.scheduleSent;
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

    bool hasScheduleOrProposal = false;
    try {
      final approved = await _proposals.getApprovedSchedule();
      final active = await _proposals.getActiveProposal();
      hasScheduleOrProposal =
          approved?.hasSchedule == true || active?.hasActiveProposal == true;
    } catch (_) {
      return false;
    }

    OnboardingState.schedulePromptShownAfterPartnerJoined = true;
    if (hasScheduleOrProposal) return false;
    return true;
  }

  /// PartnerEmail is pre-populated for BOTH sides the moment an invite is sent, so
  /// its presence alone is NOT "linked". The invitee (InviteStatus "invited") must
  /// accept first; the inviter ("inviting") and confirmed ("true") proceed.
  /// True only when EVERY onboarding gate is already satisfied server-side: a
  /// linked partner, an approved custody schedule, AND an active subscription.
  /// Requiring all three means short-circuiting to "complete" can never bypass a
  /// gate (notably the paywall), and a genuinely new/mid-onboarding account — which
  /// lacks at least one — always runs the real flow.
  Future<bool> _looksAlreadyOnboarded() async {
    try {
      if (!await _isPartnerLinked()) return false;
      final approved = await _proposals.getApprovedSchedule();
      if (approved?.hasSchedule != true) return false;
      return await _hasActiveSubscription();
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
