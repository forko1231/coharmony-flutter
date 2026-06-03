# CoHarmony — MAUI → Flutter port manifest

Source of truth = the MAUI app at `../EZSplit/EZSplit`. This tracks every screen/component
so the port is methodical and nothing is missed. Port order: **UI shells first** (fast,
clickable on web), **then business logic / services**, **then native integrations last**.

Status legend: `[ ]` not started · `[~]` UI shell done (static, no logic) · `[x]` UI + logic wired.

## Conventions
- Theme tokens: `lib/theme/app_colors.dart` (raw, from `Colors.xaml`) + `app_palette.dart`
  (theme-aware, = MAUI `AppThemeBinding`). Use `context.palette.*` and `AppColors.*`.
- One folder per feature under `lib/features/<area>/`; shared widgets in `lib/widgets/`.
- API models/services under `lib/services/` + `lib/models/` (phase 2).

## Foundation
- [x] Design tokens (colors, palette, theme)
- [x] App entry (`main.dart`)
- [x] Assets copied (70 svg + 11 png → `assets/images/`) + `flutter_svg` + `AppIcon` widget
- [ ] Fonts reconciled with MAUI `Styles.xaml`
- [ ] Routing (go_router) + auth gate
- [ ] Shared widgets: gradient button, card/Border, skeleton box, in-app banner, bottom-sheet host
- [~] App shell: 5-tab bottom nav → `features/shell/app_shell.dart` (all 5 tabs wired: Home / Schedule / Messager / Payments / Map)
- [~] Child app shell (separate nav for child accounts) → `features/child/child_app_shell.dart`

## Auth / Login  (`Views/Login`)   → `lib/features/auth/`
- [~] MainPage (landing/splash) → `landing_page.dart`
- [~] Login → `login_page.dart`
- [~] AccountCreation → `account_creation_page.dart` (incl. live password-strength meter)
- [~] ForgotPasswordPage → `forgot_password_page.dart`
- [~] VerifyPasswordPage → `verify_password_page.dart`
- [~] ResetPasswordPage → `reset_password_page.dart`
- [~] VerifyMFA → `verify_mfa_page.dart`
- shared input: `auth_simple_input.dart`

Shared widgets built so far: `app_icon`, `app_header`, `app_input_box` (+`AppTextField`),
`primary_button` (gradient, themeable), `section_card`, `bottom_action_bar`.

## Onboarding  (`Views/Onboarding` + `Views/Schedule/Templates`)   → `lib/features/onboarding/` + `lib/features/schedule/templates/`
- [~] OnboardingRoleChoicePage → `onboarding/role_choice_page.dart`
- [~] OnboardingPartnerInvitePage → `onboarding/partner_invite_page.dart` (3 modes)
- [~] OnboardingScheduleReviewPage → `onboarding/schedule_review_page.dart`
- [~] OnboardingTemplateApplyPage → `onboarding/template_apply_page.dart`
- [~] OnboardingScheduleSentPage → `onboarding/schedule_sent_page.dart`
- [~] OnboardingTourPage → `onboarding/tour_page.dart` (5-card PageView)
- [~] TemplateCatalogPage → `schedule/templates/template_catalog_page.dart` (8 real templates, grouped)
- [~] CustodyStartChoicePage → `schedule/templates/custody_start_choice_page.dart`
- [~] TemplateConfigPage → `schedule/templates/template_config_page.dart`
- shared: `onboarding/onboarding_step_header.dart`, `widgets/hero_orb.dart`

## Main  (`Views/Main`)   → `lib/features/main/`
- [~] MainMenu (Home hub) → `main_menu_page.dart` (all cards + live mini-month calendar)
- [~] Settings → `settings_page.dart` (account/personal/app-settings/connections/export/danger/version)
- [~] PartnerPage → `partner_page.dart` (declarative, stub model; co-parent/children/lawyers + 4-step children-help modal)
- [~] ExportDataPage → `export_data_page.dart` (5 report cards)

