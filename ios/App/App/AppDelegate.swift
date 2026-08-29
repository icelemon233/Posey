import UIKit
import Capacitor
import WebKit
import Photos
import AVFoundation
import UserNotifications

@objc(PoseyPhotoPlugin)
final class PoseyPhotoPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "PoseyPhotoPlugin"
    let jsName = "PoseyPhoto"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "savePhoto", returnType: CAPPluginReturnPromise)
    ]

    @objc func savePhoto(_ call: CAPPluginCall) {
        guard let dataURL = call.getString("dataUrl"),
              let comma = dataURL.firstIndex(of: ","),
              let imageData = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else {
            call.reject("照片数据无效，请重新拍摄")
            return
        }
        let fileName = call.getString("fileName") ?? "Posey.jpg"

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                call.reject("相册权限没打开。请到系统设置允许添加照片，然后再试一次。")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = fileName
                request.addResource(with: .photo, data: imageData, options: options)
            }) { saved, error in
                if saved {
                    call.resolve(["saved": true])
                } else {
                    call.reject(error?.localizedDescription ?? "照片没有保存成功")
                }
            }
        }
    }
}

private struct PoseyAIJobRecord: Codable {
    let id: String
    var state: String
    let createdAt: Double
    var completedAt: Double? = nil
    var targetTitle: String?
    var resultFile: String?
    var message: String?
}

