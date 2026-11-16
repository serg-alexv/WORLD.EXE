import XCTest
@testable import WorldCore
final class ArenaMissionTests: XCTestCase {
    func testInitialStateIsValidAndSynthetic() { let s=ArenaMission();XCTAssertTrue(s.valid);XCTAssertFalse(s.won);XCTAssertFalse(s.lost) }
    func testMoveAndReplay() { var s=ArenaMission();let i=ArenaInput(sequence:1,kind:.move,z:1);XCTAssertTrue(s.apply(i,player:"host"));let copy=s;XCTAssertFalse(s.apply(i,player:"host"));XCTAssertEqual(s,copy) }
    func testInvalidNumbersAndSpoofCannotMutate() { var s=ArenaMission();let old=s;XCTAssertFalse(s.apply(ArenaInput(sequence:1,kind:.move,x:.nan),player:"host"));XCTAssertFalse(s.apply(ArenaInput(sequence:1,kind:.move,x:1),player:"bot1"));XCTAssertEqual(s,old) }
    func testCoverBlocksAndOpenLaneWorks() { XCTAssertFalse(ArenaMission.clearLine(ax:-3,az:0,bx:3,bz:0));XCTAssertTrue(ArenaMission.clearLine(ax:-3,az:-3,bx:3,bz:-3)) }
    func testFireDamageAndNoFriendlyFire() { var s=ArenaMission();s.setGuest(true);let before=s;XCTAssertFalse(s.apply(ArenaInput(sequence:1,kind:.fire,target:"guest"),player:"host"));XCTAssertEqual(s,before);XCTAssertTrue(s.apply(ArenaInput(sequence:1,kind:.fire,target:"bot1"),player:"host"));XCTAssertEqual(s.actors.first{$0.id=="bot1"}?.health,25) }
    func testOneActionPerTickAndReload() { var s=ArenaMission();XCTAssertTrue(s.apply(ArenaInput(sequence:1,kind:.fire,target:"bot1"),player:"host"));XCTAssertFalse(s.apply(ArenaInput(sequence:2,kind:.reload),player:"host"));s.step();XCTAssertTrue(s.apply(ArenaInput(sequence:2,kind:.reload),player:"host"));XCTAssertEqual(s.actors[0].ammo,12) }
    func testBotsAreDeterministic() { var a=ArenaMission();var b=a;for _ in 0..<100 { a.step();b.step() };XCTAssertEqual(a,b);XCTAssertTrue(a.valid);XCTAssertLessThan(a.actors[0].health,100) }
    func testGuestRevocation() { var s=ArenaMission();s.setGuest(true);XCTAssertEqual(s.actors.count,5);s.setGuest(false);XCTAssertEqual(s.actors.count,4);XCTAssertFalse(s.apply(ArenaInput(sequence:1,kind:.reload),player:"guest")) }
    func testWireBoundsAndRoundTrip() throws { let s=ArenaMission();let data=try JSONEncoder().encode(ArenaPacket(state:s));XCTAssertEqual(ArenaPacket.decode(data)?.state,s);XCTAssertNil(ArenaPacket.decode(Data(repeating:0,count:16_385)));XCTAssertNil(ArenaPacket.decode(Data("{}".utf8))) }
    func testHardwarePolicyFailsClosed() { XCTAssertTrue(ArenaDevicePolicy.admits(machine:"iPhone19,2",osMajor:27));XCTAssertTrue(ArenaDevicePolicy.admits(machine:"iPhone19,7",osMajor:27));XCTAssertFalse(ArenaDevicePolicy.admits(machine:"iPhone18,1",osMajor:27));XCTAssertFalse(ArenaDevicePolicy.admits(machine:"iPhone20,1",osMajor:28));XCTAssertFalse(ArenaDevicePolicy.admits(machine:"iPhone19,2",osMajor:26));XCTAssertTrue(ArenaDevicePolicy.admits(machine:"x86_64",osMajor:26,simulator:true)) }
    func testFullMissionCanBeWon() {
        var state = ArenaMission(); var sequence = 0
        func action(_ kind: ArenaInput.Kind, x: Double = 0, z: Double = 0, target: String? = nil) {
            sequence += 1
            XCTAssertTrue(state.apply(ArenaInput(sequence: sequence, kind: kind, x: x, z: z, target: target), player: "host"))
            state.step()
        }
        action(.fire, target: "bot1"); action(.fire, target: "bot1")
        for _ in 0..<4 { action(.move, z: -1) }
        for _ in 0..<18 { action(.move, x: 1) }
        action(.fire, target: "bot2"); action(.fire, target: "bot2")
        action(.fire, target: "bot3"); action(.fire, target: "bot3")
        XCTAssertTrue(state.valid); XCTAssertTrue(state.won); XCTAssertFalse(state.lost)
    }
    func testMovementBoundaryAndCoverRejectAtomically() {
        var state = ArenaMission()
        for n in 1...4 { XCTAssertTrue(state.apply(ArenaInput(sequence: n, kind: .move, x: -1), player: "host")); state.step() }
        let beforeBoundary = state
        XCTAssertFalse(state.apply(ArenaInput(sequence: 5, kind: .move, x: -1), player: "host"))
        XCTAssertEqual(state, beforeBoundary)
        state = ArenaMission(); var n = 0
        for _ in 0..<9 { n += 1; XCTAssertTrue(state.apply(ArenaInput(sequence: n, kind: .move, z: 1), player: "host")); state.step() }
        for _ in 0..<6 { n += 1; XCTAssertTrue(state.apply(ArenaInput(sequence: n, kind: .move, x: 1), player: "host")); state.step() }
        let beforeCover = state
        XCTAssertFalse(state.apply(ArenaInput(sequence: n + 1, kind: .move, x: 1), player: "host"))
        XCTAssertEqual(state, beforeCover)
    }
    func testZeroSessionInputIsRejected() throws {
        let zero = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        let packet = ArenaPacket(session: zero, input: ArenaInput(sequence: 1, kind: .reload))
        XCTAssertNil(ArenaPacket.decode(try JSONEncoder().encode(packet)))
    }

}
