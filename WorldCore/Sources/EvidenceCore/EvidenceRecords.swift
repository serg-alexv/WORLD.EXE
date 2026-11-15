import Foundation

public enum EvidenceError: Error, Equatable { case invalidRecord, wrongLane, invalidCapacity, tooLarge, staleSequence, wrongSession }
public enum EvidenceLane: String, Codable, Sendable { case observation, telemetry, gameplay }
public enum ObservationNature: String, Codable, Sendable { case estimate }
public enum ObservationSource: String, Codable, Sendable { case arkit, roomPlan }
public enum ObservationOrigin: String, Codable, Sendable { case localSensor, restoredArchive, peerReport }
public enum TrackingQuality: String, Codable, Sendable { case normal, limited, unavailable }
public enum BackendRequest: String, Codable, Sendable { case cpu, metal }
public enum ConfirmedBackend: String, Codable, Sendable { case cpu, metal }
public enum OperationOutcome: String, Codable, Sendable { case succeeded, cancelled, failed }
public enum RuntimeCondition: String, Codable, Sendable { case nominal, fair, serious, critical, unknown, memoryWarning, background }

public struct EvidenceStamp: Codable, Equatable, Sendable {
    public let id: UUID
    public let session: UUID
    public let sequence: UInt64
    public let recordedAt: Date
    /// Seconds on the local process's monotonic clock. Never compare across sessions/devices.
    public let uptime: Double
    public init(id: UUID = UUID(), session: UUID, sequence: UInt64, recordedAt: Date, uptime: Double) throws {
        self.id = id; self.session = session; self.sequence = sequence; self.recordedAt = recordedAt; self.uptime = uptime
        guard isValid else { throw EvidenceError.invalidRecord }
    }
    public var isValid: Bool {
        id != zeroUUID && session != zeroUUID && sequence > 0 && uptime.isFinite && uptime >= 0 && recordedAt.timeIntervalSince1970.isFinite
    }
}
private let zeroUUID = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))

public enum ObservationPayload: Codable, Equatable, Sendable {
    /// Count of reconstructed elements, not a calibrated count of real-world objects.
    case roomSummary(elements: Int)
    case meshSummary(vertices: Int, triangles: Int)
    case tracking(TrackingQuality)
    fileprivate var valid: Bool {
        switch self {
        case .roomSummary(let n): return (1...512).contains(n)
        case .meshSummary(let v, let t): return (1...50_000).contains(v) && (1...100_000).contains(t)
        case .tracking: return true
        }
    }
    fileprivate func accepts(_ source: ObservationSource) -> Bool {
        switch self { case .roomSummary: return source == .roomPlan; default: return source == .arkit }
    }
}

/// Only sensor-derived estimates belong here. Game objects and model text have no representation.
public struct ObservationRecord: Codable, Equatable, Sendable {
    public let nature: ObservationNature
    public let lane: EvidenceLane
    public let stamp: EvidenceStamp
    public let source: ObservationSource
    public let origin: ObservationOrigin
    public let captureID: UUID
    /// Original capture/processing time, retained when restoring an archive.
    public let capturedAt: Date?
    /// Original ARFrame.timestamp, in the AR session's clock; not UTC.
    public let sensorTimestamp: Double?
    public let payload: ObservationPayload
    public var isPhysicalMeasurement: Bool { false } // This version exposes estimates, not calibrated raw ranging.
    public var isValid: Bool {
        guard lane == .observation, stamp.isValid, captureID != zeroUUID, payload.valid, payload.accepts(source),
              capturedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              sensorTimestamp.map({ $0.isFinite && $0 >= 0 }) ?? true else { return false }
        if origin == .restoredArchive && capturedAt == nil { return false }
        if source == .roomPlan && sensorTimestamp != nil { return false }
        return true
    }
    public init(stamp: EvidenceStamp, source: ObservationSource, origin: ObservationOrigin,
                captureID: UUID, capturedAt: Date? = nil, sensorTimestamp: Double? = nil, payload: ObservationPayload) throws {
        nature = .estimate; lane = .observation; self.stamp = stamp; self.source = source; self.origin = origin
        self.captureID = captureID; self.capturedAt = capturedAt; self.sensorTimestamp = sensorTimestamp; self.payload = payload
        guard isValid else { throw EvidenceError.invalidRecord }
    }
    private enum CodingKeys: String, CodingKey { case nature, lane, stamp, source, origin, captureID, capturedAt, sensorTimestamp, payload }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(EvidenceLane.self, forKey: .lane) == .observation,
              try c.decode(ObservationNature.self, forKey: .nature) == .estimate else { throw EvidenceError.wrongLane }
        try self.init(stamp: c.decode(EvidenceStamp.self, forKey: .stamp), source: c.decode(ObservationSource.self, forKey: .source),
                      origin: c.decode(ObservationOrigin.self, forKey: .origin), captureID: c.decode(UUID.self, forKey: .captureID),
                      capturedAt: c.decodeIfPresent(Date.self, forKey: .capturedAt), sensorTimestamp: c.decodeIfPresent(Double.self, forKey: .sensorTimestamp),
                      payload: c.decode(ObservationPayload.self, forKey: .payload))
    }
}

