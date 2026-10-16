import Foundation

/// Identity of the Wine/GPTK host, independent of its graphics deployment.
/// The fingerprint groups inventory entries only. It never authorizes replacing
/// a game's runtime: matching loader files do not prove graphics ABI compatibility.
nonisolated struct RuntimeBaseIdentity: Codable, Sendable, Hashable {
    let engine: RuntimeEngine
    let version: String
    let architecture: RuntimeArchitecture
    let hostSHA256: String

    var id: String { "\(engine.rawValue)-\(version)-\(architecture.rawValue)-\(hostSHA256)" }
    var displayName: String {
        "\(engine == .gamePortingToolkit ? "GPTK" : "Wine") \(version)"
    }
}

/// A renderer is a component of a deployment, never the host's identity.
/// D3DMetal remains paired with its compatible loader; WineD3D is built in.
nonisolated struct InstalledGraphicsComponent: Codable, Sendable, Hashable, Identifiable {
    enum Source: String, Codable, Sendable { case sharedStore, runtimeBundle, builtin }
    let backend: GraphicsBackend
    let version: String?
    let source: Source
    let reference: GraphicsComponentReference?

    var id: String { "\(backend.rawValue)-\(version ?? "unknown")-\(source.rawValue)-\(reference?.sha256 ?? "bundled")" }
    var isLegacy: Bool {
        backend == .dxvk && normalizedVersion?.hasPrefix("1.") == true
    }
    var normalizedVersion: String? {
        guard let version, !version.isEmpty else { return nil }
        return version.hasPrefix("v") ? String(version.dropFirst()) : version
    }
    var displayName: String {
        let versionLabel = normalizedVersion.map { " " + $0 } ?? ""
        let name = backend == .wineD3D ? "WineD3D" : backend.displayName
        return name + versionLabel + (isLegacy ? " Legacy" : "")
    }
}

