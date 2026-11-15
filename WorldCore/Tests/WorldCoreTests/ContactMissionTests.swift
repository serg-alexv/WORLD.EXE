import Foundation
import XCTest
@testable import WorldCore

final class ContactMissionTests: XCTestCase {
    private func command(_ m: ContactMission, _ action: ContactAction, role: ContactRole? = nil) -> ContactCommand {
        ContactCommand(session: m.state.session, revision: m.state.revision, role: role ?? action.role, action: action)
    }
    private func run(_ m: inout ContactMission, _ action: ContactAction) throws {
        let c = command(m, action); try m.apply(c, authorizedRole: action.role)
    }
    private func rejects(_ m: inout ContactMission, _ c: ContactCommand, _ error: ContactError, authority: ContactRole) {
        let before = m
        XCTAssertThrowsError(try m.apply(c, authorizedRole: authority)) { XCTAssertEqual($0 as? ContactError, error) }
        XCTAssertEqual(m, before, "Rejected commands must be atomic")
    }
    func testCompleteCooperativeMission() throws {
        var m = ContactMission(seed: 31)
        XCTAssertEqual(m.researcher.glyphs, [nil, nil, nil])
        for n in 0..<3 {
            try run(&m, .inspect(n)); let glyph = try XCTUnwrap(m.researcher.glyphs[n])
            try run(&m, .power(n)); try run(&m, .tune(glyph.channel)); try run(&m, .stabilize(n))
        }
        try run(&m, .arm); XCTAssertEqual(m.state.phase, .extraction)
        try run(&m, .extract); XCTAssertEqual(m.state.phase, .complete); XCTAssertEqual(m.state.score, 100)
    }
    func testWrongRoleAndAuthoritySpoof() {
        var m = ContactMission(seed: 2)
        rejects(&m, command(m, .inspect(0), role: .operator), .role, authority: .operator)
        rejects(&m, command(m, .inspect(0)), .role, authority: .operator)
    }
    func testOutOfRangeAndPrerequisites() {
        var m = ContactMission(seed: 2)
        for a in [ContactAction.inspect(-1), .inspect(3), .power(3), .tune(3), .stabilize(-1)] {
            rejects(&m, command(m, a), .range, authority: a.role)
        }
        rejects(&m, command(m, .power(0)), .prerequisite, authority: .operator)
        rejects(&m, command(m, .tune(0)), .prerequisite, authority: .operator)
        rejects(&m, command(m, .arm), .prerequisite, authority: .operator)
        rejects(&m, command(m, .extract), .phase, authority: .researcher)
    }
    func testWrongFrequencyPenalizesAndRemainsSolvable() throws {
        var m = ContactMission(seed: 9)
        for n in 0..<3 {
            try run(&m, .inspect(n)); let correct = try XCTUnwrap(m.researcher.glyphs[n]).channel
            try run(&m, .power(n)); try run(&m, .tune((correct + 1) % 3))
            rejects(&m, command(m, .stabilize(n)), .prerequisite, authority: .researcher)
            try run(&m, .tune(correct)); try run(&m, .stabilize(n))
        }
        XCTAssertEqual(m.state.mistakes, 3); try run(&m, .arm); try run(&m, .extract)
        XCTAssertEqual(m.state.phase, .complete)
    }
    func testStaleDuplicateSessionAndReplay() throws {
        var m = ContactMission(seed: 8); let old = command(m, .inspect(1)); let first = command(m, .inspect(0))
        try m.apply(first, authorizedRole: .researcher)
        rejects(&m, first, .duplicate, authority: .researcher); rejects(&m, old, .stale, authority: .researcher)
        let fresh = m.replay(); XCTAssertNotEqual(fresh.state.session, m.state.session); XCTAssertEqual(fresh.state.revision, 0)
        let foreign = ContactCommand(session: fresh.state.session, revision: m.state.revision, role: .researcher, action: .inspect(2))
        rejects(&m, foreign, .session, authority: .researcher)
    }
    func testDeterministicSeedAndRoundTrip() throws {
        var a = ContactMission(seed: 123), b = ContactMission(seed: 123)
        for n in 0..<3 { try run(&a, .inspect(n)); try run(&b, .inspect(n)) }
        XCTAssertEqual(a.researcher.glyphs, b.researcher.glyphs)
        let data = try JSONEncoder().encode(a); XCTAssertEqual(try JSONDecoder().decode(ContactMission.self, from: data), a)
        let publicData = try JSONEncoder().encode(a.state)
        let text = try XCTUnwrap(String(data: publicData, encoding: .utf8))
        XCTAssertFalse(text.contains("\"seed\"")); XCTAssertFalse(text.contains("\"glyphs\""))
        XCTAssertEqual(try JSONDecoder().decode(ContactPublicState.self, from: publicData), a.state)
    }
    func testCodableRejectsInvalidStateAndCommands() throws {
        let state = ContactMission(seed: 1).state
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        for (key, value) in [("version", 2 as Any), ("nodeIDs", [0, 0, 2] as Any), ("inspected", 8 as Any),
                             ("stabilized", 1 as Any), ("mistakes", 10000 as Any), ("phase", "complete" as Any),
                             ("poweredNode", 3 as Any), ("channel", 0 as Any), ("revision", -1 as Any)] {
            var bad = original; bad[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(ContactPublicState.self, from: JSONSerialization.data(withJSONObject: bad)))
        }
        let bad = ContactCommand(session: state.session, revision: 0, role: .researcher, action: .inspect(12))
        XCTAssertThrowsError(try JSONDecoder().decode(ContactCommand.self, from: JSONEncoder().encode(bad)))
    }
}
