import Foundation
import CryptoKit

struct LocalModelRecord: Codable, Sendable {
    let name: String
    let filename: String
    let bytes: Int64
    let sha256: String
    let source: String
    var valid: Bool {
        sha256.count == 64 && sha256.allSatisfy { $0.isHexDigit } &&
        filename == sha256 + ".gguf" && bytes >= 24 && bytes <= ModelFiles.maximumBytes
    }
}
enum ModelFiles {
    static let maximumBytes: Int64 = 1_300_000_000
    static let recommendedName = "Qwen3 0.6B · Q8_0"
    static let recommendedBytes: Int64 = 639_446_688
    static let recommendedSHA = "9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031"
    static let recommendedURL = URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/23749fefcc72300e3a2ad315e1317431b06b590a/Qwen3-0.6B-Q8_0.gguf")!
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
    }
    static var recordURL: URL { root.appendingPathComponent("installed-v1.json") }
    static func restore() -> LocalModelRecord? {
        guard let data = try? Data(contentsOf: recordURL), data.count < 8192,
              let record = try? JSONDecoder().decode(LocalModelRecord.self, from: data), record.valid,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url(record).path),
              (attributes[.size] as? NSNumber)?.int64Value == record.bytes else { return nil }
        return record
    }
    static func url(_ model: LocalModelRecord) -> URL { root.appendingPathComponent(model.filename) }
    static func inspect(_ file: URL, expected: String? = nil) throws -> (Int64, String) {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard (attrs[.type] as? FileAttributeType) == .typeRegular,
              let bytes = (attrs[.size] as? NSNumber)?.int64Value,
              bytes >= 24, bytes <= maximumBytes else {
            throw BrainFailure(message: "Нужен обычный GGUF-файл до 1,3 ГБ. Разбитые на части модели не поддерживаются.")
        }
        let f = try FileHandle(forReadingFrom: file)
        defer { try? f.close() }
        let header = [UInt8](try f.read(upToCount: 24) ?? Data())
        guard header.count == 24, Array(header.prefix(4)) == [0x47,0x47,0x55,0x46],
              header[4] == 2 || header[4] == 3,
              header[5] == 0, header[6] == 0, header[7] == 0 else {
            throw BrainFailure(message: "Это не поддерживаемый заголовок GGUF v2/v3.")
        }
        func u64(_ offset: Int) -> UInt64 {
            (0..<8).reduce(0) { $0 | UInt64(header[offset+$1]) << ($1*8) }
        }
        guard (1...100_000).contains(u64(8)), u64(16) <= 100_000 else {
            throw BrainFailure(message: "Некорректная таблица метаданных GGUF.")
        }
        try f.seek(toOffset: 0)
        var hasher = SHA256()
        var read: Int64 = 0
        while let chunk = try f.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            read += Int64(chunk.count)
            guard read <= maximumBytes else { throw BrainFailure(message: "Файл превышает лимит.") }
            hasher.update(data: chunk)
        }
        guard read == bytes else { throw BrainFailure(message: "Размер файла изменился во время проверки.") }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        if let expected, expected.lowercased() != digest {
            throw BrainFailure(message: "SHA-256 не совпадает. Повреждённая модель не установлена.")
        }
        return (bytes, digest)
    }
    static func install(_ source: URL, expected: String?, name: String) throws -> LocalModelRecord {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var folder = root
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try folder.setResourceValues(flags)
        let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size >= 24 && size <= maximumBytes else { throw BrainFailure(message: "Лимит файла — 1,3 ГБ.") }
        let temporary = root.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw BrainFailure(message: "Не удалось создать локальный файл.")
        }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? input.close(); try? output.close() }
        var copied: Int64 = 0
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            copied += Int64(chunk.count)
            guard copied <= maximumBytes else { throw BrainFailure(message: "Файл слишком большой.") }
            try output.write(contentsOf: chunk)
        }
        try output.synchronize(); try output.close()
        let (bytes,digest) = try inspect(temporary, expected: expected)
        let old = restore()
        let record = LocalModelRecord(name: String(name.prefix(96)), filename: digest + ".gguf", bytes: bytes,
                                      sha256: digest, source: expected == nil ? "Локальный импорт; источник не подтверждён" : "Qwen / Apache-2.0 / SHA-256 подтверждён")
        let destination = url(record)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try inspect(destination, expected: digest)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        if let old, old.filename != record.filename { try? FileManager.default.removeItem(at: url(old)) }
        return record
    }
    static func remove(_ record: LocalModelRecord) throws {
        guard record.valid else { throw BrainFailure(message: "Некорректная запись модели.") }
        try FileManager.default.removeItem(at: url(record))
        try? FileManager.default.removeItem(at: recordURL)
    }
}

final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func run() async throws -> URL {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let config = URLSessionConfiguration.ephemeral
                config.allowsCellularAccess = false
                config.allowsExpensiveNetworkAccess = false
                config.timeoutIntervalForRequest = 60
                config.timeoutIntervalForResource = 1800
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
                let task = session.downloadTask(with: ModelFiles.recommendedURL)
                lock.lock(); self.continuation = continuation; self.session = session; self.task = task; lock.unlock()
                if Task.isCancelled { cancel() } else { task.resume() }
            }
        }, onCancel: { self.cancel() })
    }
    func cancel() { lock.lock(); let task = task; lock.unlock(); task?.cancel() }
    private func finish(_ result: Result<URL, Error>) {
        lock.lock(); let c = continuation; continuation = nil; let s = session; session = nil; task = nil; lock.unlock()
        c?.resume(with: result); s?.finishTasksAndInvalidate()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > ModelFiles.recommendedBytes { downloadTask.cancel(); return }
        progress(min(1, Double(totalBytesWritten)/Double(ModelFiles.recommendedBytes)))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200,
                  (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value == ModelFiles.recommendedBytes else {
                throw BrainFailure(message: "Сервер вернул неполный файл модели.")
            }
            let retained = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")
            try FileManager.default.moveItem(at: location, to: retained)
            finish(.success(retained))
        } catch { finish(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
