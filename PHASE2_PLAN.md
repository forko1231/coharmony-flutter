# Phase 2 — Logic / Services port (MAUI → Flutter)

**READ THIS FIRST IF CONTEXT WAS COMPACTED.** This is the durable plan for porting the
MAUI app's business logic into the Flutter app. The UI-shell phase is already done
(see `PORTING_MANIFEST.md`); every screen renders from local stub view-models. Phase 2
swaps those stubs for real services with **no widget-tree changes**.

## The rule
Port each C# service in `../EZSplit/EZSplit/Services/` **1:1** to Dart: same endpoint
routes, same JSON payloads, same logic. The ASP.NET controllers in `../SplitServer/Controllers/`
are the wire spec — cross-check every route/DTO against them. This is faithful translation,
not redesign.

## Ground truth (confirmed by reading the C# + server)
- **Base URL:** `https://api.ez-split.com` (all envs, from `MauiProgram.cs`).
- **JSON naming:** **camelCase** (`AppJsonContext.cs` → `JsonKnownNamingPolicy.CamelCase`).
  Every Dart `toJson`/`fromJson` key is camelCase.
- **Default headers:** `Accept: application/json`, `X-Client-Platform`, `X-Client-Version`,
  per-request `X-Request-ID` (new GUID), `Authorization: Bearer <token>`. Timeout 30s.
- **Auth flow:** 401 → `TokenService.refreshToken()` (POST `api/auth/refresh-token`, no-retry)
  → retry once. 402 (PaymentRequired) → subscription-required redirect (suppressed during
  onboarding + for child accounts).
- **Secure storage keys:** `secure_auth_token`, `secure_refresh_token`, `secure_token_expiry`,
  `secure_email`, `secure_password`, `secure_salt_key`, `secure_messaging_key_<u1>:<u2>`.

## Dart layout
- `lib/services/` — service classes (one per MAUI service)
- `lib/models/` — DTOs (one file per domain, e.g. `auth_models.dart`)
- `lib/services/service_locator.dart` — DI wiring (replaces MAUI `MauiProgram` registration)

## Dependencies added
`http`, `flutter_secure_storage`, `crypto` (PBKDF2/SHA256 for the local password verifier + integrity wrap).

## Order (foundation first — nothing works without it)
### Step 1 — Foundation  ✅ DONE (analyzes clean)
- [x] `secure_storage_service.dart`  ← `SecureStorageService.cs` (flutter_secure_storage + salt/integrity wrap + PBKDF2 verifier)
- [x] `token_service.dart`           ← `TokenService.cs`
- [x] `api_client.dart`              ← `BaseApiService.cs` (GET/POST/PUT/DELETE + bytes + postForString/putForString + postWithoutRetry; 401 refresh+retry; 402 guard)
- [x] `preferences.dart`             ← MAUI `Preferences.Default` (shared_preferences)
- [x] `models/auth_models.dart`      ← all auth DTOs (exact camelCase keys)
- [x] `auth_service.dart`            ← `AuthService.cs` (all ~30 endpoints)
- [x] `service_locator.dart`         ← MAUI DI wiring
- **Finding:** server exposes `user/update` as **PUT** (`[HttpPut]`), MAUI client POSTed
  it → latent 405. Flutter port uses PUT (the working contract). Revisit if backend differs.

### Step 2 — Pure-logic services  ✅ DONE (analyzes clean)
- [x] `custody_proposal_service.dart` + `models/custody_models.dart` ← `CustodyProposalService.cs` (all proposal/day/override/action endpoints)
- [x] `schedule_service.dart` + `models/schedule_models.dart` ← `ScheduleService.cs` (classic schedule + weekly patterns; ScheduleItem read case-insensitively)
- [x] `holiday_resolver.dart` ← `HolidayResolver.cs` (pure; Sunday=0 weekday scheme handled via `weekday % 7`)
- [x] `financial_service.dart` + `models/financial_models.dart` ← `FinancialService.cs` (charges + receipts)
- [x] `address_search_service.dart` + `models/places_models.dart` ← `AddressSearchService.cs` (Places proxy)
- [x] `calendar_export_service.dart` ← `CalendarExportService.cs` — **ICS-generation core ported 1:1**
      (DST-free DateTime arithmetic via component construction). Native device-calendar
      export (EventKit/ContentResolver) + share-sheet stubbed → phase 3 (device_calendar/share_plus).
