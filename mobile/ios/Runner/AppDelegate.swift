import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var backgroundBridge: PoseyFlutterBackgroundBridge?
  private var platformBridge: PoseyPlatformBridge?
  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    PoseyBackgroundAIManager.shared.activate()
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    UNUserNotificationCenter.current().delegate = self
    return launched
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PoseyBackgroundAI") {
      backgroundBridge = PoseyFlutterBackgroundBridge(messenger: registrar.messenger())
      platformBridge = PoseyPlatformBridge(messenger: registrar.messenger())
    }
  }
  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    if let id = response.notification.request.content.userInfo["poseyJobId"] as? String, UUID(uuidString: id) != nil {
      PoseyPlatformBridge.openJob(id)
    }
    completionHandler()
  }
  override func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void) {
    guard identifier == "com.posey.camera.ai-pose" else {
      super.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler); return
    }
    PoseyBackgroundAIManager.shared.setSessionCompletionHandler(completionHandler)
  }
}

private final class PoseyFlutterBackgroundBridge {
  private let channel: FlutterMethodChannel
  private let io = DispatchQueue(label: "com.posey.camera.ai-bridge")
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.posey.camera/background-ai", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      let manager = PoseyBackgroundAIManager.shared
      if call.method == "start" && UIApplication.shared.applicationState != .active {
        result(FlutterError(code: "not_foreground", message: "请在应用内提交生成任务。", details: nil)); return
      }
      self?.io.async {
        do {
          let value: Any?
          switch call.method {
          case "start": value = ["jobId": try manager.start(args)]
          case "getJobs": value = ["jobs": try manager.payloads()]
          case "getImage":
            let bytes = try manager.image(id: try manager.id(args), source: args["source"] as? Bool == true)
            value = bytes.map { FlutterStandardTypedData(bytes: $0) }
          case "cancel", "clear": try manager.cancel(id: try manager.id(args), remove: call.method == "clear"); value = nil
          case "repairHistory": try manager.repairHistory(); value = nil
          case "retryResult": try manager.retryResult(id: try manager.id(args)); value = nil
          default: DispatchQueue.main.async { result(FlutterMethodNotImplemented) }; return
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          let message = (error as? PoseyNativeError)?.message ?? "后台任务未能处理，请检查存储空间后重试。"
          DispatchQueue.main.async { result(FlutterError(code: "background_failed", message: message, details: nil)) }
        }
      }
    }
  }
}
