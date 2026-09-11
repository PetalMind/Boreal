import Foundation

/// Immutable, versioned storage for optional graphics translators. Runtime
/// packages never own this directory; multiple runtimes and environments can
/// safely refer to the same component snapshot.
nonisolated struct GraphicsComponentStore: Sendable {
    let rootURL: URL

    init(applicationSupportURL: URL) {
        rootURL = applicationSupportURL.appending(path: "Components", directoryHint: .isDirectory)
    }

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    func componentURL(_ component: RuntimeComponent, version: String) -> URL {
        rootURL
            .appending(path: component.directoryName, directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)
    }

    func upscalingComponentURL(_ bridge: TemporalUpscalingBridge, version: String) -> URL {
        rootURL
            .appending(path: "Upscaling", directoryHint: .isDirectory)
            .appending(path: bridge.directoryName, directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)
    }

    static func isSafeVersion(_ version: String) -> Bool {
        !version.isEmpty
            && version != "."
            && version != ".."
            && !version.contains("/")
            && !version.contains("\\")
            && !version.contains("..")
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.contains("\\")
            && !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }

    func references(for component: RuntimeComponent, fileManager: FileManager = .default) -> [GraphicsComponentReference] {
        let componentRoot = rootURL.appending(path: component.directoryName, directoryHint: .isDirectory)
        guard let children = try? fileManager.contentsOfDirectory(at: componentRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return children.compactMap { root in
            guard (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let receiptURL = root.appending(path: "component.json")
            guard let data = try? Data(contentsOf: receiptURL),
                  let receipt = try? JSONDecoder().decode(RuntimeComponentReceipt.self, from: data),
                  root.lastPathComponent == receipt.version,
                  Self.isSafeVersion(receipt.version),
                  receipt.component == component,
                  receipt.sha256.count == 64,
                  receipt.sha256.allSatisfy({ $0.isHexDigit }),
                  receipt.installedFiles.allSatisfy(Self.isSafeRelativePath) else { return nil }
            return GraphicsComponentReference(
                component: component,
                version: receipt.version,
                sha256: receipt.sha256,
                installedFiles: receipt.installedFiles
            )
        }.sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }

    func reference(
        for component: RuntimeComponent,
        version: String? = nil,
        fileManager: FileManager = .default
    ) -> GraphicsComponentReference? {
        let values = references(for: component, fileManager: fileManager)
        if let version {
            return values.first { $0.version == version }
        }
        return values.first
    }

    func contains(_ reference: GraphicsComponentReference, fileManager: FileManager = .default) -> Bool {
        guard Self.isSafeVersion(reference.version) else { return false }
        let root = componentURL(reference.component, version: reference.version)
        guard fileManager.fileExists(atPath: root.path) else { return false }
        guard let receipt = try? Data(contentsOf: root.appending(path: "component.json")),
              let value = try? JSONDecoder().decode(RuntimeComponentReceipt.self, from: receipt) else { return false }
        guard value.component == reference.component,
              root.lastPathComponent == value.version,
              value.version == reference.version,
              value.sha256 == reference.sha256,
              value.installedFiles.allSatisfy(Self.isSafeRelativePath),
              reference.installedFiles.allSatisfy(Self.isSafeRelativePath) else { return false }
        let installedFiles = Set(value.installedFiles).union(reference.installedFiles)
        return !installedFiles.isEmpty && installedFiles.allSatisfy {
            fileManager.fileExists(atPath: root.appending(path: $0).path)
        }
    }

    func upscalingReferences(
        for bridge: TemporalUpscalingBridge,
        fileManager: FileManager = .default
    ) -> [UpscalingBridgeReference] {
        let bridgeRoot = rootURL
            .appending(path: "Upscaling", directoryHint: .isDirectory)
            .appending(path: bridge.directoryName, directoryHint: .isDirectory)
        guard let children = try? fileManager.contentsOfDirectory(
            at: bridgeRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.compactMap { root in
            guard (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let receiptURL = root.appending(path: "bridge.json")
            guard let data = try? Data(contentsOf: receiptURL),
                  let receipt = try? JSONDecoder().decode(UpscalingBridgeReceipt.self, from: data),
                  root.lastPathComponent == receipt.version,
                  Self.isSafeVersion(receipt.version),
                  receipt.bridge == bridge,
                  receipt.sha256.count == 64,
                  receipt.sha256.allSatisfy({ $0.isHexDigit }),
                  receipt.installedFiles.allSatisfy(Self.isSafeRelativePath) else { return nil }
            return UpscalingBridgeReference(
                bridge: bridge,
                version: receipt.version,
                sha256: receipt.sha256,
                installedFiles: receipt.installedFiles
            )
        }.sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }

    func upscalingReference(
        for bridge: TemporalUpscalingBridge,
        version: String? = nil,
        fileManager: FileManager = .default
    ) -> UpscalingBridgeReference? {
        let values = upscalingReferences(for: bridge, fileManager: fileManager)
        if let version { return values.first { $0.version == version } }
        return values.first
    }

    func contains(_ reference: UpscalingBridgeReference, fileManager: FileManager = .default) -> Bool {
        guard reference.bridge != .none, Self.isSafeVersion(reference.version) else { return false }
        let root = upscalingComponentURL(reference.bridge, version: reference.version)
        guard fileManager.fileExists(atPath: root.path),
              let data = try? Data(contentsOf: root.appending(path: "bridge.json")),
              let receipt = try? JSONDecoder().decode(UpscalingBridgeReceipt.self, from: data) else { return false }
        guard receipt.bridge == reference.bridge,
              receipt.version == reference.version,
              receipt.sha256 == reference.sha256,
              receipt.installedFiles.allSatisfy(Self.isSafeRelativePath),
              reference.installedFiles.allSatisfy(Self.isSafeRelativePath) else { return false }
        let installedFiles = Set(receipt.installedFiles).union(reference.installedFiles)
        return !installedFiles.isEmpty && installedFiles.allSatisfy {
            fileManager.fileExists(atPath: root.appending(path: $0).path)
        }
    }
}

nonisolated extension TemporalUpscalingBridge {
    var directoryName: String {
        switch self {
        case .none: "Disabled"
        case .ngxToMetalFX: "MetalFXBridge"
        }
    }
}
