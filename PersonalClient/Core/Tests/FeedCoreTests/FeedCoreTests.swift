import XCTest
import Foundation
import FeedDomain
import FeedAdapters
import FeedStore

final class FeedCoreTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func source(_ provider: Provider = .hornet) -> FeedSource {
        .init(provider: provider, label: "Локальный источник", acquisition: .userMappedFile)
    }
    private func item(_ s: FeedSource, id: String = "1", body: String = "Синтетический текст") -> IncomingItem {
        .init(key: .init(sourceID: s.id, externalID: id), body: body)
    }
    private func vault(_ s: FeedSource) throws -> FeedVault {
        var v = FeedVault(); try v.addSource(s); return v
    }
    func testHornetNotAdvertisedAsLiveAPI() {
        XCTAssertTrue(SourceCapability.forProvider(.hornet).fileImport)
        XCTAssertFalse(SourceCapability.forProvider(.hornet).liveSync)
        XCTAssertFalse(SourceCapability.forProvider(.grindr).liveSync)
    }
    func testProviderCannotImpersonateApprovedEndpoint() {
        XCTAssertFalse(FeedSource(provider: .hornet, label: "x", acquisition: .userEndpoint).isValid)
        XCTAssertFalse(FeedSource(provider: .grindr, label: "x", acquisition: .syntheticDemo).isValid)
    }
    func testDemoIsAlwaysLabelledSynthetic() throws {
        let v = try SyntheticDemo.vault()
        XCTAssertEqual(v.sources.map(\.source.provider), [.demonstration])
        XCTAssertTrue(v.items.allSatisfy { $0.acquisition == .syntheticDemo })
        XCTAssertTrue(v.isValid)
    }
    func testCSVQuotedCommaAndNewline() throws {
        let t = try ImportTable(data: Data("id,text\r\n1,\"привет, мир\nвторая строка\"\r\n".utf8), fileExtension: "csv")
        XCTAssertEqual(t.rows[0]["text"], "привет, мир\nвторая строка")
    }
    func testCSVEscapedQuotesAndBOM() throws {
        let t = try ImportTable(data: Data("\u{FEFF}id,text\n1,\"say \"\"hi\"\"\"\n".utf8), fileExtension: "csv")
        XCTAssertEqual(t.rows[0]["text"], "say \"hi\"")
        XCTAssertEqual(t.columns[0], "id")
    }
    func testCSVRejectsUnclosedQuotesAndDuplicateHeaders() {
        for text in ["id,text\n1,\"unclosed", "id,id\n1,2", "id,text\n1,x,y", "id,text\n1,\"x\"after"] {
            XCTAssertThrowsError(try ImportTable(data: Data(text.utf8), fileExtension: "csv"))
        }
    }
    func testUnknownFileNotPretendedHornetArchive() {
        XCTAssertThrowsError(try ImportTable(data: Data("not a ZIP".utf8), fileExtension: "zip"))
        XCTAssertThrowsError(try ImportTable(data: Data("{\"secret\":{\"text\":1}}".utf8), fileExtension: "json"))
    }
    func testJSONExplicitArrayKeyNotGuessed() throws {
        let data = Data("{\"messages\":[{\"id\":1,\"text\":\"synthetic\"}]}".utf8)
        XCTAssertThrowsError(try ImportTable(data: data, fileExtension: "json"))
        let table = try ImportTable(data: data, fileExtension: "json", arrayKey: "messages")
        XCTAssertEqual(table.rows[0]["id"], "1")
    }
    func testNestedObjectNeverSilentlyFlattened() throws {
        let table = try ImportTable(data: Data("[{\"id\":\"a\",\"nested\":{\"text\":\"x\"}}]".utf8), fileExtension: "json")
        XCTAssertEqual(table.columns, ["id"])
    }
    func testMappingRequiresDifferentIDAndText() throws {
        let table = try ImportTable(data: Data("id,text\n1,hello".utf8), fileExtension: "csv")
        XCTAssertThrowsError(try table.map(using: .init(id: "id", body: "id"), source: source()))
        XCTAssertThrowsError(try table.map(using: .init(id: "missing", body: "text"), source: source()))
    }
    func testMissingDatesStayUnknown() throws {
        let s = source(), table = try ImportTable(data: Data("id,text\n1,hello".utf8), fileExtension: "csv")
        let rows = try table.map(using: .init(id: "id", body: "text"), source: s)
        XCTAssertNil(rows[0].occurredAt)
        XCTAssertEqual(rows[0].direction, .unspecified)
    }
    func testDateParsingExplicitTimeZoneAndUnits() throws {
        let a = try ImportTable.parseDate("2023-11-14T22:13:20Z", format: .iso8601)
        let b = try ImportTable.parseDate("1700000000", format: .unixSeconds)
        XCTAssertEqual(a, b)
        XCTAssertThrowsError(try ImportTable.parseDate("yesterday", format: .iso8601))
        XCTAssertThrowsError(try ImportTable.parseDate("nan", format: .unixSeconds))
        XCTAssertThrowsError(try ImportTable.parseDate("1700000000000", format: .unixSeconds))
    }
    func testAtomicBatchRejectsInvalidRecordWithoutPartialWrites() throws {
        let s = source(); var v = try vault(s)
        let before = v
        XCTAssertThrowsError(try v.ingest([item(s), item(s, id: "2", body: "")], sourceID: s.id, at: date))
        XCTAssertEqual(v, before)
    }
    func testRepeatedImportIsIdempotent() throws {
        let s = source(); var v = try vault(s)
        let first = try v.ingest([item(s)], sourceID: s.id, at: date)
        let second = try v.ingest([item(s)], sourceID: s.id, at: date.addingTimeInterval(10))
        XCTAssertEqual(first.inserted, 1); XCTAssertEqual(second.unchanged, 1)
        XCTAssertEqual(v.items.count, 1); XCTAssertEqual(v.items[0].revision, 1)
        XCTAssertEqual(v.items[0].importedAt, date)
    }
    func testBatchDuplicateConflictIsAtomic() throws {
        let s = source(); var v = try vault(s); let before = v
        XCTAssertThrowsError(try v.ingest([item(s), item(s, body: "changed")], sourceID: s.id, at: date))
        XCTAssertEqual(v, before)
    }
    func testEqualDuplicatesCountAsUnchanged() throws {
        let s = source(); var v = try vault(s)
        let result = try v.ingest([item(s), item(s)], sourceID: s.id, at: date)
        XCTAssertEqual(result.inserted, 1); XCTAssertEqual(result.unchanged, 1)
    }
    func testSameExternalIDFromTwoSourcesDoesNotMergePeople() throws {
        let a = source(), b = source(.grindr); var v = try vault(a); try v.addSource(b)
        try v.ingest([item(a)], sourceID: a.id, at: date)
        try v.ingest([item(b)], sourceID: b.id, at: date)
        XCTAssertEqual(v.items.count, 2)
    }
    func testSourceMismatchIsRejected() throws {
        let a = source(), b = source(); var v = try vault(a)
        XCTAssertThrowsError(try v.ingest([item(b)], sourceID: a.id, at: date))
        XCTAssertTrue(v.items.isEmpty)
    }
    func testNotesNeverModifySourceItems() throws {
        let s = source(); var v = try vault(s); try v.ingest([item(s)], sourceID: s.id, at: date)
        let original = v.items
        try v.annotate(.init(kind: .personalNote, text: "Моя заметка", references: [.init(v.items[0])]))
        XCTAssertEqual(v.items, original); XCTAssertEqual(v.annotations.count, 1)
    }
    func testModelAnnotationsRequireEngineAndReferences() throws {
        let s = source(); var v = try vault(s); try v.ingest([item(s)], sourceID: s.id, at: date)
        XCTAssertThrowsError(try v.annotate(.init(kind: .modelInterpretation, text: "summary", references: [.init(v.items[0])])))
        try v.annotate(.init(kind: .modelInterpretation, text: "summary", references: [.init(v.items[0])], engine: "test-model (synthetic)"))
        XCTAssertEqual(v.items[0].body, "Синтетический текст")
    }
    func testChangedRecordInvalidatesDerivedAnnotations() throws {
        let s = source(); var v = try vault(s); try v.ingest([item(s)], sourceID: s.id, at: date)
        let old = ItemReference(v.items[0])
        try v.annotate(.init(kind: .personalNote, text: "note", references: [old]))
        let receipt = try v.ingest([item(s, body: "changed")], sourceID: s.id, at: date)
        XCTAssertEqual(receipt.invalidatedAnnotations, 1); XCTAssertTrue(v.annotations.isEmpty)
        XCTAssertEqual(v.items[0].revision, 2)
        XCTAssertThrowsError(try v.annotate(.init(kind: .personalNote, text: "stale", references: [old])))
    }
    func testDeleteSourceCascadesButKeepsOtherSource() throws {
        let a = source(), b = source(); var v = try vault(a); try v.addSource(b)
        try v.ingest([item(a)], sourceID: a.id, at: date); try v.ingest([item(b)], sourceID: b.id, at: date)
        try v.annotate(.init(kind: .personalNote, text: "linked", references: v.items.map(ItemReference.init)))
        v.deleteSource(a.id)
        XCTAssertEqual(v.items.count, 1); XCTAssertEqual(v.items[0].key.sourceID, b.id)
        XCTAssertTrue(v.annotations.isEmpty)
    }
    func testArchiveRoundTrip() throws {
        let v = try SyntheticDemo.vault()
        XCTAssertEqual(try FeedVault(data: v.encoded()), v)
    }
    func testArchiveRejectsInventedVersionAndDanglingAnnotation() throws {
        let v = try SyntheticDemo.vault()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: v.encoded()) as? [String: Any])
        object["schemaVersion"] = 123
        XCTAssertThrowsError(try FeedVault(data: JSONSerialization.data(withJSONObject: object)))
        object["schemaVersion"] = 1; object["sources"] = []
        XCTAssertThrowsError(try FeedVault(data: JSONSerialization.data(withJSONObject: object)))
    }
    func testLimitsRejectOversizeInput() {
        XCTAssertThrowsError(try ImportTable(data: Data(repeating: 32, count: ImportTable.maxBytes + 1), fileExtension: "json"))
        XCTAssertThrowsError(try FeedVault(data: Data(repeating: 32, count: FeedVault.maximumBytes + 1)))
    }
    func testSourceLimitAndDuplicateSource() throws {
        let s = source(); var v = try vault(s)
        XCTAssertThrowsError(try v.addSource(s))
        for _ in 1..<32 { try v.addSource(source()) }
        XCTAssertThrowsError(try v.addSource(source()))
    }
    func testSearchDoesNotIncludeUnrelatedNotes() throws {
        let s = source(); var v = try vault(s); try v.ingest([item(s, body: "Контакт")], sourceID: s.id, at: date)
        try v.annotate(.init(kind: .personalNote, text: "секретная заметка", references: [.init(v.items[0])]))
        XCTAssertEqual(v.feed(query: "КОНТАКТ").count, 1)
        XCTAssertTrue(v.feed(query: "секретная").isEmpty)
    }
    func testHTTPSPolicyRejectsCredentialsAndQuerySecrets() {
        for url in ["http://example.com/feed", "https://user:pass@example.com/feed", "file:///x", "https://example.com/?token=x", "https://example.com/#x"] {
            XCTAssertThrowsError(try EndpointPolicy.validate(url))
        }
        XCTAssertNoThrow(try EndpointPolicy.validate("https://example.com/feed.json"))
    }
    func testOwnExchangeContractNotMistakenForHornet() throws {
        let data = try ExchangeDocument(records: [.init(id: "1", text: "synthetic")]).encode()
        XCTAssertThrowsError(try ExchangeDocument.decode(data, source: source()))
        let custom = FeedSource(provider: .other, label: "own", acquisition: .userEndpoint)
        XCTAssertEqual(try ExchangeDocument.decode(data, source: custom).count, 1)
    }
    func testExchangeRejectsUnsupportedSchema() {
        let custom = FeedSource(provider: .other, label: "own", acquisition: .userEndpoint)
        let data = Data("{\"format\":\"hornet-native-guessed\",\"records\":[]}".utf8)
        XCTAssertThrowsError(try ExchangeDocument.decode(data, source: custom))
    }
    func testStressReimportsAndDeletionPreserveInvariants() throws {
        let s = source(); var v = try vault(s)
        for i in 0..<40 {
            let batch = (0..<25).map { item(s, id: String($0), body: "synthetic revision \(i)") }
            try v.ingest(batch, sourceID: s.id, at: date)
            XCTAssertEqual(v.items.count, 25); XCTAssertTrue(v.isValid)
        }
        XCTAssertEqual(v.items[0].revision, 40)
        v.deleteSource(s.id); XCTAssertTrue(v.items.isEmpty); XCTAssertTrue(v.isValid)
    }
}
