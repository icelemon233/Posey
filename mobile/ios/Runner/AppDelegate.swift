import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var backgroundBridge: PoseyFlutterBackgroundBridge?
  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    PoseyBackgroundAIManager.shared.activate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PoseyBackgroundAI") {
      backgroundBridge = PoseyFlutterBackgroundBridge(messenger: registrar.messenger())
    }
  }
  override func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void) {
    guard identifier == "com.posey.camera.ai-pose" else {
      super.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
      return
    }
    PoseyBackgroundAIManager.shared.setSessionCompletionHandler(completionHandler)
  }
}

private final class PoseyFlutterBackgroundBridge {
  private let channel: FlutterMethodChannel
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.posey.camera/background-ai", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      let manager = PoseyBackgroundAIManager.shared
      switch call.method {
      case "start":
        guard let source = arguments["sourceImage"] as? String,
          let guide = arguments["guideImage"] as? String, let prompt = arguments["prompt"] as? String,
          let key = arguments["apiKey"] as? String, let endpoint = arguments["endpoint"] as? String,
          let model = arguments["model"] as? String, let title = arguments["targetTitle"] as? String else {
          result(FlutterError(code: "invalid_job", message: "AI Pose 任务信息不完整", details: nil)); return
        }
        do {
          let id = try manager.start(sourceImage: source, guideImage: guide, prompt: prompt,
            apiKey: key, endpoint: endpoint, model: model, targetTitle: title)
          result(["jobId": id])
        } catch { result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil)) }
      case "getJobs":
        let known = Set(arguments["knownResults"] as? [String] ?? [])
        let jobs = manager.jobs().map { record -> [String: Any] in
          var payload: [String: Any] = ["id": record.id, "state": record.state, "createdAt": record.createdAt]
          if let value = record.completedAt { payload["completedAt"] = value }
          if let value = record.message { payload["message"] = value }
          if let value = record.targetTitle { payload["targetTitle"] = value }
          if record.state == "completed", !known.contains(record.id), let data = manager.resultData(for: record) {
            payload["image"] = "data:image/jpeg;base64,\(data.base64EncodedString())"
          }
          return payload
        }
        result(["jobs": jobs])
      case "cancel", "clear":
        guard let id = arguments["jobId"] as? String else {
          result(FlutterError(code: "invalid_job", message: "缺少任务编号", details: nil)); return
        }
        if call.method == "cancel" { manager.cancel(jobID: id) } else { manager.clear(jobID: id) }
        result(nil)
      default: result(FlutterMethodNotImplemented)
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
        clear(jobID: jobID)
        session.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == jobID }.forEach { $0.cancel() }
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
        guard let jobID = task.taskDescription else { return }
        responseLock.lock()
        let data = responseData.removeValue(forKey: task.taskIdentifier) ?? Data()
        responseLock.unlock()
        guard jobs().contains(where: { $0.id == jobID }) else { return }

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
              let imageData = Data(base64Encoded: base64), UIImage(data: imageData) != nil else {
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
        guard upsert(record) else {
            if let resultFile { try? FileManager.default.removeItem(at: jobsDirectory().appendingPathComponent(resultFile)) }
            return
        }
        DispatchQueue.main.async {
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

    private func upsert(_ record: PoseyAIJobRecord) -> Bool {
        let outcome = stateQueue.sync { () -> (Bool, [PoseyAIJobRecord]) in
            var records = loadRecords()
            guard let index = records.firstIndex(where: { $0.id == record.id }) else { return (false, []) }
            records[index] = record
            let removed = trimCompletedHistory(&records)
            saveRecords(records)
            return (true, removed)
        }
        removeFiles(for: outcome.1)
        return outcome.0
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
