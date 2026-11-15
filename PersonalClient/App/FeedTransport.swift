import Foundation
import FeedDomain
import FeedAdapters

/// Explicit user-triggered HTTPS only. No cookies, tokens, redirects, background polling or body logging.
final class FeedTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Failure: Error { case redirect, http, tooLarge, cancelled }
    private let testProtocol: URLProtocol.Type?
    init(testProtocol: URLProtocol.Type? = nil) { self.testProtocol = testProtocol; super.init() }
    private var bytes = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private let lock = NSLock()
    private var cancelled = false
    func get(_ url: URL) async throws -> Data {
        _ = try EndpointPolicy.validate(url.absoluteString)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                lock.unlock()
                let config = URLSessionConfiguration.ephemeral
                if let testProtocol = self.testProtocol { config.protocolClasses = [testProtocol] }
                config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
                config.urlCredentialStorage = nil
                config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 30
                config.waitsForConnectivity = false
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
                lock.lock(); self.session = session; let shouldCancel = cancelled; lock.unlock()
                if shouldCancel { finish(.failure(CancellationError())); return }
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                session.dataTask(with: request).resume()
            }
        }, onCancel: { self.cancel() })
    }
    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        let continuation = self.continuation; self.continuation = nil
        let session = self.session; self.session = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(Failure.redirect))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.mimeType?.lowercased() == "application/json",
              response.expectedContentLength <= ImportTable.maxBytes else {
            completionHandler(.cancel); finish(.failure(Failure.http)); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count <= ImportTable.maxBytes - data.count else { finish(.failure(Failure.tooLarge)); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) } else { finish(.success(bytes)) }
    }
}
