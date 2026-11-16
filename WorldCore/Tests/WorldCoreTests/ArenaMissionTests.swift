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
}
