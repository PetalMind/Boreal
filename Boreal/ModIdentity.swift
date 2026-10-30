import Foundation

nonisolated enum ModIdentity {
    static func key(for name: String) -> String {
        let baseName = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let folded = baseName.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let normalized = folded.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }.joined()
        return
            normalized
            .split(separator: "-")
            .joined(separator: "-")
            .lowercased()
    }

    static func existingModID(
        for archiveName: String,
        relativePaths: [String] = [],
        in state: ModGameState
    ) -> UUID? {
        let archiveKey = key(for: archiveName)
        if !archiveKey.isEmpty,
            let namedMatch = state.mods.first(where: { !$0.isExternallyDetected && key(for: $0.name) == archiveKey })
        {
            return namedMatch.id
        }

        // An archive can be renamed between revisions. When the name no
        // longer identifies the installed mod, use an exact payload-path
        // match only if it points to one unambiguous installed mod. This keeps
        // renamed updates from becoming a second copy without guessing when
        // two mods intentionally own the same destination.
        let incomingPaths = Set(relativePaths.map(ExternalModDiscovery.normalizedPath))
        guard !incomingPaths.isEmpty else { return nil }
        let candidates = state.mods.filter { mod in
            guard !mod.isExternallyDetected else { return false }
            return incomingPaths == Set(mod.files.map { ExternalModDiscovery.normalizedPath($0.relativePath) })
        }
        return candidates.count == 1 ? candidates[0].id : nil
    }

    static func externalID(adapter: ModGameAdapter, detectionKey: String) -> UUID {
        let digest = RuntimeSecurity.sha256(data: Data("\(adapter.rawValue):\(detectionKey)".utf8))
        let characters = Array(digest)
        let uuid = [
            String(characters[0..<8]),
            String(characters[8..<12]),
            String(characters[12..<16]),
            String(characters[16..<20]),
            String(characters[20..<32]),
        ].joined(separator: "-")
        return UUID(uuidString: uuid)!
    }
}
