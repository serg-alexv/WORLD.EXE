import Foundation

/// Retains an origin only in process memory. Export only differences between app events.
/// This is not a cross-device synchronization clock or a measurement of device boot time.
public struct EvidenceClock: Sendable {
    private let origin: Double
    public init(monotonicOrigin: Double) throws {
        guard monotonicOrigin.isFinite, monotonicOrigin >= 0 else { throw EvidenceError.invalidRecord }
        origin = monotonicOrigin
    }
    public func elapsed(at monotonicTime: Double) throws -> Double {
        guard monotonicTime.isFinite, monotonicTime >= origin else { throw EvidenceError.staleSequence }
        let interval = monotonicTime - origin
        guard interval.isFinite else { throw EvidenceError.invalidRecord }
        return interval
    }
}
