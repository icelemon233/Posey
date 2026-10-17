import Foundation
import UIKit
import UserNotifications
import Security
import ImageIO

struct PoseyNativeError: Error { let message: String }
private struct PoseyAIJobRecord: Codable {
  let id: String
  var state: String
  let createdAt: Double
  var completedAt: Double?
  var targetTitle: String?
  var resultFile: String?
  var message: String?
  var metadata: Data?
  var pendingResult: String?
}

final class PoseyBackgroundAIManager: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate {
  static let shared = PoseyBackgroundAIManager()
  private let state = DispatchQueue(label: "com.posey.camera.background-ai.state")
  private let responseLock = NSLock()
  private var responseData: [Int: Data] = [:]
  private var memoryResults: [String: Data] = [:]
  private var sessionCompletionHandler: (() -> Void)?
  private let recordsKey = "posey.background-ai.jobs"
  private var directory: URL {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PoseyAIJobs", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var excluded = url; var values = URLResourceValues(); values.isExcludedFromBackup = true; try? excluded.setResourceValues(values)
    return url
  }
  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: "com.posey.camera.ai-pose")
    config.isDiscretionary = false; config.sessionSendsLaunchEvents = true
    config.timeoutIntervalForRequest = 300; config.timeoutIntervalForResource = 600
    let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
    return URLSession(configuration: config, delegate: self, delegateQueue: queue)
  }()
  private func file(_ id: String, _ suffix: String) -> URL { directory.appendingPathComponent("\(id)-\(suffix)") }
  func id(_ args: [String: Any]) throws -> String {
    guard let id = args["jobId"] as? String, UUID(uuidString: id) != nil else { throw PoseyNativeError(message: "任务编号无效。") }; return id
  }
  private func validURL(_ value: String) -> URL? {
    guard let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }; return url
  }
  private func read() throws -> [PoseyAIJobRecord] {
    let current = directory.appendingPathComponent("records-v2.json")
    let data = FileManager.default.fileExists(atPath: current.path) ? try Data(contentsOf: current) : UserDefaults.standard.data(forKey: recordsKey)
    guard let data else { return [] }
    let records = try JSONDecoder().decode([PoseyAIJobRecord].self, from: data)
    guard records.count <= 2000, Set(records.map(\.id)).count == records.count,
      records.allSatisfy({ UUID(uuidString: $0.id) != nil && ["queued", "generating", "awaitingResult", "completed", "failed", "cancelled"].contains($0.state) && ($0.resultFile == nil || $0.resultFile == "\($0.id)-result.jpg") }) else {
      throw PoseyNativeError(message: "后台任务记录无法读取，请先备份并恢复记录。")
    }
    return records
  }
  private func save(_ records: [PoseyAIJobRecord]) throws {
    try JSONEncoder().encode(records).write(to: directory.appendingPathComponent("records-v2.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  func activate() { _ = session; scheduleNext() }
  func setSessionCompletionHandler(_ handler: @escaping () -> Void) { sessionCompletionHandler = handler; activate() }
  func start(_ args: [String: Any]) throws -> String {
    let jobID = try id(args)
    guard let source = args["sourceImage"] as? String, let guide = args["guideImage"] as? String,
      let prompt = args["prompt"] as? String, let key = args["apiKey"] as? String, !key.isEmpty,
      let endpoint = args["endpoint"] as? String, let url = validURL(endpoint),
      let model = args["model"] as? String, !model.isEmpty,
      source.utf8.count <= 16 * 1024 * 1024, guide.utf8.count <= 16 * 1024 * 1024,
      let sourceData = Data(base64Encoded: String(source.split(separator: ",", maxSplits: 1).last ?? "")), validImage(sourceData) else {
      throw PoseyNativeError(message: "生成配置或照片格式无效。")
    }
    try state.sync {
      var records = try read()
      guard !records.contains(where: { $0.id == jobID }), records.filter({ $0.state == "queued" || $0.state == "generating" }).count < 3,
        !records.contains(where: { $0.state == "awaitingResult" }) else { throw PoseyNativeError(message: "请先处理进行中的任务或尚未保存的成片。") }
      let body: [String: Any] = ["model": model, "prompt": prompt, "image": [source, guide], "size": "2K", "output_format": "jpeg", "response_format": "b64_json", "watermark": false]
      let requestFile = file(jobID, "request.json")
      do {
        try JSONSerialization.data(withJSONObject: body).write(to: requestFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try sourceData.write(to: file(jobID, "source.jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let task = session.uploadTask(with: request, fromFile: requestFile); task.taskDescription = jobID
        var metadata: [String: Any] = [:]
        if let input = args["metadata"] as? [String: Any] {
          for name in ["targetId", "targetSnapshot", "requestMetadata", "sourceWorkId", "retryOf"] { metadata[name] = input[name] }
        }
        let next = records.contains { $0.state == "generating" } ? "queued" : "generating"
        records.append(PoseyAIJobRecord(id: jobID, state: next, createdAt: Date().timeIntervalSince1970 * 1000,
          targetTitle: args["targetTitle"] as? String, metadata: try JSONSerialization.data(withJSONObject: metadata)))
        do { try save(records) } catch { task.cancel(); throw error }
        if next == "generating" { task.resume() }
      } catch { try? FileManager.default.removeItem(at: requestFile); try? FileManager.default.removeItem(at: file(jobID, "source.jpg")); throw error }
    }
    return jobID
  }
  private func recoveredRecords() throws -> [PoseyAIJobRecord] {
    var records = try read(); var changed = false
    for index in records.indices where records[index].state != "cancelled" {
      let id = records[index].id
      if FileManager.default.fileExists(atPath: file(id, "result.jpg").path) && records[index].state != "completed" {
        records[index].state = "completed"; records[index].resultFile = "\(id)-result.jpg"
        records[index].completedAt = Date().timeIntervalSince1970 * 1000; records[index].pendingResult = nil; changed = true
      } else if records[index].pendingResult == "save" && memoryResults[id] == nil && records[index].state == "awaitingResult" {
        records[index].state = "failed"; records[index].pendingResult = nil
        records[index].message = "上次成片未能保存。服务可能已处理，请核对服务记录后再决定是否重新生成。"; changed = true
      }
    }
    if changed { try save(records) }; return records
  }
  func payloads() throws -> [[String: Any]] {
    let payloads: [[String: Any]] = try state.sync {
      try recoveredRecords().sorted { $0.createdAt > $1.createdAt }.map { record in
        var payload: [String: Any] = ["id": record.id, "state": record.state, "createdAt": record.createdAt,
          "sourceAvailable": FileManager.default.fileExists(atPath: file(record.id, "source.jpg").path),
          "imageAvailable": memoryResults[record.id] != nil || FileManager.default.fileExists(atPath: file(record.id, "result.jpg").path)]
        payload["completedAt"] = record.completedAt; payload["targetTitle"] = record.targetTitle; payload["message"] = record.message; payload["pendingResult"] = record.pendingResult
        if let data = record.metadata { payload["metadata"] = try? JSONSerialization.jsonObject(with: data) }
        return payload
      }
    }; scheduleNext(); return payloads
  }
  func image(id: String, source: Bool) throws -> Data? {
    try state.sync {
      guard try read().contains(where: { $0.id == id }) else { return nil }
      if !source, let data = memoryResults[id] { return data }
      let url = file(id, source ? "source.jpg" : "result.jpg")
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 24 * 1024 * 1024 else { throw PoseyNativeError(message: "照片过大。") }
      return try Data(contentsOf: url)
    }
  }
  func cancel(id: String, remove: Bool) throws {
    try state.sync {
      var records = try read()
      guard let index = records.firstIndex(where: { $0.id == id }) else { return }
      if remove { records.remove(at: index) } else { records[index].state = "cancelled"; records[index].pendingResult = nil }
      try save(records); memoryResults.removeValue(forKey: id)
      try? FileManager.default.removeItem(at: file(id, "request.json")); secret(id, value: nil)
      if remove { try? FileManager.default.removeItem(at: file(id, "source.jpg")); try? FileManager.default.removeItem(at: file(id, "result.jpg")) }
    }
    session.getAllTasks { tasks in tasks.filter { self.jobID($0) == id }.forEach { $0.cancel() }; self.scheduleNext() }
  }
  func repairHistory() throws {
    try state.sync {
      do { _ = try read(); return } catch { }
      let current = directory.appendingPathComponent("records-v2.json")
      let data = FileManager.default.fileExists(atPath: current.path) ? try Data(contentsOf: current) : UserDefaults.standard.data(forKey: recordsKey) ?? Data()
      try data.write(to: directory.appendingPathComponent("recovery-\(UUID().uuidString).json"), options: .atomic)
      try save([])
    }
  }
  private func jobID(_ task: URLSessionTask) -> String? { task.taskDescription?.components(separatedBy: "|").first }
  private func isDownload(_ task: URLSessionTask) -> Bool { task.taskDescription?.hasSuffix("|download") == true }
  private func update(_ id: String, _ next: String, _ message: String? = nil, pending: String? = nil) {
    try? state.sync {
      var records = try read(); guard let index = records.firstIndex(where: { $0.id == id && $0.state != "cancelled" }) else { return }
      records[index].state = next; records[index].message = message; records[index].pendingResult = pending
      if next == "completed" { records[index].resultFile = "\(id)-result.jpg"; records[index].completedAt = Date().timeIntervalSince1970 * 1000 }
      try save(records)
    }
  }
  private func validImage(_ data: Data) -> Bool {
    guard data.count <= 24 * 1024 * 1024, let image = CGImageSourceCreateWithData(data as CFData, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
      let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int else { return false }
    return width > 0 && height > 0 && width <= 16384 && height <= 16384 && width * height <= 16 * 1024 * 1024
  }
  private func accept(_ id: String, data: Data) {
    guard validImage(data) else { update(id, "failed", "服务返回的图片格式无效。"); return }
    var accepted = false
    do {
      try state.sync {
        guard try read().contains(where: { $0.id == id && $0.state != "cancelled" }) else { return }
        memoryResults[id] = data
        try data.write(to: file(id, "result.jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        memoryResults.removeValue(forKey: id); accepted = true
      }
    } catch { update(id, "awaitingResult", "成片已生成，图片未能写入。释放空间后可重试保存。", pending: "save"); notify(id, completed: false); return }
    if accepted { update(id, "completed"); secret(id, value: nil); notify(id, completed: true) }
  }
  func retryResult(id: String) throws {
    let bytes = try state.sync { () throws -> Data? in
      guard let job = try read().first(where: { $0.id == id }), job.state == "awaitingResult" else { throw PoseyNativeError(message: "成片状态已经变化，请刷新任务列表。") }
      return memoryResults[id]
    }
    if let bytes { accept(id, data: bytes); scheduleNext(); return }
    guard let value = secret(id), let url = validURL(value) else { throw PoseyNativeError(message: "未找到可恢复的成片，请先核对服务记录。") }
    session.getAllTasks { tasks in
      guard !tasks.contains(where: { self.jobID($0) == id }) else { return }
      self.download(id, url: url)
    }
  }
  private func download(_ id: String, url: URL) {
    var request = URLRequest(url: url); request.timeoutInterval = 90
    let task = session.downloadTask(with: request); task.taskDescription = "\(id)|download"; task.resume()
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    responseLock.lock(); defer { responseLock.unlock() }
    if (responseData[dataTask.taskIdentifier]?.count ?? 0) + data.count > 40 * 1024 * 1024 { dataTask.cancel(); return }
    responseData[dataTask.taskIdentifier, default: Data()].append(data)
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    if totalBytesWritten > 24 * 1024 * 1024 || totalBytesExpectedToWrite > 24 * 1024 * 1024 { downloadTask.cancel() }
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let id = jobID(downloadTask) else { return }
    guard (200..<300).contains((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0),
      let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 24 * 1024 * 1024,
      let data = try? Data(contentsOf: location) else { update(id, "awaitingResult", "成片下载未完成，可重试下载。", pending: "download"); return }
    accept(id, data: data)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let id = jobID(task) else { return }
    responseLock.lock(); let data = responseData.removeValue(forKey: task.taskIdentifier) ?? Data(); responseLock.unlock()
    defer { if !isDownload(task) { try? FileManager.default.removeItem(at: file(id, "request.json")) }; scheduleNext() }
    if error != nil {
      if isDownload(task) { update(id, "awaitingResult", "成片下载未完成，可重试下载。", pending: "download") }
      else { update(id, "failed", "网络或后台任务已中断。服务可能已处理，请核对后再决定是否重试。") }; return
    }
    if isDownload(task) { return }
    let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      let message = status == 401 || status == 403 ? "服务鉴权失败，请检查 API Key 与模型权限。" : status == 429 ? "服务请求过多或配额不足，请稍后重试。" : "生成服务返回错误（\(status)），请核对服务记录后再试。"
      update(id, "failed", message); notify(id, completed: false); return
    }
    guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let first = (payload["data"] as? [[String: Any]])?.first else { update(id, "failed", "服务没有返回可用的图片。"); return }
    if let base64 = first["b64_json"] as? String, let bytes = Data(base64Encoded: base64) { accept(id, data: bytes) }
    else if let value = first["url"] as? String, let url = validURL(value) {
      guard secret(id, value: value) else { update(id, "failed", "下载地址未能安全保存，请核对服务记录后再试。"); return }
      update(id, "awaitingResult", "正在下载成片。", pending: "download"); download(id, url: url)
    } else { update(id, "failed", "服务没有返回可用的图片。") }
  }
  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) { DispatchQueue.main.async { self.sessionCompletionHandler?(); self.sessionCompletionHandler = nil } }
  private func scheduleNext() {
    session.getAllTasks { tasks in
      try? self.state.sync {
        var records = try self.recoveredRecords(); var changed = false
        for index in records.indices where ["queued", "generating"].contains(records[index].state) && !tasks.contains(where: { self.jobID($0) == records[index].id }) {
          if Date().timeIntervalSince1970 * 1000 - records[index].createdAt < 5000 { continue }
          records[index].state = "failed"; records[index].message = "上次任务已中断，服务可能已处理，请核对后再决定是否重试。"; changed = true
        }
        if changed { try self.save(records) }
        guard !records.contains(where: { $0.state == "awaitingResult" }) else { return }
        let next = records.first(where: { $0.state == "generating" }) ?? records.filter { $0.state == "queued" }.min { $0.createdAt < $1.createdAt }
        guard let next, let task = tasks.first(where: { self.jobID($0) == next.id }), task.state == .suspended else { return }
        if let index = records.firstIndex(where: { $0.id == next.id }) { records[index].state = "generating"; try self.save(records) }
        task.resume()
      }
    }
  }
  @discardableResult private func secret(_ id: String, value: String?) -> Bool {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "posey.ai.results", kSecAttrAccount as String: id]
    guard let value else { SecItemDelete(query as CFDictionary); return true }
    let data = Data(value.utf8)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecSuccess { return true }
    if status != errSecItemNotFound { return false }
    var insert = query; insert[kSecValueData as String] = data; insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
  }
  private func secret(_ id: String) -> String? {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "posey.ai.results", kSecAttrAccount as String: id, kSecReturnData as String: true]
    var result: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }; return String(data: data, encoding: .utf8)
  }
  private func notify(_ id: String, completed: Bool) {
    DispatchQueue.main.async {
      guard UIApplication.shared.applicationState != .active else { return }
      let content = UNMutableNotificationContent(); content.title = "Posey"; content.body = completed ? "生成完成，打开查看成片。" : "生成尚未完成，打开任务页处理。"
      content.userInfo = ["poseyJobId": id]; content.sound = .default
      UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "posey-ai-\(id)", content: content, trigger: nil))
    }
  }
}
