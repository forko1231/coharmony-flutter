import 'address_search_service.dart';
import 'ai_chat_service.dart';
import 'app_navigation.dart';
import 'calling_service.dart';
import 'callkit_service.dart';
import 'auth_service.dart';
import 'api_client.dart';
import 'live_schedule_service.dart';
import 'financial_service.dart';
import 'location_service.dart';
import 'messaging_service.dart';
import 'notification_service.dart';
import 'onboarding_router.dart';
import 'onboarding_state.dart';
import 'post_auth_router.dart';
import 'preferences.dart';
import 'schedule_service.dart';
import 'subscription_service.dart';
import 'iap_service.dart';
import 'push_service.dart';
import 'websocket_service.dart';
import 'secure_storage_service.dart';
import 'token_service.dart';
import '../security/message_encryption_service.dart';
import '../security/security_services.dart';
import 'package:flutter/material.dart';
import '../features/subscription/subscription_page.dart';

/// Minimal service locator — the Flutter equivalent of the DI registration in
/// MAUI's `MauiProgram.cs`. Singletons are created in dependency order:
/// SecureStorage → Token → ApiClient → AuthService.
///
/// Call [ServiceLocator.init] once at startup before using any service.
class ServiceLocator {
  ServiceLocator._();

  static late final SecureStorageService secureStorage;
  static late final TokenService tokenService;
  static late final ApiClient api;
  static late final AuthService auth;
  static late final LiveScheduleService liveSchedule;
  static late final ScheduleService schedule;
  static late final FinancialService financial;
  static late final AddressSearchService addressSearch;
  static late final WebSocketService webSocket;
  static late final MessagingService messaging;
  static late final MessageEncryptionService messageEncryption;
  static late final NotificationService notifications;
  static late final PushService push;
  static late final LocationService location;
  static late final SubscriptionService subscription;
  static late final IapService iap;
  static late final AiChatService aiChat;
  static late final CallingService calling;
  static late final CallKitService callKit;

  /// LiveKit server URL — set this to your deployed LiveKit instance.
  /// e.g. 'wss://livekit.ez-split.com'
  static const String livekitUrl = String.fromEnvironment(
    'LIVEKIT_URL',
    defaultValue: 'wss://coharmony-hg32gbwv.livekit.cloud',
  );
  static late final OnboardingRouter onboardingRouter;
  static late final PostAuthRouter postAuthRouter;
  static late final KeyManagementService keyManagement;
  static late final SecurityAuditService securityAudit;

  static bool _initialized = false;

  static Future<void> init({
    bool Function()? isOnboardingCompleted,
    String Function()? accountType,
    void Function()? onSubscriptionRequired,
  }) async {
    if (_initialized) return;

    await Preferences.init();

    secureStorage = SecureStorageService();
    tokenService = TokenService(secureStorage);
    api = ApiClient(
      tokenService: tokenService,
      // Defaults so a runtime 402 (Payment Required) is actually HANDLED. Previously these
      // were null, so the ApiClient silently swallowed 402s — leaving a logged-in user stuck
      // with empty/failed data and no paywall (recovered only by logging out and back in).
      isOnboardingCompleted: isOnboardingCompleted ?? (() => OnboardingState.isCompleted),
      accountType: accountType ?? (() => Preferences.getString('AccountType')),
      onSubscriptionRequired: onSubscriptionRequired ?? _handleSubscriptionRequired,
    );
    auth = AuthService(api, secureStorage, tokenService);
    schedule = ScheduleService(api);
    financial = FinancialService(api);
    addressSearch = AddressSearchService(api);
    webSocket = WebSocketService(api);
    liveSchedule = LiveScheduleService(api, webSocket);
    messaging = MessagingService(api, webSocket);
    messageEncryption = MessageEncryptionService(messaging);
    notifications = NotificationService(api, secureStorage);
    push = PushService(notifications);
    location = LocationService(api);
    subscription = SubscriptionService(api);
    iap = IapService(subscription)..init();
    aiChat = AiChatService(api);
    calling = CallingService(api: api, webSocket: webSocket);
    AppNavigation.livekitUrl = livekitUrl;
    callKit = CallKitService(calling, notifications)..start();
    // Foreground WebSocket rings → native CallKit/full-screen incoming UI.
    webSocket.onCallIncoming.listen(callKit.showIncoming);
    // Dismiss the native UI when the caller cancels or the call ends/rejects.
    calling.onCallStateChanged.listen((e) {
      if (e.type == 'call_ended' || e.type == 'call_rejected') {
        callKit.dismiss(e.roomName);
      }
    });
    onboardingRouter = OnboardingRouter(auth, liveSchedule, subscription);
    postAuthRouter = PostAuthRouter(auth, subscription);

    // Security startup (mirrors MauiProgram.CreateMauiApp): initialise key
    // management (rotates the device entropy every 30 days) and run the weekly
    // crypto-environment audit if it's due. Both are fire-and-forget.
    keyManagement = KeyManagementService(secureStorage)..initialize();
    securityAudit = SecurityAuditService();
    if (securityAudit.shouldPerformAudit()) {
      securityAudit.performSecurityAudit();
    }

    OnboardingState.ensureSchemaUpToDate();

    _initialized = true;
  }

  static bool _subRecovering = false;

  // Runtime 402 (Payment Required) handler for a signed-in, onboarded, non-child user.
  // A 402 can mean the server's subscription record went stale (e.g. the store auto-renewed
  // but the server hasn't re-validated the receipt — its status lazily flips to "expired").
  // So we RE-VALIDATE against the store first (same thing logging out/in did); if that
  // restores access, the user keeps working with no interruption. Only if it's genuinely
  // inactive do we route to the paywall — instead of silently leaving them in a broken app.
  static Future<void> _handleSubscriptionRequired() async {
    if (_subRecovering) return;
    _subRecovering = true;
    try {
      final (valid, _) = await subscription.validateSubscription();
      if (valid) return; // store says active → server record reconciled → access restored
      final nav = AppNavigation.navigatorKey.currentState;
      nav?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SubscriptionPage()),
        (route) => false,
      );
    } catch (_) {
      // best-effort; never throw out of a background API call
    } finally {
      // Release the latch after a beat so a later genuine lapse can still react.
      Future.delayed(const Duration(seconds: 3), () => _subRecovering = false);
    }
  }
}