nonisolated enum RuntimeInventory {
    static func baseIdentity(for runtime: InstalledRuntime) -> RuntimeBaseIdentity? {
        let wineRoot = runtime.rootURL.appending(path: "Runtime/Wine.app/Contents/Resources/wine")
        let files = [
            runtime.wineExecutable,
            runtime.wineServerExecutable,
            wineRoot.appending(path: "lib/wine/x86_64-unix/ntdll.so"),
            wineRoot.appending(path: "lib/wine/x86_64-windows/ntdll.dll")
        ]
        // Unknown/custom layouts remain separate, rather than being grouped
        // merely because their advertised versions happen to match.
        let hashes = files.compactMap { try? RuntimeSecurity.sha256(of: $0) }
        guard hashes.count == files.count else { return nil }
        return RuntimeBaseIdentity(
            engine: runtime.hostEngine ?? runtime.resolvedEngine,
            version: runtime.wineVersion,
            architecture: runtime.architecture,
            hostSHA256: RuntimeSecurity.sha256(data: Data(hashes.joined(separator: "\n").utf8))
        )
    }

    static func graphicsComponents(
        for runtime: InstalledRuntime,
        store: GraphicsComponentStore
    ) -> [InstalledGraphicsComponent] {
        var result: [InstalledGraphicsComponent] = []
        if runtime.resolvedEngine == .wine {
            result.append(.init(backend: .wineD3D, version: nil, source: .builtin, reference: nil))
        }
        if runtime.features?.d3dmetal == true {
            result.append(.init(backend: .d3dMetal, version: runtime.features?.d3dmetalVersion, source: .runtimeBundle, reference: nil))
        }
        // The current resolver qualifies optional DXMT/DXVK/VKD3D packages
        // for Wine deployments. Shared storage alone does not qualify GPTK.
        guard runtime.resolvedEngine == .wine else { return result }
        for component in RuntimeComponent.allCases {
            let available: Bool
            let backend: GraphicsBackend
            switch component {
            case .dxmt: available = runtime.features?.dxmt == true || hasBundledDXMT(in: runtime); backend = .dxmt
            case .dxvk: available = runtime.features?.dxvk == true; backend = .dxvk
            case .vkd3d: available = runtime.features?.vkd3d == true; backend = .vkd3d
            }
            guard available else { continue }
            let reference = store.reference(for: component)
            let receiptURL = runtime.rootURL.appending(path: "GraphicsComponents/\(component.directoryName)/component.json")
            let legacyVersion = receiptVersion(at: receiptURL)
                ?? advertisedComponentVersion(backend, in: runtime.displayName)
            result.append(.init(
                backend: backend,
                version: reference?.version ?? legacyVersion,
                source: reference == nil ? .runtimeBundle : .sharedStore,
                reference: reference
            ))
        }
        return result
    }

    static func hasBundledDXMT(in runtime: InstalledRuntime) -> Bool {
        guard runtime.resolvedEngine == .wine else { return false }
        let libraries = runtime.rootURL.appending(path: "Runtime/Wine.app/Contents/Resources/wine/lib/wine")
        let windowsFolders = runtime.features?.resolvedArchitectureCapabilities.canRunX86 == true
            ? ["x86_64-windows", "i386-windows"] : ["x86_64-windows"]
        return windowsFolders.allSatisfy { folder in
            ["dxgi.dll", "d3d11.dll", "winemetal.dll"].allSatisfy {
                FileManager.default.isReadableFile(atPath: libraries.appending(path: "\(folder)/\($0)").path)
            }
        } && FileManager.default.isReadableFile(atPath: libraries.appending(path: "x86_64-unix/winemetal.so").path)
    }

    private static func receiptVersion(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["version"] as? String
    }

    private static func advertisedComponentVersion(_ backend: GraphicsBackend, in name: String) -> String? {
        // Old generated descriptors recorded bundled versions in their name.
        // Retain that metadata without interpreting a version as verification.
        guard let range = name.range(of: " + \(backend.displayName) ") else { return nil }
        return name[range.upperBound...].split(separator: " ").first.map(String.init)
    }

    static func displayName(_ original: String, engine: RuntimeEngine, version: String) -> String {
        let name = original.replacingOccurrences(of: " (Local Snapshot)", with: "")
        if engine == .gamePortingToolkit {
            return "GPTK \(version)"
        }
        if name.hasPrefix("Wine \(version) + ") { return "Wine \(version)" }
        if name == "Wine Devel" { return "Wine \(version) Devel" }
        return name
    }
}

/// Existing deployments keep their IDs and capability checks. The inventory
/// exposes one host with components and expandable compatibility snapshots.
struct RuntimeFamily: Identifiable, Sendable {
    let id: String
    let deployments: [RuntimeStatus]
    var primary: RuntimeStatus { deployments[0] }
    var name: String { primary.name }
    var graphicsComponents: [InstalledGraphicsComponent] {
        let components = Array(Set(deployments.flatMap(\.graphicsComponents)))
        return components.filter { component in
            component.version != nil || component.source == .builtin
                || !components.contains { $0.backend == component.backend && $0.version != nil }
        }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    static func group(_ statuses: [RuntimeStatus]) -> [RuntimeFamily] {
        Dictionary(grouping: statuses) { status in
            // Catalog entries have no inspected payload and must stay separate.
            status.source == .installed ? (status.baseIdentity?.id ?? status.id) : status.id
        }.map { id, values in
            let deployments = values.sorted { lhs, rhs in
                if lhs.isVerified != rhs.isVerified { return lhs.isVerified }
                let left = lhs.features?.d3dmetalVersion ?? ""
                let right = rhs.features?.d3dmetalVersion ?? ""
                if left != right { return left.localizedStandardCompare(right) == .orderedDescending }
                return lhs.id < rhs.id
            }
            return RuntimeFamily(id: id, deployments: deployments)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
