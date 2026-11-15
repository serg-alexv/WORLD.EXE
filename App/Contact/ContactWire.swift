import Foundation
import simd
import WorldCore

struct ContactSurface: Codable, Equatable, Sendable {
    let kind: String
    let dimensions: [Float]
    let transform: [Float]
    var valid: Bool {
        !kind.isEmpty && kind.utf8.count <= 32 && dimensions.count == 3 &&
        dimensions.allSatisfy { $0.isFinite && $0 >= 0 && $0 < 1000 } && dimensions.contains { $0 > 0 } && ContactMath.valid(transform)
    }
}
enum ContactMath {
    static let identity: [Float] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    static let offsets: [SIMD3<Float>] = [SIMD3(-0.22,0,-0.16), SIMD3(0.22,0,-0.16), SIMD3(0,0,0.24)]
    static func matrix(_ a: [Float]) -> simd_float4x4 {
        guard a.count == 16 else { return matrix_identity_float4x4 }
        return simd_float4x4(columns: (SIMD4(a[0],a[1],a[2],a[3]), SIMD4(a[4],a[5],a[6],a[7]),
                                     SIMD4(a[8],a[9],a[10],a[11]), SIMD4(a[12],a[13],a[14],a[15])))
    }
    static func array(_ m: simd_float4x4) -> [Float] {
        [m.columns.0,m.columns.1,m.columns.2,m.columns.3].flatMap { [$0.x,$0.y,$0.z,$0.w] }
    }
    static func valid(_ a: [Float], horizontal: Bool = false) -> Bool {
        guard a.count == 16, a.allSatisfy({ $0.isFinite && abs($0) < 10000 }),
              abs(a[3]) < 0.001, abs(a[7]) < 0.001, abs(a[11]) < 0.001, abs(a[15] - 1) < 0.001 else { return false }
        let m = matrix(a); let x = SIMD3(m.columns.0.x,m.columns.0.y,m.columns.0.z)
        let y = SIMD3(m.columns.1.x,m.columns.1.y,m.columns.1.z), z = SIMD3(m.columns.2.x,m.columns.2.y,m.columns.2.z)
        return [x,y,z].allSatisfy { abs(simd_length($0) - 1) < 0.04 } &&
            abs(simd_dot(x,y)) < 0.04 && abs(simd_dot(x,z)) < 0.04 && abs(simd_dot(y,z)) < 0.04 &&
            simd_dot(simd_cross(x,y),z) > 0.9 && (!horizontal || simd_length(y - SIMD3(0,1,0)) < 0.04)
    }
}
struct ContactRoomDTO: Codable, Equatable, Sendable {
    let version: Int
    let synthetic: Bool
    let captureID: UUID?
    let capturedAt: Date?
    let surfaces: [ContactSurface]
    var valid: Bool { version == 1 && !surfaces.isEmpty && surfaces.count <= 512 && surfaces.allSatisfy { $0.valid } }
    init?(snapshot: RoomSnapshot, captureID: UUID? = nil, capturedAt: Date? = nil) {
        version = 1; synthetic = false; self.captureID = captureID; self.capturedAt = capturedAt
        surfaces = snapshot.elements.map { ContactSurface(kind: $0.kind, dimensions: $0.dimensions, transform: $0.transform) }
        guard snapshot.isValid, valid else { return nil }
    }
    private init(surfaces: [ContactSurface]) { version = 1; synthetic = true; captureID = nil; capturedAt = nil; self.surfaces = surfaces }
    static var demo: ContactRoomDTO {
        var t = ContactMath.identity; t[13] = -0.04
        return ContactRoomDTO(surfaces: [ContactSurface(kind: "table", dimensions: [1.4,0.04,1], transform: t)])
    }
    private enum CodingKeys: String, CodingKey { case version, synthetic, surfaces, captureID, capturedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version); synthetic = try c.decode(Bool.self, forKey: .synthetic)
        captureID = try c.decodeIfPresent(UUID.self, forKey: .captureID)
        capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt)
        surfaces = try c.decode([ContactSurface].self, forKey: .surfaces)
        guard valid else { throw ContactError.range }
    }
    var bounds: (SIMD3<Float>, SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for s in surfaces {
            let m = ContactMath.matrix(s.transform), d = s.dimensions
            for x: Float in [-0.5,0.5] { for y: Float in [-0.5,0.5] { for z: Float in [-0.5,0.5] {
                let p = m * SIMD4(x*d[0],y*d[1],z*d[2],1); let v = SIMD3(p.x,p.y,p.z)
                lo = simd_min(lo,v); hi = simd_max(hi,v)
            } } }
        }
        return (lo,hi)
    }
    func contains(_ root: [Float]) -> Bool {
        guard ContactMath.valid(root, horizontal: true) else { return false }
        let (lo,hi) = bounds, m = ContactMath.matrix(root)
        return ([SIMD3<Float>.zero] + ContactMath.offsets).allSatisfy {
            let p = m * SIMD4($0.x,$0.y,$0.z,1)
            return p.x >= lo.x + 0.05 && p.x <= hi.x - 0.05 && p.z >= lo.z + 0.05 && p.z <= hi.z - 0.05 && p.y >= lo.y - 0.2 && p.y <= hi.y + 0.2
        }
    }
}
struct ContactPacket: Codable {
    enum Kind: String, Codable { case welcome, state, placement, command, rejected, beat }
    let version: Int = 1
    let kind: Kind
    let session: UUID
    let revision: UInt32
    var state: ContactPublicState? = nil
    var room: ContactRoomDTO? = nil
    var root: [Float]? = nil
    var command: ContactCommand? = nil
    var commandID: UUID? = nil
    var ready: Bool? = nil
    var error: ContactError? = nil
    private enum CodingKeys: String, CodingKey { case version, kind, session, revision, state, room, root, command, commandID, ready, error }
    init(kind: Kind, state: ContactPublicState) { self.kind = kind; session = state.session; revision = state.revision }
    init(command: ContactCommand) { kind = .command; session = command.session; revision = command.revision; self.command = command }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .version) == 1 else { throw ContactError.range }
        kind = try c.decode(Kind.self, forKey: .kind); session = try c.decode(UUID.self, forKey: .session); revision = try c.decode(UInt32.self, forKey: .revision)
        state = try c.decodeIfPresent(ContactPublicState.self, forKey: .state); room = try c.decodeIfPresent(ContactRoomDTO.self, forKey: .room)
        root = try c.decodeIfPresent([Float].self, forKey: .root); command = try c.decodeIfPresent(ContactCommand.self, forKey: .command)
        commandID = try c.decodeIfPresent(UUID.self, forKey: .commandID); ready = try c.decodeIfPresent(Bool.self, forKey: .ready); error = try c.decodeIfPresent(ContactError.self, forKey: .error)
        let fields = Set([state != nil,room != nil,root != nil,command != nil,commandID != nil,ready != nil,error != nil].enumerated().compactMap { $0.element ? $0.offset : nil })
        guard session.uuidString != "00000000-0000-0000-0000-000000000000", state.map({ $0.session == session && $0.revision == revision }) ?? true,
              root.map({ ContactMath.valid($0, horizontal: true) }) ?? true else { throw ContactError.range }
        switch kind {
        case .welcome: guard fields == [0,1] || fields == [0,1,2], room?.synthetic == false else { throw ContactError.range }
        case .state: guard fields == [0,4] else { throw ContactError.range }
        case .placement: guard fields == [2] else { throw ContactError.range }
        case .command: guard fields == [3], command?.session == session, command?.revision == revision else { throw ContactError.range }
        case .rejected: guard fields == [0,4,6] else { throw ContactError.range }
        case .beat: guard fields == [5] else { throw ContactError.range }
        }
    }
    static func decode(_ data: Data) throws -> ContactPacket {
        guard !data.isEmpty, data.count <= 256 * 1024 else { throw ContactError.range }
        return try JSONDecoder().decode(ContactPacket.self, from: data)
    }
}
