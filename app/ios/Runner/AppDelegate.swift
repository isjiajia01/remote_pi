import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var dartReady = false
  private var pendingTap: [String: Any]?
  private var deviceToken: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PerchPush")!
    let channel = FlutterMethodChannel(name: "dev.zhangjiajia.perch/push", binaryMessenger: registrar.messenger())
    pushChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "ready":
        self.dartReady = true
        if let token = self.deviceToken { channel.invokeMethod("token", arguments: token) }
        if let tap = self.pendingTap {
          self.pendingTap = nil
          channel.invokeMethod("tap", arguments: tap)
        }
        result(nil)
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { allowed, error in
          DispatchQueue.main.async {
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
            if let error {
              result(FlutterError(code: "notification_permission", message: error.localizedDescription, details: nil))
            } else { result(allowed) }
          }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    let hex = token.map { String(format: "%02x", $0) }.joined()
    deviceToken = hex
    if dartReady { pushChannel?.invokeMethod("token", arguments: hex) }
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: token)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let info = response.notification.request.content.userInfo
    // Navigation hints only; approval authority always comes from the live channel.
    var tap: [String: Any] = [:]
    for key in ["kind", "event_id", "session_id", "tool_call_id"] {
      if let value = info[key] as? String { tap[key] = value }
    }
    if dartReady { pushChannel?.invokeMethod("tap", arguments: tap) }
    else { pendingTap = tap }
    completionHandler()
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound])
  }
}
