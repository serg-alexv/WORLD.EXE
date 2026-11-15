import Foundation
import XCTest
@testable import WorldCore

final class CompactCoreTests: XCTestCase {
    private let sector = Sector.training
    private var cells: [GridPoint] { (0..<81).map { GridPoint($0 % 9, $0 / 9) } }
    private func reference(_ start: GridPoint, _ goal: GridPoint,
                           extra: Set<GridPoint> = []) -> [GridPoint]? {
        guard sector.isWalkable(start), sector.isWalkable(goal),
              !extra.contains(start), !extra.contains(goal) else { return nil }
        var queue = [start], head = 0
        var seen: Set<GridPoint> = [start]
        var previous: [GridPoint: GridPoint] = [:]
        while head < queue.count {
            let current = queue[head]; head += 1
            if current == goal {
                var route = [goal], cursor = goal
                while cursor != start {
                    guard let parent = previous[cursor] else { return nil }
                    route.append(parent); cursor = parent
                }
                route.reverse(); return route
            }
            for next in current.neighbors where sector.isWalkable(next) && !extra.contains(next) {
                if seen.insert(next).inserted { previous[next] = current; queue.append(next) }
            }
        }
        return nil
    }
    func testAll6561PairsPreserveExactLegacyTieBreaking() {
        let points = cells
        var maximumEdges = 0
        for start in points { for goal in points {
            let path = sector.path(from: start, to: goal)
            XCTAssertEqual(path, reference(start, goal))
            maximumEdges = max(maximumEdges, (path?.count ?? 1) - 1)
        } }
        XCTAssertEqual(maximumEdges, 16, "Revisit the preview-pool budget if the training map changes.")
    }
    func test2000DeterministicBlockedMapQueries() {
        let points = cells
        var seed: UInt64 = 731
        func next() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed
        }
        for _ in 0..<2000 {
            let start = points[Int(next() % 81)], goal = points[Int(next() % 81)]
            var extra: Set<GridPoint> = [GridPoint(Int.max, Int.min)]
            for _ in 0..<12 { extra.insert(points[Int(next() % 81)]) }
            XCTAssertEqual(sector.path(from: start, to: goal, avoiding: extra), reference(start, goal, extra: extra))
        }
    }
    func testMaskBoundariesAndPayloadBudgets() throws {
        var mask = CellMask81()
        for cell in [0, 63, 64, 80] { mask.insert(cell) }
        for cell in 0..<81 { XCTAssertEqual(mask.contains(cell), [0, 63, 64, 80].contains(cell)) }
        XCTAssertEqual(MemoryLayout<CellMask81>.size, 16)
        XCTAssertEqual(CompactPathfinder.scratchBytes, 162)
        XCTAssertEqual(try Mission().compactData().count, 19)
        for invalid in [GridPoint(-1, 0), GridPoint(9, 0), GridPoint(Int.max, Int.min)] {
            XCTAssertNil(sector.path(from: invalid, to: GridPoint(0, 0)))
            XCTAssertNil(sector.path(from: GridPoint(0, 0), to: invalid))
        }
    }
    func testCompactSaveRoundTripsEntireMission() throws {
        var mission = Mission()
        XCTAssertEqual(try Mission(compactData: mission.compactData()), mission)
        mission.begin()
        for goal in sector.relics + [sector.extraction] {
            let route = try XCTUnwrap(sector.path(from: mission.position, to: goal))
            for step in route.dropFirst() {
                if mission.actions == 0 { try mission.endTurn() }
                try mission.move(to: step)
                XCTAssertEqual(try Mission(compactData: mission.compactData()), mission)
            }
            if mission.actions == 0 { try mission.endTurn() }
            if goal == sector.extraction { try mission.extract() } else { try mission.recover() }
            XCTAssertEqual(try Mission(compactData: mission.compactData()), mission)
        }
        XCTAssertEqual(mission.phase, .success)
        mission.reset()
        XCTAssertEqual(try Mission(compactData: mission.compactData()), Mission())
    }
    func testCompactSaveRejectsEverySingleBitCorruption() throws {
        let encoded = try Mission().compactData()
        for index in 0..<encoded.count { for bit in 0..<8 {
            var damaged = encoded
            damaged[index] ^= UInt8(1) << UInt8(bit)
            XCTAssertThrowsError(try Mission(compactData: damaged))
        } }
        XCTAssertThrowsError(try Mission(compactData: Data()))
        XCTAssertThrowsError(try Mission(compactData: encoded + Data([0])))
        var prefixed = Data([0xff]); prefixed.append(encoded)
        XCTAssertEqual(try Mission(compactData: prefixed.dropFirst()), Mission())
    }
    func testLegacyJSONRemainsReadableAndTurnIsNotTruncated() throws {
        var mission = Mission(); mission.begin()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(mission)) as? [String: Any])
        object["turn"] = Int.max
        let legacy = try JSONDecoder().decode(Mission.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(legacy.isValid)
        let encoded = try legacy.compactData()
        XCTAssertEqual(encoded.count, 19)
        XCTAssertEqual(try Mission(compactData: encoded), legacy)
    }
}
