/// Specialized to the fixed 9x9 training sector. No hash tables or path-prefix queues.
/// Scratch payload: 81 predecessor bytes + 81 queue bytes; blocked mask: 16 bytes.
/// Returned route storage and compiler/runtime overhead are separate.
struct CellMask81 {
    var low: UInt64 = 0
    var high: UInt64 = 0
    mutating func insert(_ cell: Int) {
        precondition((0..<81).contains(cell))
        if cell < 64 { low |= UInt64(1) << UInt64(cell) }
        else { high |= UInt64(1) << UInt64(cell - 64) }
    }
    func contains(_ cell: Int) -> Bool {
        precondition((0..<81).contains(cell))
        if cell < 64 { return low & (UInt64(1) << UInt64(cell)) != 0 }
        return high & (UInt64(1) << UInt64(cell - 64)) != 0
    }
}

enum CompactPathfinder {
    static let cellCount = 81
    static let scratchBytes = cellCount * 2
    private static let baseMask: CellMask81 = {
        var mask = CellMask81()
        for point in Sector.training.obstacles { mask.insert(point.y * 9 + point.x) }
        return mask
    }()

    static func path(from start: GridPoint, to goal: GridPoint,
                     avoiding extra: Set<GridPoint> = []) -> [GridPoint]? {
        let sector = Sector.training
        guard sector.contains(start), sector.contains(goal) else { return nil }
        let startID = start.y * 9 + start.x, goalID = goal.y * 9 + goal.x
        var blocked = baseMask
        for point in extra where sector.contains(point) { blocked.insert(point.y * 9 + point.x) }
        guard !blocked.contains(startID), !blocked.contains(goalID) else { return nil }
        if startID == goalID { return [start] }
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: scratchBytes) { storage in
            storage.initialize(repeating: .max)
            defer { storage.deinitialize() }
            // Pointers remain inside this closure; every byte is initialized before reading.
            let parents = storage.baseAddress!
            let queue = parents.advanced(by: cellCount)
            parents[startID] = UInt8(startID)
            queue[0] = UInt8(startID)
            var head = 0, tail = 1
            while head < tail {
                let current = Int(queue[head]); head += 1
                if current == goalID {
                    var cursor = goalID, count = 1
                    while cursor != startID { cursor = Int(parents[cursor]); count += 1 }
                    var route: [GridPoint] = []
                    route.reserveCapacity(count)
                    cursor = goalID
                    while true {
                        route.append(GridPoint(cursor % 9, cursor / 9))
                        if cursor == startID { break }
                        cursor = Int(parents[cursor])
                    }
                    route.reverse()
                    return route
                }
                let column = current % 9
                // Preserve legacy N, E, S, W tie-breaking without allocating neighbors.
                for direction in 0..<4 {
                    let next: Int
                    switch direction {
                    case 0: guard current >= 9 else { continue }; next = current - 9
                    case 1: guard column < 8 else { continue }; next = current + 1
                    case 2: guard current < 72 else { continue }; next = current + 9
                    default: guard column > 0 else { continue }; next = current - 1
                    }
                    if parents[next] != .max || blocked.contains(next) { continue }
                    parents[next] = UInt8(current)
                    // Each of 81 cells enters the queue at most once.
                    assert(tail < cellCount)
                    queue[tail] = UInt8(next); tail += 1
                }
            }
            return nil
        }
    }
}