## Schedule  (`Views/Schedule`)   → `lib/features/schedule/`
- [~] Scedule (tab calendar) → `schedule_page.dart` (month nav + shaded calendar + metrics + export-options modal); wired to shell Schedule tab
- [~] CustodySchedule (proposal editor) → `custody_schedule_page.dart` (week view, day/override sheets, accept/reject/counter, 8-step onboarding)
- [~] DayEditorView (component) → `day_editor_view.dart`
- [~] OverrideEditorView (component) → `override_editor_view.dart`
- [~] AddEventPopupView → `add_event_popup.dart`
- [~] DateData → `date_data_page.dart` (24-hour timeline + info cards)
- [~] TwelveHourTimePicker (control) → `twelve_hour_time_picker.dart`
- shared: `custody_parent.dart` (Dad/Mom/Both/None enum + colors)

## Messaging  (`Views/Messaging`)   → `lib/features/messaging/`
- [~] Messaging (conversation list) → `messaging_page.dart` (AI card, grouped contacts, encryption info); wired to shell Messager tab
- [~] ChatInterface (thread) → `chat_interface_page.dart` (bubbles, encrypted header, input bar) — real-time + E2E encryption are phase 2/3

## Map  (`Views/Map`)   → `lib/features/map/`
- [~] MapPage → `map_page.dart` (placeholder map surface + search/FAB/pins overlay); wired to shell Map tab. Live map SDK = phase 3
- [~] LocationRecordsPage → `location_records_page.dart` (summary + records list + filter sheet)
- [~] AddPoiPopupView → `map_popups.dart` (AddPoiPopup)
- [~] AddRecordPopupView → `map_popups.dart` (AddRecordPopup)
- [~] FilterPopupView → `map_popups.dart` (MapFilterPopup)
- [~] PinDetailsPopupView → `map_popups.dart` (PinDetailsPopup)

## Finances  (`Views/Finances`)   → `lib/features/finances/`
- [~] PaymentTracker (split payments) → `payment_tracker_page.dart` (month nav, in/out tabs, payment list, add-payment sheet w/ split slider, summary sheet); wired to shell Payments tab

## File Vault  (`Views/FileVault`)   → `lib/features/filevault/`
- [~] Filevault (encrypted documents) → `file_vault_page.dart` (3-col grid, search, add-to-vault menu, empty state). Encryption/storage = phase 2/3

## AI  (`Views/AI`)   → `lib/features/ai/`
- [~] AiChatPage → `ai_chat_page.dart` (welcome state + suggestion chips, bubbles, input bar)

## Subscription
- [~] SubscriptionPage (paywall — monthly + annual) → `features/subscription/subscription_page.dart`

## Tutorial
- [x] TutorialPage — REMOVED. The replay entry was deleted from Settings in both the MAUI and Flutter projects (per user); the standalone tutorial is not ported.

## Child mode  (`Views/Child`)   → `lib/features/child/`
- [~] ChildAppShell → `child_app_shell.dart` (3-tab nav: Home/Schedule/Messages)
- [~] ChildMainMenu → `child_main_menu.dart` (stats, mini-month, messages/family cards)
- [~] ChildSchedulePage → `child_schedule_page.dart` (read-only shaded calendar + day detail)
- [~] ChildMessagingPage → `child_messaging_page.dart` (parent contacts → shared chat thread)
- [~] ChildFamilyPage → `child_family_page.dart`
- [~] ChildSettingsPage → `child_settings_page.dart` (child-account badge, theme, leave family)
- [~] ChildWaitingPage → `child_waiting_page.dart`
- [~] ChildInvitePage → `child_invite_page.dart`

## Phase 2 — business logic / services (after UI shells)
- [ ] API client + auth/token refresh (`BaseApiService`, `TokenService`, `AuthService`)
- [ ] Secure storage
- [ ] Custody proposal service + diff/baseline logic
- [ ] Holiday resolver + custody templates
- [ ] Financial service
- [ ] WebSocket (real-time messaging)
- [ ] Notifications (Firebase push + reminders)
- [ ] Location / address search
- [ ] Calendar export

## Phase 3 — native / risky (last)
- [ ] Message E2E encryption + key management (MUST be byte-compatible with server)
- [ ] In-app purchases (StoreKit + Play Billing, monthly + annual)
- [ ] Push notifications wiring
- [ ] iOS Siri/App Intents / voice (platform channels)
- [ ] Photo picker / file preview / media
