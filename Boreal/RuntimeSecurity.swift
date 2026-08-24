import CryptoKit
import Foundation

nonisolated enum RuntimeSecurity {
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 4 * 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated protocol RuntimeCatalogLoading: Sendable {
    func loadCatalog() async throws -> [BorealRuntime]
}

nonisolated struct SignedRuntimeCatalogLoader: RuntimeCatalogLoading {
    let manifestURL: URL
    let signatureURL: URL
    let publicKey: Curve25519.Signing.PublicKey
    var session: URLSession = .shared

    func loadCatalog() async throws -> [BorealRuntime] {
        let (manifest, manifestResponse) = try await session.data(from: manifestURL)
        let (signature, signatureResponse) = try await session.data(from: signatureURL)
        guard (manifestResponse as? HTTPURLResponse)?.statusCode == 200,
              (signatureResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw RuntimeManagerError.downloadFailed("The signed catalog is unavailable.")
        }
        guard publicKey.isValidSignature(signature, for: manifest) else { throw RuntimeManagerError.manifestSignatureInvalid }
        do { return try JSONDecoder().decode([BorealRuntime].self, from: manifest) }
        catch { throw RuntimeManagerError.invalidManifest }
    }
}

nonisolated struct EmptyRuntimeCatalog: RuntimeCatalogLoading {
    func loadCatalog() async throws -> [BorealRuntime] { [] }
}

#if DEBUG
nonisolated struct LocalDevelopmentRuntimeCatalog: RuntimeCatalogLoading {
    let url: URL
    func loadCatalog() async throws -> [BorealRuntime] {
        do { return try JSONDecoder().decode([BorealRuntime].self, from: Data(contentsOf: url)) }
        catch { throw RuntimeManagerError.invalidManifest }
    }
}
#endif