private final class PoseyBackgroundAIManager: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    static let shared = PoseyBackgroundAIManager()

    private let maxActiveJobs = 3
    private let maxCompletedJobs = 20
    private let recordsKey = "posey.background-ai.jobs"
    private let stateQueue = DispatchQueue(label: "com.posey.camera.background-ai.state")
    private let responseLock = NSLock()
    private var responseData: [Int: Data] = [:]
    private var backgroundTasks: [String: UIBackgroundTaskIdentifier] = [:]
    private var sessionCompletionHandler: (() -> Void)?
    weak var plugin: PoseyBackgroundAIPlugin?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.posey.camera.ai-pose")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    func activate() {
        _ = session
        pruneCompletedHistory()
        scheduleNext()
    }

    func start(sourceImage: String, guideImage: String, prompt: String, apiKey: String, endpoint: String, model: String, targetTitle: String) throws -> String {
        guard let endpointURL = URL(string: endpoint), endpointURL.scheme == "https" else {
            throw NSError(domain: "PoseyBackgroundAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "AI Pose 服务地址无效"])
        }

        let jobID = UUID().uuidString
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "image": [sourceImage, guideImage],
            "size": "2K",
            "output_format": "jpeg",
            "response_format": "b64_json",
            "watermark": false
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let requestFile = jobsDirectory().appendingPathComponent("\(jobID)-request.json")
        try bodyData.write(to: requestFile, options: .atomic)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.uploadTask(with: request, fromFile: requestFile)
        task.taskDescription = jobID
        let initialState: String
        do {
            initialState = try enqueue(jobID: jobID, targetTitle: targetTitle)
        } catch {
            task.cancel()
            try? FileManager.default.removeItem(at: requestFile)
            throw error
        }
        if initialState == "generating" {
            beginBackgroundExecution(for: jobID)
            task.resume()
        }
        return jobID
    }

    func jobs() -> [PoseyAIJobRecord] {
        stateQueue.sync { loadRecords().sorted { $0.createdAt > $1.createdAt } }
    }

    func resultData(for record: PoseyAIJobRecord) -> Data? {
        guard let resultFile = record.resultFile else { return nil }
        return try? Data(contentsOf: jobsDirectory().appendingPathComponent(resultFile))
    }

    func cancel(jobID: String) {
        session.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == jobID }.forEach { $0.cancel() }
            self.clear(jobID: jobID)
            self.scheduleNext()
        }
    }

    func clear(jobID: String) {
        let removed = stateQueue.sync { () -> PoseyAIJobRecord? in
            var records = loadRecords()
            let record = records.first { $0.id == jobID }
            records.removeAll { $0.id == jobID }
            saveRecords(records)
            return record
        }
        try? FileManager.default.removeItem(at: jobsDirectory().appendingPathComponent("\(jobID)-request.json"))
        if let resultFile = removed?.resultFile {
            try? FileManager.default.removeItem(at: jobsDirectory().appendingPathComponent(resultFile))
        }
        endBackgroundExecution(for: jobID)
    }

    func setSessionCompletionHandler(_ handler: @escaping () -> Void) {
        activate()
        sessionCompletionHandler = handler
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseLock.lock()
        responseData[dataTask.taskIdentifier, default: Data()].append(data)
        responseLock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let jobID = task.taskDescription, jobs().contains(where: { $0.id == jobID }) else { return }
        responseLock.lock()
        let data = responseData.removeValue(forKey: task.taskIdentifier) ?? Data()
        responseLock.unlock()

        defer {
            try? FileManager.default.removeItem(at: jobsDirectory().appendingPathComponent("\(jobID)-request.json"))
            endBackgroundExecution(for: jobID)
            scheduleNext()
        }

        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            finish(jobID: jobID, state: "failed", resultData: nil, message: "AI Pose 暂时生成失败，请稍后再试")
            return
        }
        if let error = error as NSError?, error.code == NSURLErrorCancelled { return }

        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            finish(jobID: jobID, state: "failed", resultData: nil, message: publicError(statusCode: statusCode, responseData: data))
            return
        }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = payload["data"] as? [[String: Any]],
              let base64 = items.first?["b64_json"] as? String,
              let imageData = Data(base64Encoded: base64) else {
            finish(jobID: jobID, state: "failed", resultData: nil, message: "AI Pose 没有返回可用图片")
            return
        }
        finish(jobID: jobID, state: "completed", resultData: imageData, message: nil)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.sessionCompletionHandler?()
            self.sessionCompletionHandler = nil
        }
    }

    private func finish(jobID: String, state: String, resultData: Data?, message: String?) {
        var resultFile: String?
        if let resultData {
            let fileName = "\(jobID)-result.jpg"
            do {
                try resultData.write(to: jobsDirectory().appendingPathComponent(fileName), options: .atomic)
                resultFile = fileName
            } catch {
                finish(jobID: jobID, state: "failed", resultData: nil, message: "AI Pose 结果暂时无法保存")
                return
            }
        }
        let previous = jobs().first { $0.id == jobID }
        let record = PoseyAIJobRecord(
            id: jobID,
            state: state,
            createdAt: previous?.createdAt ?? Date().timeIntervalSince1970 * 1000,
            completedAt: state == "completed" ? Date().timeIntervalSince1970 * 1000 : previous?.completedAt,
            targetTitle: previous?.targetTitle,
            resultFile: resultFile,
            message: message
        )
        upsert(record)
        DispatchQueue.main.async {
            self.plugin?.notifyListeners("aiPoseJobUpdate", data: ["id": jobID, "state": state])
            if UIApplication.shared.applicationState != .active {
                self.scheduleNotification(state: state, jobID: jobID)
            }
        }
    }

    private func publicError(statusCode: Int, responseData: Data) -> String {
        if statusCode == 401 || statusCode == 403 { return "AI Pose 服务鉴权失败，请稍后再试" }
        if statusCode == 429 { return "AI Pose 现在有点忙，请稍后再试" }
        if let payload = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let error = payload["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        return "AI Pose 暂时生成失败，请稍后再试"
    }

    private func scheduleNotification(state: String, jobID: String) {
        let content = UNMutableNotificationContent()
        content.title = state == "completed" ? "AI Pose 已完成" : "AI Pose 生成失败"
        content.body = state == "completed" ? "生成结果已准备好，打开 Posey 查看。" : "打开 Posey 后可以重新生成。"
        content.sound = .default
        content.userInfo = ["poseyJobId": jobID]
        let request = UNNotificationRequest(identifier: "posey-ai-\(jobID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func upsert(_ record: PoseyAIJobRecord) {
        let removed = stateQueue.sync { () -> [PoseyAIJobRecord] in
            var records = loadRecords()
            records.removeAll { $0.id == record.id }
            records.append(record)
            let removed = trimCompletedHistory(&records)
            saveRecords(records)
            return removed
        }
        removeFiles(for: removed)
    }

    private func pruneCompletedHistory() {
        let removed = stateQueue.sync { () -> [PoseyAIJobRecord] in
            var records = loadRecords()
            let removed = trimCompletedHistory(&records)
            if !removed.isEmpty { saveRecords(records) }
            return removed
        }
        removeFiles(for: removed)
    }

    private func trimCompletedHistory(_ records: inout [PoseyAIJobRecord]) -> [PoseyAIJobRecord] {
        let completed = records
            .filter { $0.state == "completed" }
            .sorted { $0.createdAt > $1.createdAt }
        guard completed.count > maxCompletedJobs else { return [] }
        let removedIDs = Set(completed.dropFirst(maxCompletedJobs).map(\.id))
        let removed = records.filter { removedIDs.contains($0.id) }
        records.removeAll { removedIDs.contains($0.id) }
        return removed
    }

    private func removeFiles(for records: [PoseyAIJobRecord]) {
        records.forEach { record in
            try? FileManager.default.removeItem(at: jobsDirectory().appendingPathComponent("\(record.id)-request.json"))
            if let resultFile = record.resultFile {
                try? FileManager.default.removeItem(at: jobsDirectory().appendingPathComponent(resultFile))
            }
        }
    }

    private func enqueue(jobID: String, targetTitle: String) throws -> String {
        try stateQueue.sync {
            var records = loadRecords()
            let activeJobCount = records.filter { $0.state == "queued" || $0.state == "generating" }.count
            guard activeJobCount < maxActiveJobs else {
                throw NSError(
                    domain: "PoseyBackgroundAI",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "AI Pose 队列已满，最多同时处理 \(maxActiveJobs) 条"]
                )
            }
            let state = records.contains { $0.state == "generating" } ? "queued" : "generating"
            records.append(PoseyAIJobRecord(
                id: jobID,
                state: state,
                createdAt: Date().timeIntervalSince1970 * 1000,
                targetTitle: targetTitle,
                resultFile: nil,
                message: nil
            ))
            saveRecords(records)
            return state
        }
    }

    private func scheduleNext() {
        session.getAllTasks { tasks in
            let taskByJobID = Dictionary(uniqueKeysWithValues: tasks.compactMap { task in
                task.taskDescription.map { ($0, task) }
            })
            let selection = self.stateQueue.sync { () -> (String, Bool)? in
                var records = self.loadRecords()
                var reconciledInterruptedJob = false
                for index in records.indices where (records[index].state == "queued" || records[index].state == "generating") && taskByJobID[records[index].id] == nil {
                    records[index].state = "failed"
                    records[index].message = "任务已中断，请重新生成"
                    reconciledInterruptedJob = true
                }
                if let active = records.first(where: { $0.state == "generating" }), taskByJobID[active.id] != nil {
                    if reconciledInterruptedJob { self.saveRecords(records) }
                    return (active.id, false)
                }
                guard let nextIndex = records.indices
                    .filter({ records[$0].state == "queued" && taskByJobID[records[$0].id] != nil })
                    .min(by: { records[$0].createdAt < records[$1].createdAt }) else {
                        if reconciledInterruptedJob { self.saveRecords(records) }
                        return nil
                    }
                records[nextIndex].state = "generating"
                let jobID = records[nextIndex].id
                self.saveRecords(records)
                return (jobID, true)
            }
            guard let (jobID, promoted) = selection, let task = taskByJobID[jobID] else { return }
            if task.state == .suspended {
                self.beginBackgroundExecution(for: jobID)
                task.resume()
            }
            if promoted {
                DispatchQueue.main.async {
                    self.plugin?.notifyListeners("aiPoseJobUpdate", data: ["id": jobID, "state": "generating"])
                }
            }
        }
    }

    private func loadRecords() -> [PoseyAIJobRecord] {
        guard let data = UserDefaults.standard.data(forKey: recordsKey) else { return [] }
        return (try? JSONDecoder().decode([PoseyAIJobRecord].self, from: data)) ?? []
    }

    private func saveRecords(_ records: [PoseyAIJobRecord]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: recordsKey)
    }

    private func jobsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("PoseyAIJobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func beginBackgroundExecution(for jobID: String) {
        DispatchQueue.main.async {
            guard self.backgroundTasks[jobID] == nil else { return }
            let identifier = UIApplication.shared.beginBackgroundTask(withName: "Posey AI Pose") {
                self.endBackgroundExecution(for: jobID)
            }
            self.backgroundTasks[jobID] = identifier
        }
    }

    private func endBackgroundExecution(for jobID: String) {
        DispatchQueue.main.async {
            guard let identifier = self.backgroundTasks.removeValue(forKey: jobID), identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }
}

