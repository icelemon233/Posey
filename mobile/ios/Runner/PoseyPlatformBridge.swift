import Flutter
import UIKit
import UserNotifications
import UniformTypeIdentifiers

final class PoseyPlatformBridge: NSObject, UIDocumentPickerDelegate {
  private static weak var current: PoseyPlatformBridge?
  private static var pendingJob: String?
  private let channel: FlutterMethodChannel
  private let io = DispatchQueue(label: "com.posey.camera.platform-files")
  private var documentResult: FlutterResult?
  private var exporting = false
  private var exportCopy: URL?
  private let limit = 1024 * 1024 * 1024
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.posey.camera/platform", binaryMessenger: messenger)
    super.init(); Self.current = self
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }
  static func openJob(_ id: String) { pendingJob = id; current?.channel.invokeMethod("openJob", arguments: id) }
  private func controller() -> UIViewController? {
    var view = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
    while let presented = view?.presentedViewController { view = presented }; return view
  }
  private func error(_ result: @escaping FlutterResult, _ message: String) { result(FlutterError(code: "platform_failed", message: message, details: nil)) }
  private func owned(_ path: String?) throws -> URL {
    guard let path else { throw PoseyNativeError(message: "文件不可用，请重新选择。") }
    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    let root = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
    guard url.path.hasPrefix(root + "/"), FileManager.default.fileExists(atPath: url.path),
      let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]).fileSize,
      size <= limit else { throw PoseyNativeError(message: "文件不可用或超过 1 GB。") }; return url
  }
  private func folder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
  }
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "openSettings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else { error(result, "系统设置无法打开。"); return }
      UIApplication.shared.open(url) { opened in if opened { result(nil) } else { self.error(result, "系统设置无法打开。") } }
    case "requestNotifications":
      let center = UNUserNotificationCenter.current()
      center.getNotificationSettings { settings in
        if settings.authorizationStatus == .notDetermined {
          center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in DispatchQueue.main.async { result(granted) } }
        } else { DispatchQueue.main.async { result(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) } }
      }
    case "pendingJob": result(Self.pendingJob); Self.pendingJob = nil
    case "ackJob": if args["jobId"] as? String == Self.pendingJob { Self.pendingJob = nil }; result(nil)
    case "appInfo": result(["name": "Posey", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
      "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "", "developer": "Cinna"])
    case "shareFiles":
      guard let paths = args["paths"] as? [String], !paths.isEmpty, paths.count <= 100 else { error(result, "一次最多分享 100 张照片。"); return }
      io.async {
        do {
          let folder = try self.folder("Posey-share")
          let copies = try paths.map { path -> URL in
            let source = try self.owned(path)
            guard (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 24 * 1024 * 1024 else { throw PoseyNativeError(message: "照片过大。") }
            let copy = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
            try FileManager.default.copyItem(at: source, to: copy); return copy
          }
          DispatchQueue.main.async {
            guard let view = self.controller() else { self.error(result, "分享界面无法打开。"); return }
            let share = UIActivityViewController(activityItems: copies, applicationActivities: nil)
            share.popoverPresentationController?.sourceView = view.view
            share.popoverPresentationController?.sourceRect = CGRect(x: view.view.bounds.midX, y: view.view.bounds.midY, width: 1, height: 1)
            view.present(share, animated: true); result(nil)
          }
        } catch { DispatchQueue.main.async { self.error(result, "照片未能分享，请检查文件与存储空间。") } }
      }
    case "exportFile":
      guard documentResult == nil else { error(result, "请先完成文件选择。"); return }
      documentResult = result; exporting = true
      io.async {
        do {
          let source = try self.owned(args["path"] as? String)
          let name = URL(fileURLWithPath: args["name"] as? String ?? "Posey-backup.zip").lastPathComponent
          let copy = try self.folder("Posey-export").appendingPathComponent(name)
          try? FileManager.default.removeItem(at: copy); try FileManager.default.copyItem(at: source, to: copy)
          DispatchQueue.main.async {
            guard let view = self.controller() else { self.finishDocument(error: "文件界面无法打开。"); return }
            self.exportCopy = copy
            let picker = UIDocumentPickerViewController(forExporting: [copy], asCopy: true); picker.delegate = self
            view.present(picker, animated: true)
          }
        } catch { DispatchQueue.main.async { self.finishDocument(error: "备份未能导出，请检查存储空间。") } }
      }
    case "importFile":
      guard documentResult == nil, let view = controller() else { error(result, "请先完成文件选择。"); return }
      documentResult = result; exporting = false
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true); picker.delegate = self
      view.present(picker, animated: true)
    case "clearTemporaryFiles":
      guard documentResult == nil else { error(result, "请先完成文件选择。"); return }
      io.async {
        var bytes = 0
        for name in ["Posey-share", "Posey-export", "Posey-import"] {
          let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
          for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            do { try FileManager.default.removeItem(at: file); bytes += size } catch { }
          }
        }; DispatchQueue.main.async { result(bytes) }
      }
    case "storageUsage":
      io.async {
        var bytes = 0, recoveries = 0
        let roots = [URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents"), URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support"), FileManager.default.temporaryDirectory]
        for root in roots {
          let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
          while let url = enumerator?.nextObject() as? URL {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true {
              bytes += values.fileSize ?? 0; if url.lastPathComponent.hasPrefix("recovery-") { recoveries += 1 }
            }
          }
        }; DispatchQueue.main.async { result(["bytes": bytes, "recoveryCopies": recoveries]) }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finishDocument(value: exporting ? false : nil) }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if exporting { finishDocument(value: true); return }
    guard let source = urls.first else { finishDocument(); return }
    io.async {
      let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
      do {
        guard let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= self.limit else { throw PoseyNativeError(message: "备份超过 1 GB。") }
        let copy = try self.folder("Posey-import").appendingPathComponent("\(UUID().uuidString).zip")
        try FileManager.default.copyItem(at: source, to: copy)
        DispatchQueue.main.async { self.finishDocument(value: copy.path) }
      } catch { DispatchQueue.main.async { self.finishDocument(error: "备份未能读取，请检查文件访问权限与存储空间。") } }
    }
  }
  private func finishDocument(value: Any? = nil, error message: String? = nil) {
    let result = documentResult; documentResult = nil
    if let copy = exportCopy { try? FileManager.default.removeItem(at: copy) }; exportCopy = nil
    if let message, let result { error(result, message) } else { result?(value) }
  }
}
