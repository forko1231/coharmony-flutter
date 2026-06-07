import Flutter
import UIKit
import PushKit
import UserNotifications
import flutter_callkit_incoming

// iOS uses native Apple MapKit (via apple_maps_flutter), matching the MAUI app — no
// Google Maps SDK key is required on iOS. Android still uses Google Maps (key in the
// AndroidManifest).
//
// Calls: iOS requires a VoIP push (PushKit) to wake a killed app and show the native
// CallKit incoming-call screen. We register for VoIP pushes here, hand the token to
// the flutter_callkit_incoming plugin (which forwards it to Dart so it can be
// registered with Azure Notification Hub), and on an incoming VoIP push we report the
// call to CallKit immediately — Apple requires this on every VoIP push.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  // Channel for STANDARD APNs alert notifications (schedule changes, reminders, messages).
  // Separate from the VoIP/PushKit path used for calls.
  private var pushChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register for VoIP pushes (calls).
    let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [PKPushType.voIP]

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Bridge for standard remote (alert) notifications — Dart asks us to register, we hand
    // back the raw APNs token (no Firebase on iOS; the token goes to Azure Notification Hub).
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "coharmony/push", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, res in
        if call.method == "registerForPush" {
          self?.registerForStandardPush()
          res(nil)
        } else {
          res(FlutterMethodNotImplemented)
        }
      }
      pushChannel = channel
    }
    return result
  }

  /// Ask for notification permission, then register for standard remote notifications.
  private func registerForStandardPush() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      guard granted else { return }
      DispatchQueue.main.async {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }

  /// Standard APNs token → hand to Dart to register with the Notification Hub (platform "ios").
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    pushChannel?.invokeMethod("onApnsToken", arguments: token)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    NSLog("[push] APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  /// A remote (alert) notification arrived / was tapped → forward its data for routing.
  override func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    if let data = userInfo["data"] as? [String: Any] {
      pushChannel?.invokeMethod("onApnsTap", arguments: data)
    }
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - PKPushRegistryDelegate

  /// New/updated VoIP token → hand to the plugin, which raises
  /// `Event.actionDidUpdateDevicePushTokenVoIP` in Dart so we can register it
  /// with the server (Azure Notification Hub).
  func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  /// Incoming VoIP push. We MUST report a call to CallKit synchronously here or
  /// iOS will throttle/stop delivering VoIP pushes to the app.
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    // The backend nests the call fields under "data"; fall back to top level.
    // `dictionaryPayload` is [AnyHashable: Any]; coerce to [String: Any] (VoIP
    // payload keys are strings) so the lookups below are well-typed.
    let root = payload.dictionaryPayload
    let data: [String: Any] = (root["data"] as? [String: Any])
      ?? (root as? [String: Any])
      ?? [:]

    let roomName = (data["roomName"] as? String) ?? ""
    let callerName = (data["callerName"] as? String) ?? "Incoming call"
    let callerEmail = (data["callerEmail"] as? String) ?? ""
    let hasVideo = (data["hasVideo"] as? String == "true") || (data["hasVideo"] as? Bool == true)

    let callkitData = flutter_callkit_incoming.Data(
      id: UUID().uuidString,
      nameCaller: callerName,
      handle: callerEmail,
      type: hasVideo ? 1 : 0
    )
    callkitData.appName = "CoHarmony"
    callkitData.duration = 45000
    // Carried so the Dart accept handler can join the right LiveKit room.
    callkitData.extra = [
      "roomName": roomName,
      "callerEmail": callerEmail,
      "callerName": callerName,
      "hasVideo": hasVideo,
    ] as NSDictionary

    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(callkitData, fromPushKit: true)
    completion()
  }
}