@objc(PoseyBackgroundAIPlugin)
final class PoseyBackgroundAIPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "PoseyBackgroundAIPlugin"
    let jsName = "PoseyBackgroundAI"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getJobs", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise)
    ]

    override func load() {
        PoseyBackgroundAIManager.shared.plugin = self
        PoseyBackgroundAIManager.shared.activate()
    }

    @objc func start(_ call: CAPPluginCall) {
        guard let sourceImage = call.getString("sourceImage"),
              let guideImage = call.getString("guideImage"),
              let prompt = call.getString("prompt"),
              let apiKey = call.getString("apiKey"),
              let endpoint = call.getString("endpoint"),
              let model = call.getString("model"),
              let targetTitle = call.getString("targetTitle") else {
            call.reject("AI Pose 任务信息不完整")
            return
        }
        do {
            let jobID = try PoseyBackgroundAIManager.shared.start(
                sourceImage: sourceImage,
                guideImage: guideImage,
                prompt: prompt,
                apiKey: apiKey,
                endpoint: endpoint,
                model: model,
                targetTitle: targetTitle
            )
            call.resolve(["jobId": jobID])
        } catch {
            call.reject(error.localizedDescription)
        }
    }

    @objc func getJobs(_ call: CAPPluginCall) {
        let jobs = PoseyBackgroundAIManager.shared.jobs().map { record -> [String: Any] in
            var payload: [String: Any] = [
                "id": record.id,
                "state": record.state,
                "createdAt": record.createdAt
            ]
            if let completedAt = record.completedAt { payload["completedAt"] = completedAt }
            if let message = record.message { payload["message"] = message }
            if let targetTitle = record.targetTitle { payload["targetTitle"] = targetTitle }
            if record.state == "completed", let data = PoseyBackgroundAIManager.shared.resultData(for: record) {
                payload["image"] = "data:image/jpeg;base64,\(data.base64EncodedString())"
            }
            return payload
        }
        call.resolve(["jobs": jobs])
    }

    @objc func cancel(_ call: CAPPluginCall) {
        guard let jobID = call.getString("jobId") else { call.reject("缺少任务编号"); return }
        PoseyBackgroundAIManager.shared.cancel(jobID: jobID)
        call.resolve()
    }

    @objc func clear(_ call: CAPPluginCall) {
        guard let jobID = call.getString("jobId") else { call.reject("缺少任务编号"); return }
        PoseyBackgroundAIManager.shared.clear(jobID: jobID)
        call.resolve()
    }
}