- All wired in `service_locator.dart`. `ScheduleService.ExportCustodyCalendar` (local file
  placeholder) also deferred to phase 3.

### Step 3 — Real-time + native  ✅ core DONE (analyzes clean)
- [x] `websocket_service.dart` ← `WebSocketService.cs` (web_socket_channel/IOWebSocketChannel
      with Authorization header; C# events → broadcast Stream; reconnect logic).
- [x] `messaging_service.dart` + `models/message_models.dart` ← `MessagingService.cs`.
      **Finding:** message text is plaintext over the API; the SERVER encrypts at rest —
      there is NO client-side message E2E to byte-match. (Mixed JSON casing per DTO handled.)
- [x] `notification_service.dart` + `models/notification_models.dart` ← `NotificationService.cs`
      (server register/update + type parsing + installation id). Native FCM/APNs token,
      permissions, local notifications, banner/nav → phase 3 (firebase_messaging,
      flutter_local_notifications, permission_handler).
- [x] `location_service.dart` + `models/location_models.dart` ← `LocationService.cs`
      (records + custody transfers + POIs). Native geolocation/reverse-geocoding → phase 3
      (geolocator/geocoding).
- [x] `subscription_service.dart` + `models/subscription_models.dart` ← `SubscriptionService.cs`
      (status + 5-min cache + server activation/validation + restore HTTP). Native StoreKit/
      Play Billing purchase flows → phase 3 (`in_app_purchase`); plugin calls validate*/restore* here.
- All wired in `service_locator.dart`. Deps added: `web_socket_channel`.

### Step 3 — remaining  ✅ DONE (analyzes clean)
- [x] `ai_chat_service.dart` + `models/ai_models.dart` ← `AiChatService.cs` (+ tool-call arg models)
- [x] `analytics_service.dart` ← `AnalyticsService.cs` (pluggable `reporter` sink; no-op until
      phase-3 `sentry_flutter` wires it; `*Once` dedup via Preferences)
- [x] `onboarding_state.dart` ← `OnboardingState.cs` (per-email scoped, Preferences-backed)
- [x] `onboarding_router.dart` ← `OnboardingRouter.cs` — returns an `OnboardingDestination`
      enum (declarative; nav layer reacts). Carries the invite-accept fix (InviteStatus
      "invited" ⇒ not linked). `shouldPromptPostJoinSchedule()` ported.
- [x] `post_auth_router.dart` ← `PostAuthRouter.cs` — returns `PostAuthDestination`
      (childApp/onboarding/subscription/mainApp); FAIL-SECURE to subscription on error.
- All wired in `service_locator.dart` (`ensureSchemaUpToDate()` runs on init).
- NOTE: routers read the current user email from the `email` preference + `AccountType`;
  the login/wiring layer (Step 4) must set those after auth (MAUI does the same).

### Phase 2 — essentially complete. Native-only items remain for phase 3 (plugins):
media/photo picker, file preview, `VoiceIntentService` (Siri/App Intents), push wiring
(firebase_messaging/flutter_local_notifications), IAP purchase flow (`in_app_purchase`),
live map SDK (google_maps_flutter), E2E-at-rest is server-side. `PendingTemplateService`
+ custody templates registry still to port when wiring the template flow.

### Step 4 — Wire screens  ◐ IN PROGRESS
Replace each screen's stub view-model with the real service (no widget-tree changes).

**Done (analyzes clean):**
- [x] `main.dart` — `await ServiceLocator.init()` before `runApp`.
- [x] `lib/navigation/app_navigator.dart` — maps `PostAuthDestination`/`OnboardingDestination`
      → pages; `routeAfterAuth()` / `advanceOnboarding()` drive navigation.
- [x] `login_page.dart` — `auth.login` → set `RememberMe` + `email` prefs → `routeAfterAuth`.
- [x] `account_creation_page.dart` — `auth.createAccount` → `OnboardingState.reset` + `email`
      pref → `routeAfterAuth`. (Phone passed empty — collected later in MAUI.)
- [x] `settings_page.dart` — Log Out → confirm → `auth.logout` → back to `LandingPage`.

**Auth surface — DONE (analyzes clean):**
- [x] `forgot_password_page.dart` — `initiatePasswordReset` → push `VerifyMfaPage(passwordReset)`.
- [x] `verify_mfa_page.dart` — full parameterized port of `VerifyMFA` (purpose+method enums,
      send/resend with 60s countdown, attempt tracking via secure storage, per-purpose success
      routing: newAccount→routeAfterAuth, passwordReset→ResetPasswordPage, secureAction/login→
      onComplete callback, change email/phone→popToRoot). SMS method supported in logic; in-UI
      method *selector* not rendered (email/sms chosen by caller) — minor UI deferred.
- [x] `reset_password_page.dart` — two modes: forgot-reset (`completePasswordReset`→login→route)
      and `.changePassword(currentPassword:)` (`updateUserInfo`, parses server message on failure).
- [x] `verify_password_page.dart` — re-auth via `login`, returns password through `Navigator.pop`.
- [x] `landing_page.dart` — Sign In→`LoginPage`, Create Account→`AccountCreationPage`.
- [x] `settings_page.dart` — change email / change password / delete account wired (re-auth →
      SecureAction MFA → action), all via the shared building blocks. `Preferences.clear()` added.
      NOTE: settings still *displays* stub values — read-wiring is in the data-screen pass.

**Onboarding pages — DONE (analyzes clean):**
- [x] `role_choice_page.dart` — Parent: `role='parent'` + analytics + `advanceOnboarding`.
      Child: `role='child'` + `auth.checkChildInvite` → ChildInvite / ChildAppShell / ChildWaiting.
- [x] `partner_invite_page.dart` — `checkForInvite` picks send/accept mode; send →
      auto-accept-if-match else `invitePartner` (+ best-effort `inviteChild` loop) → waiting;
      accept → `acceptInvite` → advance; waiting → advance. Loading overlay + error + analytics.
- [x] `schedule_review_page.dart` — loads active proposal, plain-English summary; Accept→
      `approveProposal`, Reject→`rejectProposal` (both confirm→advance); Counter / See-details →
      push `CustodySchedulePage`.
- [x] `schedule_sent_page.dart` — loads proposal id + partner-email subtitle; Continue flips
      `scheduleAcknowledged`→advance; Redo confirms→`withdrawProposal`→reset→advance.
- [x] `template_apply_page.dart` — Template→`TemplateCatalogPage`, AI→`AiChatPage`,
      Build-from-scratch→`CustodySchedulePage` (+ analytics).
- [x] `tour_page.dart` — Next(last)/Skip → `tourSeen=true` + analytics → `advanceOnboarding`
      (router falls through to completeOnboarding → main app).
- NOTE: the editor-dependent jumps (Counter / See-details / Build / Template / AI) navigate to
  the existing editor/template/AI screens; their onboarding-mode **save routing** (MAUI's
  `PendingTemplateService.IsOnboardingMode`) + the proposal-driven calendar preview (shared
  widget reused by review/sent/editor) land in the schedule/template pass below.

**Data screens — DONE so far (analyze clean):**
- [x] `subscription_page.dart` — Sign Out wired (force RememberMe off → `auth.logout` →
      `Preferences.clear` → landing). Purchase/Restore = phase-3 IAP; active/trial/management
      status states aren't in this paywall shell; legal links = native URL launch (phase 3).
- [x] `ai/ai_chat_page.dart` — `chatContext` param (general/schedule/onboarding-schedule);
      `sendMessage` with conversation history, typing indicator, monthly-usage bar, limit/error
      handling; context-aware welcome subtitle. **Tool-call preview cards** (set_custody_pattern /
      add_override_day / create_event / draft_message / select_template) + their apply/open/send
      deferred to the schedule/templates/messaging passes (need editor + TemplateRegistry +
      PendingTemplateService + ChatInterface) — assistant acknowledges the action for now.

- [x] `main/partner_page.dart` — declarative rewrite of the imperative MAUI page. Loads
      `checkForInvite` + `getPendingLawyerRequests` + `getApprovedLawyers` (+ `getChildren` when
      synced) with a 30s poll + refresh. Co-parent card is state-driven (none→invite /
      pending_received→accept+decline / pending_sent→waiting / synced→disconnect); child invites
      (synced only); lawyers are request-based (accept/decline incoming, remove approved — no "add
      lawyer"). Confirm dialogs + analytics + busy overlay. Help modal preserved.

- [x] `finances/payment_tracker_page.dart` — loads `getCharges(month)` + `getChargesAwaitingVerification`;
      outgoing/incoming tabs by email match; split charges show user's share; month nav reload;
      monthly summary (verified/pending/overdue) from real data; add-payment via `makeCharge`
      (type/direction/split/repeat); card→details sheet with mark-paid / verify / dispute
      (`updateChargePaymentStatus` / `verifyOrDisputePayment`); verification sheet; receipt image
      shown via `getReceipt`. Receipt **photo capture** when marking paid = phase-3 media picker.

- [x] `map/location_records_page.dart` — paginated `getLocationRecords` + infinite scroll;
      summary counts (wide fetch); type filter (all/custody/general); tap→details with
      `deleteLocationRecord`. Live `MapPage` (Google Maps SDK), current-location, geocoding,
      external Navigate = phase-3 native.

**Messaging — DONE (analyzes clean). CORRECTION to an earlier wrong finding:** the message wire
payload is **AES-256-GCM ciphertext** and the CLIENT does the crypto (it is NOT true E2E — the
per-conversation key is fetched from the server via `getConversationEncryptionKey`, so the server
can decrypt). Added dep `cryptography`; new `lib/security/message_encryption_service.dart`
(AesGcm.with256bits; base64(NONCE[12]+TAG[16]+CIPHERTEXT); 15-min normalized key cache) registered
as `ServiceLocator.messageEncryption`.
- [x] `messaging/messaging_page.dart` — loads partner(`checkForInvite`)+children+lawyers + latest
      messages, **decrypts** each, groups Co-Parent/Children/Legal/Other; reloads on
      `onMessageReceived`. Contacts carry email (name→email map). AI card → AiChatPage.
- [x] `messaging/chat_interface_page.dart` — `(contactEmail,contactName,draftMessage?)`; loads +
      decrypts (HTTP, paginated, scroll-to-load-older); send **encrypts** then optimistic bubble;
      `bad_tone` → suggestion bar; live streams (received=PLAINTEXT/no-decrypt, read→Delivered/Read,
      typing bubble); throttled typing notifications (3s); markMessagesAsRead on open/receive.
      **KEY:** WebSocket payloads are already plaintext (server-decrypted) — only HTTP rows decrypt.
- [x] `child/child_messaging_page.dart` — `getFamilyInfo` → two parent contacts + decrypted preview
      + unread; tap → shared chat.
- Attachment pick/view/save (native media/file pickers) = phase 3.

**Schedule subsystem — DONE (whole project analyzes clean).** The linchpin + the main tab.
New Dart pieces under `lib/services/custody_templates/`: `custody_template.dart` (CustodyTemplate/
TemplateQuestion/QuestionType/TemplateAnswers/GeneratedDay), `templates.dart` (8 concrete templates
+ PatternHelpers.fromNights/addHours + CommonQuestions; underscore class names renamed to
UpperCamelCase to satisfy `camel_case_types`), `template_registry.dart` (groupedByCategory preserves
first-seen order), `template_apply_helper.dart`, `pending_template_service.dart` (static holder; no
lock needed — single isolate; `isOnboardingMode` is a plain field).
- [x] `features/schedule/editor_models.dart` — LocationData / DayBaseline / DayEditCommit /
      OverrideBaseline / OverrideDayEditResult (times as `TimeOfDay`; page formats to "HH:mm").
- [x] `day_editor_view.dart` + `override_editor_view.dart` — real Load semantics via ctor data +
      baseline + POIs; live `onCommit`(day) / `onApply`(override) callbacks; per-field "was X · Revert"
      diff rows + "Edited" pill; POI "choose existing"; holiday picker + date picker (override).
- [x] `custody_schedule_page.dart` — wired to `custodyProposal`: load active+approved, day-data
      resolution (local edits→proposal→approved→None), gradient day cells (transfer-time split),
      long-press conflict (partner mode), special-day cards (add/edit/delete/undo + deletion filter),
      FULL save routing (counter / draft-submit / submitted→new / new), accept/reject/withdraw/counter,
      pattern-length change, onboarding chrome ("Continue" green), template/raw-pattern apply via
      `PendingTemplateService`, AI FAB, first-open walkthrough.
- [x] `templates/template_catalog_page.dart` + `template_config_page.dart` + `custody_start_choice_page.dart`
      — registry-driven catalog, config with dynamic questions + LIVE gradient preview + Apply
      (onboarding → `TemplateApplyHelper.createAndSubmitProposal` + `advanceOnboarding`; editor →
      `setResult` + pop), start-choice wired.
- [x] `schedule_page.dart` (main tab) + ported `MonthItem` resolver — month calendar shaded by custody
      (pattern anchoring via CalculateWeekInPattern + override/holiday/alternation resolution), payment
      borders, event dots, proposal-preview toggle, custody-% metrics, tap→DateDataPage, Manage→editor.
- [x] Onboarding-mode flag wired: `template_apply_page` + `schedule_review_page` set
      `PendingTemplateService.isOnboardingMode = true`; main-tab Manage button sets it false (defensive).
- DEFERRED here: AI **tool-call cards** in chat (set_custody_pattern/add_override/etc — services now
  exist; revisit), device-calendar export + .ics share (native device_calendar/share_plus — phase 3).

**Dashboard / Settings / Export — DONE (whole project analyzes clean).**
- [x] `theme/theme_controller.dart` (NEW) — persisted `ValueNotifier<ThemeMode>` (`app_theme` pref);
      `main.dart` wraps MaterialApp in a `ValueListenableBuilder` so the Settings theme dropdown
      applies app-wide + survives restart.
- [x] `features/shell/app_shell.dart` — added `AppShellScope` InheritedWidget exposing `goToTab(i)`
      (replaces MAUI's `Shell.GoToAsync("//Schedule")`); tabs 0 Home/1 Schedule/2 Messager/3 Payments/4 Map.
- [x] `main/settings_page.dart` — loads `getUserInfo` (account overview name + email + verified badge);
      theme dropdown ↔ `ThemeController`; notifications toggle persisted; Partner & Export rows now push
      `PartnerPage` / `ExportDataPage`. (Change email/password/delete-account were already wired.)
- [x] `main/export_data_page.dart` — each report calls the real `api/export/*` endpoint via
      `ServiceLocator.api.getBytes` with a busy overlay; confirms generation (size). Saving the PDF to
      device (MAUI `IMediaService`) stays phase-3 native (path_provider/share_plus).
- [x] `main/main_menu_page.dart` (dashboard) — full port of `MainMenu.xaml.cs`: loads partner
      (`checkForInvite`) + lawyers + children (contact-name map), schedule events, approved custody,
      month charges, decrypted messages, location records; renders Today-custody + Next-event stats,
      custody-shaded mini-calendar (same resolver: pattern anchoring + override/holiday/alternation +
      payment borders + event dots, tap→DateData), upcoming events, payment summary (verified/pending/
      overdue w/ split share), recent conversations (top-4, co-parent→lawyer→recent, tap→ChatInterface),
      co-parent status (→PartnerPage), location stats, quick access (AI/FileVault/Subscription); pull-to-
      refresh + live reload on `onMessageReceived`. Tab jumps via `AppShellScope`.

**Day detail + child screens — DONE (whole project analyzes clean).**
- [x] `schedule/add_event_popup.dart` — returns an `AddEventResult` (name/start/end/repeat/endDate);
      edit ctor pre-fills; end-after-start validation.
- [x] `schedule/date_data_page.dart` — loads events (`getScheduleOptimized`, non-custodial) + approved
      custody + charges; custody-info card (override→pattern+alternation+handoff+location), payment-info
      card (direct + recurring charges, colored border), 24h timeline with positioned event blocks
      (recurrence-expanded), add/edit/delete via `updateSchedules`/`deleteSchedules` (edit = delete-then-
      recreate, using the event's ORIGINAL date for recurring instances), day prev/next nav.
- [x] Child: `child_invite_page` (load `checkChildInvite`, accept→`acceptChildInvite`+AccountType=child→
      ChildAppShell, decline→`declineChildInvite`; none-left→clear role + `advanceOnboarding`),
      `child_waiting_page` (refresh polls `checkChildInvite`; "I'm not a child"→clear role + advance),
      `child_family_page` (`getFamilyInfo` → parents + siblings sections), `child_settings_page`
      (`getUserInfo` + ThemeController + logout + `removeChildStatus`→leave family), `child_main_menu`
      (today custody + next change, custody-shaded mini-month, parent message previews→ChatInterface,
      family card). `child_schedule_page` + `child_messaging_page` were already wired.

**AI tool-call cards — DONE (whole project analyzes clean).** `ai/ai_chat_page.dart` now renders the
AI's inline tool-call preview cards and applies them (was a deferred stub):
- `_items` is a `sealed _ChatItem` list (text bubbles + card items); `_handleToolCall` decodes
  `arguments` JSON into the existing arg models and appends the matching card.
- **set_custody_pattern** → mini week-grid preview; non-onboarding "Accept" → `createNewProposal` +
  `updateDays` + `submitProposal` (+ "View in Schedule Editor" button); onboarding "Open in Editor" →
  `PendingTemplateService.setRawPattern` → push CustodySchedulePage.
- **add_override_day** → card; Accept → active-proposal-or-create → `addOrUpdateOverride`.
- **create_event** → card; "Add Event" → `schedule.updateSchedule`.
- **draft_message** → card with Copy (clipboard) / Send (→ ChatInterfacePage with `draftMessage`).
- **select_template** → card; Open → `TemplateRegistry.findById` → TemplateConfigPage(presetAnswers).

**File Vault = confirmed PHASE-3 NATIVE (no wiring).** MAUI `Filevault.xaml.cs` is entirely local —
`FileSystem.AppDataDirectory` document store + `MediaPicker`/`FilePicker`/`Share` + local copy/rename/
delete + photo viewer; there is NO server API. The Dart stub stands until native plugins land
(path_provider, file_picker, image_picker, share_plus).

**PHASE 2 SCREEN-WIRING COMPLETE.** Every screen with a server/data dependency is wired and the whole
project analyzes clean. Only genuinely-native features remain (phase 3).

### Phase 3 — native plugins  ◐ IN PROGRESS (analyzes clean)
Deps added + `flutter pub get` OK: `url_launcher`, `share_plus`, `path_provider`, `image_picker`,
`geolocator`, `geocoding`. Platform config done: Android `AndroidManifest.xml` (INTERNET, FINE/COARSE
LOCATION, CAMERA, READ_MEDIA_IMAGES + maxSdk READ_EXTERNAL_STORAGE; `<queries>` for https + geo) and
iOS `Info.plist` (NSCamera/NSPhotoLibrary/NSLocationWhenInUse usage strings + LSApplicationQueriesSchemes
https/maps/comgooglemaps).
- [x] **url_launcher** — `lib/services/external_launcher.dart` (openUrl + openMaps geo→web fallback);
      subscription Terms/Privacy links (co-harmony.com/Legal/*), location-record **Navigate** button.
- [x] **share_plus + path_provider** — export-data reports write the fetched PDF bytes to a temp file +
      system share sheet; schedule export dialog's **.ics** button builds via `calendarExport.buildIcsForRange`
      → temp file → share. (Device-calendar *import* still needs `device_calendar` — see below.)
- [x] **image_picker** — payment-tracker mark-paid now offers Add Receipt / Skip: camera-or-gallery pick →
      base64 → `financial.uploadReceipt` then status update.
- [x] **geolocator + geocoding** — location-records "Add current location" FAB: permission → getCurrentPosition
      → reverse-geocode → `location.createLocationRecord`.
- NOTE: chat **send-attachment** is intentionally NOT wired — there's no send-attachment endpoint in the
      ported `MessagingService` (only `getAttachment` for viewing), so the picker would have nowhere to post.

### App identity (set permanently, per-platform — the MAUI config matches these)
- Android `applicationId` = **com.x456746A.ezsplit** (`android/app/build.gradle.kts`) — matches the copied
  `android/app/google-services.json` (package com.x456746A.ezsplit) + the Maps key + Play Billing products.
- iOS bundle id = **com.456746.ezsplit** (all Runner build configs in `project.pbxproj`; tests `.RunnerTests`).
- NOTE: namespace stays `com.coharmony.coharmony` (R-class package; needn't equal applicationId).

### Phase 3 — native, with the MAUI config (analyzes clean)
- [x] **Maps — PLATFORM-NATIVE (matches MAUI): Apple MapKit on iOS, Google Maps on Android.**
      `lib/features/map/platform_map.dart` = a neutral wrapper: `PlatformMap` widget + `MapMarkerData` +
      `MapHue` (azure/green/orange) + `PlatformMapController.moveTo(lat,lng,zoom)`. It imports BOTH
      `apple_maps_flutter` (iOS, `Annotation`/`AppleMap`) and `google_maps_flutter` (Android, `Marker`/
      `GoogleMap`) with prefixes (colliding `LatLng`/`CameraPosition`/`BitmapDescriptor`/`InfoWindow` names)
      and branches on `defaultTargetPlatform == TargetPlatform.iOS`. `map_page.dart` only sees neutral types:
      POI (azure) + record (green=transfer/orange=general) markers from `location.getPois`/`getLocationRecords`,
      current-location (geolocator perm), address search (geocoding `locationFromAddress`), refresh,
      records/filter controls, Add-POI FAB (still opens the form popup — POI *create*-at-pin is a refinement).
      Android Maps key stays in `AndroidManifest.xml` (`com.google.android.geo.API_KEY` =
      AIzaSyAzGxlIxlkEsnX3iIMREbd_uLx95GovOjs, from MAUI secrets.xml). Apple MapKit needs NO key — removed
      `import GoogleMaps` + `GMSServices.provideAPIKey` from `ios/Runner/AppDelegate.swift`.
      CAVEAT: `google_maps_flutter` is still a dep (Dart can't drop a plugin per-mobile-platform), so its iOS
      pod links but is INERT (no `GoogleMap` ever built on iOS, no key call). That pod needs iOS 14 → bumped
      `IPHONEOS_DEPLOYMENT_TARGET` 13.0→14.0 (all 3 configs in `project.pbxproj`). Verify on a Mac `pod install`.
- [x] **IAP** — `lib/services/iap_service.dart` (registered as `ServiceLocator.iap`): listens to
      `InAppPurchase.purchaseStream`, queries products (Apple `ERSplitPremium24356`/`CoHarmonyPremiumAnnual`,
      Google `ezsplit_premium_monthly`), buys, validates via `subscription.validateAppleTransaction`/
      `validateGooglePurchase`, completes the purchase. `subscription_page` CTA → buy(plan), Restore → restore(),
      result-stream feedback + busy spinner. Android `com.android.vending.BILLING` permission added.

- [x] **Firebase push (Android only)** — deps `firebase_core` + `firebase_messaging`; `google-services.json`
      in `android/app/`; google-services Gradle plugin applied (`settings.gradle.kts` + `app/build.gradle.kts`)
      so the native config is read (no `firebase_options.dart` needed for Android-only); `minSdk = 23`;
      `POST_NOTIFICATIONS` permission. `lib/services/push_service.dart` (`ServiceLocator.push`) GUARDS every
      Firebase call with `Platform.isAndroid` — on iOS it's a no-op so the pods stay inert (no init, no crash,
      matching MAUI which never configured iOS push). `push.init()` is called from both dashboards' initState
      (post-login, so the user email is set): `Firebase.initializeApp` → requestPermission → `getToken` →
      `NotificationService.registerDeviceToken(platform:'android')` (+ onTokenRefresh re-register).
      Needs a device/Gradle build to confirm the plugin + pods resolve, but the Dart analyzes clean.

### Phase 3 — remaining (local/native, lower priority)
- [x] **File Vault — DONE.** `lib/features/filevault/file_vault_page.dart` is now a real on-device file
      manager rooted at `<getApplicationSupportDirectory()>/PrivateLocker` (MAUI used `AppDataDirectory`).
      Folders/files in a 3-col grid, drill-down nav + back (PopScope), multi-select delete, import from
      camera (`image_picker`)/files (`file_picker`)/photo library (`image_picker.pickMultipleMedia`),
      new-folder, per-item share (`share_plus`)/rename/delete via long-press sheet, immersive image viewer +
      system viewer (`open_filex`) for docs/videos, search + extension filter. Pure local FS, no API. Deps
      added: `file_picker`, `open_filex`, `path`. No new perms needed (camera/photos already declared).
- [x] **Sentry — DONE.** `lib/services/telemetry_config.dart` (DSN + `coharmony@1.0.0` release, port of
      `TelemetryConfig.cs`). `main.dart` wraps startup in `SentryFlutter.init` (env debug/production via
      `kReleaseMode`, `sendDefaultPii=false`, `tracesSampleRate=0.0`, `attachScreenshot=false`, session
      tracking on — matches MAUI `UseSentry`) and sets `AnalyticsService.reporter` to capture each conversion
      as an Info-level `'conversion: <name>'` message with the event tags. The 32 `AnalyticsService.*` call
      sites were already wired. Dep: `sentry_flutter`.
- [x] **Calendar export — REMOVED from BOTH apps (user request 2026-06-02: it spammed the device calendar).**
      Flutter: deleted `calendar_export_service.dart` + its ServiceLocator registration, the schedule-tab
      "Export to Calendar" button + the whole `_ExportOptionsDialog`; dropped `device_calendar` / `timezone` /
      `flutter_timezone` deps, the READ/WRITE_CALENDAR Android perms, and the NSCalendars* iOS usage strings.
      MAUI: deleted `Services/CalendarExportService.cs` + its `MauiProgram` DI registration, the
      `Scedule.xaml` export button + `ExportPopup`, and the two export `#region`s in `Scedule.xaml.cs`
      (handlers + duration state). `.ics` share went away with it (was part of the same popup).

### Phase 3 — final gap-closure pass (all MAUI features except voice assistant) ✅ DONE (analyzes clean)
The "what's missing vs MAUI" sweep — everything implemented except `VoiceIntentService` (Siri/App Intents).
- [x] **Map actions** — `map_page.dart` Add-POI now creates at the tapped/selected pin (or current
      location): `AddPoiPopup` → `getAddressFromCoordinates` → `createPoi` → reload; pin details
      Record/Records/Navigate; `_createRecord` verifies ≤200m proximity (Geolocator.distanceBetween)
      before `createLocationRecord`; filter popup (POIs/transfers). `platform_map.dart` gained `onTap`
      + violet selected-pin hue.
- [x] **Notifications (foreground)** — `push_service.dart` listens `FirebaseMessaging.onMessage`/
      `onMessageOpenedApp`/`getInitialMessage`; `notification_service.dart` `initLocalNotifications()` +
      immediate `.show` for `scheduleLocalNotification`; `handleNotificationReceived` shows an overlay
      banner (`widgets/app_notification_banner.dart`, port of MAUI InAppNotificationBanner styling,
      suppressed while `AppNavigation.inChat`) and `handleNotificationTapped` routes via
      `AppNavigation.goToTab` / pushes PartnerPage. `main.dart` + `app_shell.dart` register the
      navigatorKey + goToTab sink.
- [x] **Chat attachments** — `chat_interface_page.dart`: pick (Photo Library/Files) → base64 →
      `encryptAttachment` → `{FileName,EncryptedData}` JSON sent via `sendMessage(attachmentBase64:)`;
      received attachment chip → action sheet View / Save to Files (share) / Camera Roll (gal, images) /
      Vault (PrivateLocker copy); `getAttachment` → `decryptAttachment` → bytes → image viewer or OpenFilex.
- [x] **Subscription Manage/Cancel** — `subscription_page.dart` is now status-driven (port of MAUI
      `UpdateUI`): inactive states show the paywall; Active/SharedActive/TrialActive/GracePeriod show the
      accent status card + plan details + **Manage Subscription** sheet (View Details / Update Payment /
      Cancel Subscription, platform-specific store-settings copy) + **Continue to App**
      (`validateSubscription` → `routeAfterAuth`). Loads `getSubscriptionStatus()` on init.
- [x] **Security startup** — `lib/security/security_services.dart`: `KeyManagementService` (30-day device
      entropy rotation + `getSecureDeviceId`, stored under plain `KeyRotationDate`/`SecureDeviceId` keys via
      SecureStorageService) and `SecurityAuditService` (weekly audit: AES-GCM availability via
      `AesGcm.with256bits`, secure RNG, root/jailbreak file checks, TLS). Wired into `ServiceLocator.init`
      (`keyManagement..initialize()` + `if (securityAudit.shouldPerformAudit()) performSecurityAudit()`),
      mirroring `MauiProgram.CreateMauiApp`.
- [x] **Real platform tag** — `location_service.dart` `_deviceInfo` now returns `iOS`/`Android` (was `flutter`).
- DEFERRED (only remaining MAUI item): `VoiceIntentService` (Siri / App Intents) — native, intentionally skipped.

## Verify loop
`flutter analyze` after each service. Networked paths need a real run against the server to
fully verify; get everything written + self-consistent first. Git intentionally untouched.

## Native-not-1:1 caveats (don't fight these)
`SecureStorageService` device-entropy AES path, photo/media pickers, push registration,
`VoiceIntentService` (Siri/App Intents) map onto Flutter plugins, not literal translations.
