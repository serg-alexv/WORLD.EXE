import Foundation
import Dispatch

// Reference preserves the previous hash-table BFS. Both kernels return the same public route type.
@inline(never)
func reference(_ start: GridPoint, _ goal: GridPoint) -> [GridPoint]? {
    let sector = Sector.training
    guard sector.isWalkable(start), sector.isWalkable(goal) else { return nil }
    var queue = [start], head = 0
    var visited: Set<GridPoint> = [start]
    var previous: [GridPoint: GridPoint] = [:]
    while head < queue.count {
        let current = queue[head]; head += 1
        if current == goal {
            var result = [goal], cursor = goal
            while cursor != start {
                guard let parent = previous[cursor] else { return nil }
                result.append(parent); cursor = parent
            }
            result.reverse(); return result
        }
        for next in current.neighbors where sector.isWalkable(next) {
            if visited.insert(next).inserted { previous[next] = current; queue.append(next) }
        }
    }
    return nil
}
@inline(never)
func compact(_ start: GridPoint, _ goal: GridPoint) -> [GridPoint]? {
    Sector.training.path(from: start, to: goal)
}
let cells = (0..<81).map { GridPoint($0 % 9, $0 / 9) }
for a in cells { for b in cells { precondition(reference(a, b) == compact(a, b)) } }
let queries = 20_000
@inline(never)
func measure(_ optimized: Bool) -> (Double, Int) {
    var checksum = 0
    let start = DispatchTime.now().uptimeNanoseconds
    for i in 0..<queries {
        let a = cells[i % 81], b = cells[(i * 37 + 11) % 81]
        let path = optimized ? compact(a, b) : reference(a, b)
        checksum &+= path?.count ?? 0
    }
    return (Double(DispatchTime.now().uptimeNanoseconds - start) / Double(queries), checksum)
}
_ = measure(true); _ = measure(false)
var fast: [Double] = [], old: [Double] = []
for trial in 0..<7 {
    let a = measure(trial % 2 == 0), b = measure(trial % 2 != 0)
    precondition(a.1 == b.1)
    if trial % 2 == 0 { fast.append(a.0); old.append(b.0) }
    else { old.append(a.0); fast.append(b.0) }
}
fast.sort(); old.sort()
let encoded = try Mission().compactData()
print("EQUIVALENCE_PASS pairs=6561 scratch_payload_bytes=\(CompactPathfinder.scratchBytes) mask_payload_bytes=\(MemoryLayout<CellMask81>.size) save_payload_bytes=\(encoded.count)")
print(String(format: "MEDIAN_NS_PER_QUERY compact=%.1f reference=%.1f ratio=%.2f", fast[3], old[3], old[3] / fast[3]))
print("Host microbenchmark only. Not measured iPhone latency, RSS, energy or whole-app size. No timing assertion on shared CI.")
