/// Local AR input safety. A network snapshot cannot clear a local tracking-loss latch.
public struct ArenaTrackingGate: Equatable, Sendable {
    public private(set) var trackingReady = true
    public private(set) var requiresResume = false
    public init() {}
    public mutating func updateTracking(_ ready: Bool) {
        trackingReady = ready
        if !ready { requiresResume = true }
    }
    @discardableResult public mutating func resume() -> Bool {
        guard trackingReady else { return false }
        requiresResume = false
        return true
    }
    public func permitsActions(authorityPaused: Bool) -> Bool {
        trackingReady && !requiresResume && !authorityPaused
    }
}
