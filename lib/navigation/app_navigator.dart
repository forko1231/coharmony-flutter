import 'package:flutter/material.dart';

import '../features/auth/verify_mfa_page.dart';
import '../features/child/child_app_shell.dart';
import '../features/onboarding/contact_email_page.dart';
import '../features/onboarding/partner_invite_page.dart';
import '../features/onboarding/role_choice_page.dart';
import '../features/onboarding/tour_page.dart';
import '../features/schedule/live_schedule_page.dart';
import '../features/shell/app_shell.dart';
import '../features/subscription/subscription_page.dart';
import '../services/onboarding_router.dart';
import '../services/post_auth_router.dart';
import '../services/preferences.dart';
import '../services/service_locator.dart';

/// Maps the routers' decision enums onto concrete page widgets and drives
/// navigation. Keeps the imperative `MainPage`-swap out of the decision logic
/// (which stays pure in [PostAuthRouter] / [OnboardingRouter]).

/// Resolves an [OnboardingDestination] to its page.
Widget pageForOnboarding(OnboardingDestination dest) {
  switch (dest) {
    case OnboardingDestination.roleChoice:
      return const RoleChoicePage();
    case OnboardingDestination.partnerInvite:
      return const PartnerInvitePage();
    case OnboardingDestination.liveEditor:
      return const LiveSchedulePage(isOnboarding: true);
    case OnboardingDestination.subscription:
      return const SubscriptionPage(isOnboarding: true);
    case OnboardingDestination.tour:
      return const TourPage();
    case OnboardingDestination.mainApp:
      return const AppShell();
  }
}

/// Resolves where to land after authentication, deferring to [OnboardingRouter]
/// when onboarding is incomplete.
Future<Widget> resolveAfterAuth() async {
  final dest = await ServiceLocator.postAuthRouter.route();
  switch (dest) {
    case PostAuthDestination.childApp:
      return const ChildAppShell();
    case PostAuthDestination.mfaRequired:
      // Cold-start MFA gate: a session was restored but the email was never
      // verified (e.g. the app was killed on the VerifyMfaPage mid-login).
      // Same arguments LoginPage uses, but no onComplete — there's no login
      // page beneath us, so VerifyMfaPage's login-success fallback re-runs
      // routeAfterAuth itself to continue into normal post-auth routing.
      return VerifyMfaPage(
        identifier: Preferences.getString('email'),
        purpose: VerificationPurpose.login,
        method: MfaMethod.email,
        forceMethod: true,
      );
    case PostAuthDestination.contactEmail:
      return const ContactEmailPage();
    case PostAuthDestination.subscription:
      return const SubscriptionPage();
    case PostAuthDestination.mainApp:
      return const AppShell();
    case PostAuthDestination.onboarding:
      final od = await ServiceLocator.onboardingRouter.routeToNext();
      return pageForOnboarding(od);
  }
}

/// Convenience: resolve the post-auth destination and replace the whole stack.
Future<void> routeAfterAuth(BuildContext context) async {
  final page = await resolveAfterAuth();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => page),
    (route) => false,
  );
}

/// Advance forced onboarding to the next step, replacing the stack. Onboarding
/// pages call this from their primary action.
Future<void> advanceOnboarding(BuildContext context) async {
  final od = await ServiceLocator.onboardingRouter.routeToNext();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => pageForOnboarding(od)),
    (route) => false,
  );
}