private enum PoseyPermissionCoordinator {
    static func requestInitialPermissions() {
        requestCameraPermission {
            requestPhotoAddPermission {
                requestNotificationPermission()
            }
        }
    }

    private static func requestCameraPermission(completion: @escaping () -> Void) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { completion(); return }
        AVCaptureDevice.requestAccess(for: .video) { _ in completion() }
    }

    private static func requestPhotoAddPermission(completion: @escaping () -> Void) {
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined else { completion(); return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in completion() }
    }

    private static func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        }
    }
}

final class PoseyBridgeViewController: CAPBridgeViewController {
    private let poseyBackground = UIColor(red: 1, green: 250 / 255, blue: 242 / 255, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = poseyBackground
        setNeedsStatusBarAppearanceUpdate()
    }

    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(PoseyPhotoPlugin())
        bridge?.registerPluginInstance(PoseyBackgroundAIPlugin())
        bridge?.registerPluginInstance(PoseySystemBarsPlugin())
    }

    override func webView(with frame: CGRect, configuration: WKWebViewConfiguration) -> WKWebView {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "-PoseyDebug"), arguments.indices.contains(flagIndex + 1) {
            let mode = String(reflecting: arguments[flagIndex + 1])
            let script = WKUserScript(
                source: "window.__POSEY_DEBUG__ = \(mode);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            configuration.userContentController.addUserScript(script)
        }
        #endif
        let webView = super.webView(with: frame, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = poseyBackground
        webView.scrollView.backgroundColor = poseyBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        return webView
    }
}

@objc(PoseySystemBarsPlugin)
final class PoseySystemBarsPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "PoseySystemBarsPlugin"
    let jsName = "PoseySystemBars"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setStyle", returnType: CAPPluginReturnPromise)
    ]

    @objc func setStyle(_ call: CAPPluginCall) {
        let darkContent = call.getBool("darkContent") ?? true
        let animated = call.getBool("animated") ?? false
        let fallbackColor = darkContent
            ? UIColor(red: 1, green: 250 / 255, blue: 242 / 255, alpha: 1)
            : UIColor(red: 13 / 255, green: 13 / 255, blue: 16 / 255, alpha: 1)
        let backgroundColor = color(from: call.getString("backgroundColor"), fallback: fallbackColor)
        DispatchQueue.main.async {
            self.bridge?.statusBarStyle = darkContent ? .darkContent : .lightContent
            let updateBackgrounds = {
                self.bridge?.viewController?.view.backgroundColor = backgroundColor
                self.bridge?.viewController?.view.window?.backgroundColor = backgroundColor
                self.bridge?.webView?.backgroundColor = backgroundColor
                self.bridge?.webView?.scrollView.backgroundColor = backgroundColor
            }
            if animated {
                UIView.animate(
                    withDuration: 0.32,
                    delay: 0,
                    options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction],
                    animations: updateBackgrounds
                ) { _ in call.resolve() }
            } else {
                updateBackgrounds()
                call.resolve()
            }
        }
    }

    private func color(from value: String?, fallback: UIColor) -> UIColor {
        guard let value else { return fallback }
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return fallback }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: 1
        )
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = UIColor(red: 1, green: 250 / 255, blue: 242 / 255, alpha: 1)
        window.rootViewController = PoseyBridgeViewController()
        window.makeKeyAndVisible()
        self.window = window
        UNUserNotificationCenter.current().delegate = self
        PoseyBackgroundAIManager.shared.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            PoseyPermissionCoordinator.requestInitialPermissions()
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == "com.posey.camera.ai-pose" else { completionHandler(); return }
        PoseyBackgroundAIManager.shared.setSessionCompletionHandler(completionHandler)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

}
