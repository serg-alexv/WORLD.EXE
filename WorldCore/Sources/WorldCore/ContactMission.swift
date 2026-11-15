import Foundation

public enum ContactRole: String, Codable, Sendable { case researcher, `operator` }
public enum ContactPhase: String, Codable, Sendable { case active, extraction, complete }
public enum ContactGlyph: String, Codable, CaseIterable, Sendable {
    case circle, triangle, diamond
    public var channel: Int { switch self { case .circle: return 2; case .triangle: return 0; case .diamond: return 1 } }
}
public enum ContactError: String, Error, Codable, Sendable {
    case session, stale, duplicate, role, range, phase, prerequisite, exhausted
}
public enum ContactAction: Codable, Equatable, Sendable {
    case inspect(Int), power(Int), tune(Int), stabilize(Int), arm, extract
    public var role: ContactRole {
        switch self { case .power, .tune, .arm: return .operator; default: return .researcher }
    }
    public var isValid: Bool {
        switch self { case let .inspect(n), let .power(n), let .tune(n), let .stabilize(n): return (0..<3).contains(n); default: return true }
    }
}
public struct ContactCommand: Codable, Equatable, Sendable {
    public let id: UUID
    public let session: UUID
    public let revision: UInt32
    public let role: ContactRole
    public let action: ContactAction
    public init(id: UUID = UUID(), session: UUID, revision: UInt32, role: ContactRole, action: ContactAction) {
        self.id = id; self.session = session; self.revision = revision; self.role = role; self.action = action
    }
    private enum CodingKeys: String, CodingKey { case id, session, revision, role, action }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); session = try c.decode(UUID.self, forKey: .session)
        revision = try c.decode(UInt32.self, forKey: .revision); role = try c.decode(ContactRole.self, forKey: .role)
        action = try c.decode(ContactAction.self, forKey: .action)
        guard contactUUID(id), contactUUID(session), action.isValid else { throw ContactError.range }
    }
}
public struct ContactManualEntry: Codable, Equatable, Sendable {
    public let glyph: ContactGlyph
    public let channel: Int
    public static let standard = ContactGlyph.allCases.map { ContactManualEntry(glyph: $0, channel: $0.channel) }
}
public struct ContactPublicState: Codable, Equatable, Sendable {
    public let version: Int
    public let session: UUID
    public let revision: UInt32
    public let nodeIDs: [Int]
    public let inspected: UInt8
    public let stabilized: UInt8
    public let poweredNode: Int?
    public let channel: Int?
    public let mistakes: UInt16
    public let extractionArmed: Bool
    public let phase: ContactPhase
    public let manual: [ContactManualEntry]
    public var score: Int { max(0, 100 - Int(mistakes) * 10) }
    public func isInspected(_ n: Int) -> Bool { (0..<3).contains(n) && inspected & (1 << n) != 0 }
    public func isStable(_ n: Int) -> Bool { (0..<3).contains(n) && stabilized & (1 << n) != 0 }
    internal init(session: UUID, revision: UInt32 = 0, inspected: UInt8 = 0, stabilized: UInt8 = 0,
                  poweredNode: Int? = nil, channel: Int? = nil, mistakes: UInt16 = 0, phase: ContactPhase = .active) {
        version = 1; self.session = session; self.revision = revision; nodeIDs = [0, 1, 2]
        self.inspected = inspected; self.stabilized = stabilized; self.poweredNode = poweredNode
        self.channel = channel; self.mistakes = mistakes; self.phase = phase
        extractionArmed = phase != .active; manual = ContactManualEntry.standard
    }
    public var isValid: Bool {
        guard version == 1, contactUUID(session), nodeIDs == [0, 1, 2], inspected <= 7, stabilized <= 7,
              stabilized & inspected == stabilized, mistakes <= 9999, manual == ContactManualEntry.standard else { return false }
        if let n = poweredNode {
            guard (0..<3).contains(n), isInspected(n), !isStable(n) else { return false }
        } else if channel != nil { return false }
        if let c = channel, !(0..<3).contains(c) { return false }
        switch phase {
        case .active: return !extractionArmed
        case .extraction, .complete: return extractionArmed && stabilized == 7 && poweredNode == nil && channel == nil
        }
    }
    private enum CodingKeys: String, CodingKey {
        case version, session, revision, nodeIDs, inspected, stabilized, poweredNode, channel, mistakes, extractionArmed, phase, manual
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version); session = try c.decode(UUID.self, forKey: .session)
        revision = try c.decode(UInt32.self, forKey: .revision); nodeIDs = try c.decode([Int].self, forKey: .nodeIDs)
        inspected = try c.decode(UInt8.self, forKey: .inspected); stabilized = try c.decode(UInt8.self, forKey: .stabilized)
        poweredNode = try c.decodeIfPresent(Int.self, forKey: .poweredNode); channel = try c.decodeIfPresent(Int.self, forKey: .channel)
        mistakes = try c.decode(UInt16.self, forKey: .mistakes); extractionArmed = try c.decode(Bool.self, forKey: .extractionArmed)
        phase = try c.decode(ContactPhase.self, forKey: .phase); manual = try c.decode([ContactManualEntry].self, forKey: .manual)
        guard isValid else { throw ContactError.range }
    }
}
public struct ContactResearcherView: Codable, Equatable, Sendable {
    public let state: ContactPublicState
    public let glyphs: [ContactGlyph?]
    internal init(state: ContactPublicState, glyphs: [ContactGlyph?]) { self.state = state; self.glyphs = glyphs }
    private enum CodingKeys: String, CodingKey { case state, glyphs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(ContactPublicState.self, forKey: .state); glyphs = try c.decode([ContactGlyph?].self, forKey: .glyphs)
        guard glyphs.count == 3, (0..<3).allSatisfy({ (glyphs[$0] != nil) == state.isInspected($0) }),
              Set(glyphs.compactMap { $0 }).count == glyphs.compactMap({ $0 }).count else { throw ContactError.range }
    }
}
public struct ContactMission: Codable, Equatable, Sendable {
    public private(set) var state: ContactPublicState
    private let seed: UInt32
    private var recent: [UUID]
    public init(seed: UInt32, session: UUID = UUID()) {
        self.seed = seed; state = ContactPublicState(session: session); recent = []
    }
    private var order: [ContactGlyph] {
        var values = ContactGlyph.allCases; var value = seed
        for i in stride(from: 2, through: 1, by: -1) {
            value = value &* 1664525 &+ 1013904223; values.swapAt(i, Int(value % UInt32(i + 1)))
        }
        return values
    }
    public var researcher: ContactResearcherView {
        let values = order
        return ContactResearcherView(state: state, glyphs: (0..<3).map { state.isInspected($0) ? values[$0] : nil })
    }
    public func replay() -> ContactMission { ContactMission(seed: seed) }
    public mutating func apply(_ command: ContactCommand, authorizedRole: ContactRole) throws {
        guard command.session == state.session else { throw ContactError.session }
        guard !recent.contains(command.id) else { throw ContactError.duplicate }
        guard command.revision == state.revision else { throw ContactError.stale }
        guard command.role == authorizedRole, command.action.role == authorizedRole else { throw ContactError.role }
        guard command.action.isValid, contactUUID(command.id) else { throw ContactError.range }
        guard state.revision < UInt32.max else { throw ContactError.exhausted }
        let extracting = command.action == .extract
        guard state.phase == (extracting ? .extraction : .active) else { throw ContactError.phase }
        var inspected = state.inspected, stable = state.stabilized, mistakes = state.mistakes
        var power = state.poweredNode, channel = state.channel; var phase = state.phase
        switch command.action {
        case let .inspect(n):
            guard !state.isInspected(n) else { throw ContactError.prerequisite }; inspected |= 1 << n
        case let .power(n):
            guard state.isInspected(n), !state.isStable(n) else { throw ContactError.prerequisite }; power = n; channel = nil
        case let .tune(c):
            guard let n = power else { throw ContactError.prerequisite }; channel = c
            if c != order[n].channel { mistakes = min(9999, mistakes + 1) }
        case let .stabilize(n):
            guard power == n, channel == order[n].channel, state.isInspected(n) else { throw ContactError.prerequisite }
            stable |= 1 << n; power = nil; channel = nil
        case .arm:
            guard stable == 7 else { throw ContactError.prerequisite }; phase = .extraction
        case .extract: phase = .complete
        }
        state = ContactPublicState(session: state.session, revision: state.revision + 1, inspected: inspected,
                                   stabilized: stable, poweredNode: power, channel: channel, mistakes: mistakes, phase: phase)
        recent.append(command.id); if recent.count > 64 { recent.removeFirst(recent.count - 64) }
    }
    private enum CodingKeys: String, CodingKey { case state, seed, recent }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(ContactPublicState.self, forKey: .state); seed = try c.decode(UInt32.self, forKey: .seed)
        recent = try c.decode([UUID].self, forKey: .recent)
        guard recent.count <= 64, Set(recent).count == recent.count, recent.allSatisfy(contactUUID),
              UInt64(recent.count) <= UInt64(state.revision) else { throw ContactError.range }
    }
}
private func contactUUID(_ id: UUID) -> Bool { id.uuidString != "00000000-0000-0000-0000-000000000000" }
