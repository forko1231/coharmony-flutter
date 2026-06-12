import '../models/auth_models.dart';
import 'auth_service.dart';
import 'onboarding_router.dart';
import 'onboarding_state.dart';
import 'preferences.dart';
import 'subscription_service.dart';

/// Where to send the user immediately after authentication.
///
/// [onboarding] means "defer to [OnboardingRouter.routeToNext]". The navigation
/// layer should, on [onboarding], call the onboarding router and map its
/// [OnboardingDestination]. Mirrors `PostAuthRouter`'s precedence.
enum PostAuthDestination { childApp, mfaRequired, contactEmail, onboarding, subscription, mainApp }

/// Port of `Services/PostAuthRouter.cs`. Single source of truth for post-auth
/// routing. Returns a destination instead of swapping `MainPage`.
///
/// Precedence:
///   1. Accepted child account → childApp
///   2. Email not verified     → mfaRequired (login MFA gate)
///   3. Onboarding incomplete  → onboarding (defer to OnboardingRouter)
///   4. No active subscription → subscription
///   5. Otherwise              → mainApp
///
/// FAIL-SECURE: any routing failure returns [PostAuthDestination.subscription]
/// (never mainApp) so a thrown exception can't bypass the paywall.
class PostAuthRouter {
  PostAuthRouter(this._auth, this._subscription);

  final AuthService _auth;
  final SubscriptionService _subscription;

  Future<PostAuthDestination> route() async {
    try {
      UserInfo? userInfo;
      try {
        userInfo = await _auth.getUserInfo();
      } catch (_) {
        // GetUserInfo failure — leave null; fall through (better to over-onboard).
      }

      // 1. Child accounts get their own shell — checked first.
      if (userInfo?.accountType == 'child') {
        await Preferences.setString('AccountType', 'child');
        return PostAuthDestination.childApp;
      }

      // 1b. Email-verification MFA gate. Login normally gates this before routing,
      // but the token is stored first — so a kill-and-relaunch from the
      // VerifyMfaPage would otherwise restore the session and skip MFA entirely.
      // Only gate when the server EXPLICITLY says unverified: a failed
      // getUserInfo leaves userInfo null and falls through (a transient error
      // must not lock out a verified user), and SSO accounts (Google/Apple)
      // always come back emailConfirmed since the provider verified the email.
      if (userInfo != null && !userInfo.emailConfirmed) {
        return PostAuthDestination.mfaRequired;
      }

      // 1c. Apple "Hide My Email" relay → must set a real contact email first, so a
      // co-parent can find them by an address they actually use.
      if ((userInfo?.email ?? '').endsWith('@privaterelay.appleid.com')) {
        return PostAuthDestination.contactEmail;
      }

      // 2. Onboarding gate (paywall is the last onboarding step).
      if (!OnboardingState.isCompleted) {
        return PostAuthDestination.onboarding;
      }

      // 3. Onboarding done → check subscription.
      final (isValid, _) = await _subscription.validateSubscription();
      return isValid ? PostAuthDestination.mainApp : PostAuthDestination.subscription;
    } catch (_) {
      // FAIL-SECURE: land at the paywall, never the app.
      return PostAuthDestination.subscription;
    }
  }
}
