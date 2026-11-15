import XCTest
import Foundation
import CryptoKit
import FeedDomain
import FeedAdapters
import FeedStore
#if canImport(PersonalFeedFeature)
@testable import PersonalFeedFeature
#else
@testable import PersonalFeed
#endif

final class PersonalFeedTests: XCTestCase {
    private func fixture() throws -> FeedVault {
        let source = FeedSource(provider: .hornet, label: "Synthetic account", acquisition: .userMappedFile)
        var value = FeedVault(); try value.addSource(source)
        try value.ingest([.init(key: .init(sourceID: source.id, externalID: "a"), body: "PRIVATE-SYNTHETIC-MARKER-731")], sourceID: source.id)
        return value
    }
    func testDiskRoundTripUsesAuthenticatedEncryption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = PrivateVault(root: root, testKey: SymmetricKey(size: .bits256)), original = try fixture()
        try await disk.save(original)
        let bytes = try Data(contentsOf: root.appendingPathComponent("vault.aesgcm"))
        XCTAssertNil(bytes.range(of: Data("PRIVATE-SYNTHETIC-MARKER-731".utf8)))
        let restored = try await disk.load(); XCTAssertEqual(restored, original)
        let props = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(props.isExcludedFromBackup, true)
    }
    func testRealKeychainRoundTripUsesDistinctTestService() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let id = UUID(), original = try fixture()
        let disk = PrivateVault(root: root, keychainTestID: id)
        do {
            try await disk.save(original)
            let reopened = PrivateVault(root: root, keychainTestID: id)
            let restored = try await reopened.load()
            XCTAssertEqual(restored, original)
            try await disk.erase()
        } catch {
            try? await disk.erase()
            throw error
        }
    }
    func testWrongKeyAndCorruptVaultFailWithoutOverwrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = PrivateVault(root: root, testKey: SymmetricKey(size: .bits256))
        try await disk.save(fixture())
        let file = root.appendingPathComponent("vault.aesgcm")
        let before = try Data(contentsOf: file)
        let wrong = PrivateVault(root: root, testKey: SymmetricKey(size: .bits256))
        do { _ = try await wrong.load(); XCTFail("Wrong key accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: file), before)
        var corrupted = before; corrupted[corrupted.startIndex] ^= 1; try corrupted.write(to: file)
        do { _ = try await disk.load(); XCTFail("Tampered archive accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: file), corrupted)
    }
    func testEraseRemovesOnlyOurVault() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = PrivateVault(root: root, testKey: SymmetricKey(size: .bits256))
        try await disk.save(fixture()); try await disk.erase()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let restored = try await disk.load(); XCTAssertTrue(restored.items.isEmpty)
    }
    @MainActor func testDemoNeverWritesPrivateDiskAndLockClearsVisibleRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = FeedSession(disk: PrivateVault(root: root, testKey: SymmetricKey(size: .bits256)))
        session.startDemo(); XCTAssertEqual(session.value.items.count, 3)
        let item = try XCTUnwrap(session.value.items.first)
        await session.addNote("Synthetic note", item: item)
        XCTAssertEqual(session.value.annotations.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        session.lock(); XCTAssertFalse(session.isOpen); XCTAssertTrue(session.value.items.isEmpty)
    }
    @MainActor func testFailedNoteCannotClaimSuccessOrChangeVault() async throws {
        let session = FeedSession(); session.startDemo()
        let item = try XCTUnwrap(session.value.items.first)
        let before = session.value
        let accepted = await session.addNote(String(repeating: "x", count: 8_193), item: item)
        XCTAssertFalse(accepted); XCTAssertEqual(session.value, before)
        XCTAssertFalse(session.message.isEmpty)
    }
    @MainActor func testDemoCannotCreateRealHornetSource() async {
        let session = FeedSession(); session.startDemo()
        await session.addSource(.init(provider: .hornet, label: "x", acquisition: .userMappedFile))
        XCTAssertEqual(session.value.sources.map(\.source.provider), [.demonstration])
    }
    func testExplicitHTTPSUsesOwnExchangeOnly() async throws {
        MockFeedProtocol.configure(status: 200, mime: "application/json", data: try ExchangeDocument(records: [.init(id: "x", text: "synthetic")]).encode())
        let client = FeedTransport(testProtocol: MockFeedProtocol.self)
        let data = try await client.get(URL(string: "https://feed-test.invalid/feed.json")!)
        let source = FeedSource(provider: .other, label: "test", acquisition: .userEndpoint)
        XCTAssertEqual(try ExchangeDocument.decode(data, source: source).count, 1)
        XCTAssertNil(MockFeedProtocol.request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(MockFeedProtocol.request?.httpBody)
    }
    func testTransportDoesNotReuseCompletedConsent() async throws {
        MockFeedProtocol.configure(status: 200, mime: "application/json", data: Data("{}".utf8))
        let client = FeedTransport(testProtocol: MockFeedProtocol.self)
        let url = URL(string: "https://feed-test.invalid/feed.json")!
        _ = try await client.get(url)
        do { _ = try await client.get(url); XCTFail("Transport silently reused") } catch {}
    }
    func testCancelBeforeStartDoesNotSendRequest() async {
        MockFeedProtocol.configure(status: 200, mime: "application/json", data: Data("{}".utf8))
        let client = FeedTransport(testProtocol: MockFeedProtocol.self); client.cancel()
        do { _ = try await client.get(URL(string: "https://feed-test.invalid/feed.json")!); XCTFail("Cancelled operation started") } catch {}
        XCTAssertNil(MockFeedProtocol.request)
    }
    func testHTTPErrorNotImported() async {
        MockFeedProtocol.configure(status: 403, mime: "application/json", data: Data("{}".utf8))
        do { _ = try await FeedTransport(testProtocol: MockFeedProtocol.self).get(URL(string: "https://feed-test.invalid/feed.json")!); XCTFail("HTTP failure accepted") } catch {}
    }
    func testHTMLNotImportedAsJSON() async {
        MockFeedProtocol.configure(status: 200, mime: "text/html", data: Data("<html>login</html>".utf8))
        do { _ = try await FeedTransport(testProtocol: MockFeedProtocol.self).get(URL(string: "https://feed-test.invalid/feed.json")!); XCTFail("HTML accepted") } catch {}
    }
    func testStreamRejectsOversizeBody() async {
        MockFeedProtocol.configure(status: 200, mime: "application/json", data: Data(repeating: 32, count: ImportTable.maxBytes + 1))
        do { _ = try await FeedTransport(testProtocol: MockFeedProtocol.self).get(URL(string: "https://feed-test.invalid/feed.json")!); XCTFail("Oversize accepted") } catch {}
    }
    func testRedirectNotFollowed() {
        let client = FeedTransport(), session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let source = URL(string: "https://feed-test.invalid/feed.json")!
        let task = session.dataTask(with: source)
        var called = false
        client.urlSession(session, task: task, willPerformHTTPRedirection: HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: URLRequest(url: URL(string: "https://other.invalid")!)) { request in
            called = true; XCTAssertNil(request)
        }
        XCTAssertTrue(called)
    }
}

private final class MockFeedProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var status = 200
    private static var mime = "application/json"
    private static var payload = Data()
    private(set) static var request: URLRequest?
    static func configure(status: Int, mime: String, data: Data) {
        lock.lock(); defer { lock.unlock() }
        self.status = status; self.mime = mime; payload = data; request = nil
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "feed-test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let status = Self.status, mime = Self.mime, data = Self.payload; Self.request = request; Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
