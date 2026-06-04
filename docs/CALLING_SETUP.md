# Voice/Video Calling — Setup & Native Configuration

This app does voice/video calls with **LiveKit** (self-hosted WebRTC SFU) and shows
**native incoming-call screens** (CallKit on iOS, full-screen incoming on Android)
via `flutter_callkit_incoming`, with **Whisper** for post-call transcription.

Most of the code is wired. The items below are the **manual** platform/cloud steps
that can't be done in Dart/C# and must be completed before calls work end-to-end.

---

## 1. Flutter packages
```bash
cd coharmony-flutter
flutter pub get
```
Adds `livekit_client`, `permission_handler`, `flutter_callkit_incoming`, `uuid`.

## 2. LiveKit server (Azure)
- Run `livekit/livekit-server` (Azure Container App or VM).
- Ports: 7880 (HTTP/API), 7881 (TURN/TLS), 50000–60000/UDP (RTC media).
- Set in **Azure Key Vault**:
  - `LiveKit__ApiKey`, `LiveKit__ApiSecret` (the server's `LIVEKIT_KEYS` pair)
  - `LiveKit__Url` (informational; the app uses its own URL below)
- Point the Flutter app at it via `--dart-define=LIVEKIT_URL=wss://livekit.ez-split.com`
  (default is `wss://livekit.ez-split.com` in `ServiceLocator.livekitUrl`).

## 3. Whisper microservice (Azure)
- Deploy `whisper-service/` (FastAPI + openai-whisper) as an Azure Container App.
- Set `Whisper__BaseUrl` in Key Vault (e.g. `https://whisper.ez-split.com`).
- Transcription only runs when a call has a `RecordingUrl`. To get recordings,
  enable **LiveKit Egress** (room composite → Azure Blob) and write the blob URL
  onto the `CallSession.RecordingUrl` before `EndCallAsync` (TODO: egress webhook).

## 4. Backend DB migration
```bash
cd SplitServer/SplitServer/SplitServer
dotnet ef migrations add AddCallSession
dotnet ef database update   # or let the app apply on startup
```

## 5. Android — native incoming call
- Permissions are already in `AndroidManifest.xml` (RECORD_AUDIO, CAMERA,
  USE_FULL_SCREEN_INTENT, MANAGE_OWN_CALLS, FOREGROUND_SERVICE*).
- `flutter_callkit_incoming` merges its own receivers/activity via the plugin
  manifest — no manual service needed.
- FCM **data-only, high-priority** messages drive the background full-screen UI.
  The backend `SendCallPushAsync` already sends `android.priority = "high"` with no
  notification block, and `callFcmBackgroundHandler` (registered in `PushService`)
  shows the native screen from a killed state.
- Android 14+: the system grants USE_FULL_SCREEN_INTENT to calling apps; no extra
  runtime prompt for this category.

## 6. iOS — CallKit + VoIP push (PushKit)

**Already wired in code:**
- `ios/Runner/AppDelegate.swift` — PushKit registration, VoIP-token forwarding,
  and `didReceiveIncomingPushWith` → reports the call to CallKit (Apple requires
  this on every VoIP push).
- `ios/Runner/Runner.entitlements` (`aps-environment`) created and referenced from
  all three Runner build configs in the Xcode project.
- `Info.plist` has `UIBackgroundModes: audio, voip` + mic/camera usage strings.
- Dart registers the VoIP token with the server post-login
  (`CallKitService.registerVoipToken`, called from the dashboards) and re-registers
  on token refresh. Backend sends `apns-push-type: voip` + `apns-topic:
  com.456746.ezsplit.voip` (override via `Apple:VoipTopic`).

**You still need to do (Apple account — can't be done in code):**
1. **Xcode capabilities** (Runner target → Signing & Capabilities) — tick the boxes
   so the provisioning profile includes them: **Push Notifications** and
   **Background Modes → Voice over IP + Audio**. (The entitlement/plist entries
   already exist; this makes the signing profile match.)
2. **APNs credential on Azure Notification Hub** — create an **APNs Auth Key (.p8)**
   in the Apple Developer portal and add it to your Notification Hub's Apple (APNS)
   settings with the **Key ID**, **Team ID**, and **App Bundle ID**
   `com.456746.ezsplit`. Token (.p8) auth lets the hub sign for the `.voip` topic.
   (A VoIP Services .p12 cert also works but a .p8 key is simpler and never expires.)
3. `pod install` in `ios/` after `flutter pub get` so the `flutter_callkit_incoming`
   pod (imported by `AppDelegate.swift`) is built.

> With the .p8 key uploaded and the two capabilities ticked, iOS calls ring the
> native CallKit screen even when the app is killed. Until then, iOS still rings via
> the foreground WebSocket path.

## 7. In-app entry points
- **Messages list**: each contact card has inline **voice** + **video** buttons;
  tapping the **avatar** opens the **Contact** page.
- **Contact page** (`ContactDetailPage`): Message / Voice / Video actions plus the
  full **call history** with expandable **transcripts**.
- **Chat header**: voice + video buttons.

## 8. Toggle
Calling is optional and gated by the `calling_enabled` preference
(`Preferences.getBool('calling_enabled', true)`). When false, the call buttons are
hidden everywhere and incoming native rings are suppressed in-app.

---

## Flow summary
1. Caller taps voice/video → `POST /api/calls/initiate` → LiveKit room + token.
2. Server pushes `call_incoming` over WebSocket (foreground) **and** a high-priority
   call push (background/killed) → recipient sees the **native** incoming screen.
3. Accept → `POST /api/calls/join` → token → both join the LiveKit room → `CallScreen`.
4. Hang up → `POST /api/calls/end` → session marked ended; Whisper runs if a
   recording exists. Decline → `POST /api/calls/reject`, logged as missed.
