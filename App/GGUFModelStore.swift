import Foundation
import CryptoKit

/// Opt-in GGUF asset management. Downloading a model does not enable inference:
/// the llama.cpp XCFramework bridge is a separate, version-pinned release gate.
@MainActor
final class GGUFModelStore: ObservableObject {
    enum ModelError: Error {
        case untrustedHost, invalidFile, oversized, checksumMismatch, missingChecksum
    }
    @Published private(set) var installedURL: URL?
    @Published private(set) var state = "No model installed"
    private let maxBytes: Int64 = 2_000_000_000

    /// Only accept HTTPS model artifacts from the approved model host.
    /// The expected SHA-256 must come from a separately reviewed manifest.
    func install(from remote: URL, expectedSHA256: String) async throws {
        guard remote.scheme == "https",
              remote.host?.lowercased() == "huggingface.co" else {
            throw ModelError.untrustedHost
        }
        guard expectedSHA256.count == 64,
              expectedSHA256.allSatisfy({ $0.isHexDigit }) else {
            throw ModelError.missingChecksum
        }
        state = "Downloading verified model"
        let (temporary, response) = try await URLSession.shared.download(from: remote)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else { throw ModelError.invalidFile }
        let size = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size >= 1024, size <= maxBytes else { throw ModelError.oversized }
        let handle = try FileHandle(forReadingFrom: temporary)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data([0x47, 0x47, 0x55, 0x46]) else {
            throw ModelError.invalidFile
        }
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw ModelError.checksumMismatch
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("tactical-\(digest.prefix(16)).gguf")
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: temporary, to: destination)
        }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: destination.path)
        installedURL = destination
        state = "Verified GGUF installed; inference backend not yet linked"
    }

    func removeInstalledModel() throws {
        if let installedURL { try FileManager.default.removeItem(at: installedURL) }
        installedURL = nil
        state = "No model installed"
    }
}