public struct InferenceSample: Codable, Equatable, Sendable {
    public let modelSHA256: String
    public let requestedBackend: BackendRequest
    /// nil means not instrumented. A request for Metal does not prove GPU execution.
    public let confirmedBackend: ConfirmedBackend?
    public let tokens: Int?
    /// Native request duration, including prompt evaluation; not token-decode-only time.
    public let requestSeconds: Double?
    public let outcome: OperationOutcome
    public var requestTokensPerSecond: Double? {
        guard let tokens, let seconds = requestSeconds, seconds > 0 else { return nil }
        let value = Double(tokens) / seconds
        return value.isFinite ? value : nil
    }
    public var isValid: Bool {
        modelSHA256.utf8.count == 64 && modelSHA256.allSatisfy({ $0.isASCII && $0.isHexDigit }) &&
        (tokens.map({ (0...256).contains($0) }) ?? true) &&
        (requestSeconds.map({ $0.isFinite && $0 >= 0 && $0 <= 3600 }) ?? true) &&
        !(requestedBackend == .cpu && confirmedBackend == .metal)
    }
    public init(modelSHA256: String, requestedBackend: BackendRequest, confirmedBackend: ConfirmedBackend? = nil,
                tokens: Int?, requestSeconds: Double?, outcome: OperationOutcome) throws {
        self.modelSHA256 = modelSHA256; self.requestedBackend = requestedBackend; self.confirmedBackend = confirmedBackend
        self.tokens = tokens; self.requestSeconds = requestSeconds; self.outcome = outcome
        guard isValid else { throw EvidenceError.invalidRecord }
    }
}
public enum TelemetryPayload: Codable, Equatable, Sendable {
    case inference(InferenceSample)
    /// Bytes accepted by the local transport API, not delivery confirmation or RTT.
    case network(bytes: Int, outbound: Bool, accepted: Bool)
    case runtime(RuntimeCondition)
    case captureDuration(seconds: Double, outcome: OperationOutcome)
    fileprivate var valid: Bool {
        switch self {
        case .inference(let s): return s.isValid
        case .network(let bytes, _, _): return (1...262_144).contains(bytes)
        case .runtime: return true
        case .captureDuration(let s, _): return s.isFinite && s >= 0 && s <= 86_400
        }
    }
}
public struct TelemetryRecord: Codable, Equatable, Sendable {
    public let lane: EvidenceLane
    public let stamp: EvidenceStamp
    public let payload: TelemetryPayload
    public var isValid: Bool { lane == .telemetry && stamp.isValid && payload.valid }
    public init(stamp: EvidenceStamp, payload: TelemetryPayload) throws {
        lane = .telemetry; self.stamp = stamp; self.payload = payload
        guard isValid else { throw EvidenceError.invalidRecord }
    }
    private enum CodingKeys: String, CodingKey { case lane, stamp, payload }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(EvidenceLane.self, forKey: .lane) == .telemetry else { throw EvidenceError.wrongLane }
        try self.init(stamp: c.decode(EvidenceStamp.self, forKey: .stamp), payload: c.decode(TelemetryPayload.self, forKey: .payload))
    }
}

public enum GameEventKind: String, Codable, Sendable {
    case trainingCommand, contactCommand, rejectedCommand, demoStarted, pairStarted, peerState, placement, replay, reset
}
public struct GameEventRecord: Codable, Equatable, Sendable {
    public let lane: EvidenceLane
    public let stamp: EvidenceStamp
    public let missionID: UUID
    public let kind: GameEventKind
    /// Bounded command name, not a prompt, response, user name or sensor reading.
    public let action: String
    public let revision: UInt32?
    public let score: Int?
    public var isValid: Bool {
        lane == .gameplay && stamp.isValid && missionID != zeroUUID && !action.isEmpty && action.utf8.count <= 64 &&
        action.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._:-".contains($0)) }) &&
        (score.map({ (0...100).contains($0) }) ?? true)
    }
    public init(stamp: EvidenceStamp, missionID: UUID, kind: GameEventKind, action: String, revision: UInt32? = nil, score: Int? = nil) throws {
        lane = .gameplay; self.stamp = stamp; self.missionID = missionID; self.kind = kind; self.action = action; self.revision = revision; self.score = score
        guard isValid else { throw EvidenceError.invalidRecord }
    }
    private enum CodingKeys: String, CodingKey { case lane, stamp, missionID, kind, action, revision, score }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(EvidenceLane.self, forKey: .lane) == .gameplay else { throw EvidenceError.wrongLane }
        try self.init(stamp: c.decode(EvidenceStamp.self, forKey: .stamp), missionID: c.decode(UUID.self, forKey: .missionID),
                      kind: c.decode(GameEventKind.self, forKey: .kind), action: c.decode(String.self, forKey: .action),
                      revision: c.decodeIfPresent(UInt32.self, forKey: .revision), score: c.decodeIfPresent(Int.self, forKey: .score))
    }
}
