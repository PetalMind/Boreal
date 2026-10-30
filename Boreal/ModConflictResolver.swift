import Foundation

nonisolated enum ModConflictResolver {
    static func conflicts(in mods: [InstalledMod]) -> [ModConflict] {
        var owners: [String: [(mod: InstalledMod, file: ModFile)]] = [:]
        for mod in mods where mod.enabled {
            for file in mod.files {
                owners[file.id, default: []].append((mod, file))
            }
        }
        return owners.compactMap { key, values in
            guard values.count > 1,
                let winner = values.max(by: { $0.mod.priority < $1.mod.priority })
            else { return nil }
            let ordered = values.sorted { $0.mod.priority < $1.mod.priority }
            let winningFile = ordered.last?.file
            return ModConflict(
                relativePath: winningFile.map { $0.destinationRoot.displayPath($0.relativePath) } ?? key,
                modIDs: ordered.map { $0.mod.id },
                winnerModID: winner.mod.id,
                kind: conflictKind(for: winningFile?.relativePath ?? key),
                resolutionStrategy: .priorityLast
            )
        }.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func conflictKind(for path: String) -> ModConflictKind {
        let lowercased = path.lowercased()
        if [".asi", ".dll", ".exe"].contains(where: { lowercased.hasSuffix($0) }) {
            return .potentialRuntime
        }
        if [".dat", ".ide", ".ipl", ".cfg"].contains(where: { lowercased.hasSuffix($0) }) {
            return .mergeable
        }
        return .directReplacement
    }
}

nonisolated enum ModProfileFingerprint {
    static func make(
        mods: [InstalledMod],
        plugins: [BethesdaPlugin],
        includeExternallyDetected: Bool = false
    ) -> String {
        let modPart = mods.filter { includeExternallyDetected || !$0.isExternallyDetected }.sorted { $0.priority < $1.priority }.map { mod in
            let files = mod.files.sorted {
                if $0.destinationRoot != $1.destinationRoot {
                    return $0.destinationRoot.rawValue < $1.destinationRoot.rawValue
                }
                return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
            .map {
                let target = $0.destinationRoot == .data ? $0.relativePath : $0.id
                return "\(target)=\($0.sha256)"
            }
            .joined(separator: ";")
            return "\(mod.id.uuidString):\(mod.enabled ? 1 : 0):\(mod.priority):\(files)"
        }.joined(separator: "|")
        let pluginPart = plugins.sorted { $0.loadOrder < $1.loadOrder }.map {
            "\($0.filename.lowercased()):\($0.enabled ? 1 : 0):\($0.loadOrder):\($0.modID?.uuidString ?? "base"):\($0.classification.rawValue):\($0.masters.map { $0.lowercased() }.joined(separator: ","))"
        }.joined(separator: "|")
        return modPart + "##" + pluginPart
    }
}
