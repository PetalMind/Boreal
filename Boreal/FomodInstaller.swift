import Foundation

nonisolated enum FomodPluginType: Equatable, Sendable {
    case required
    case recommended
    case optional
    case couldBeUsable
    case notUsable

    var isUsable: Bool { self != .notUsable }
    var isRequired: Bool { self == .required }

    var displayName: String {
        switch self {
        case .required: "Required"
        case .recommended: "Recommended"
        case .optional: "Optional"
        case .couldBeUsable: "Could be usable"
        case .notUsable: "Not compatible"
        }
    }

    static func parse(_ value: String?) -> FomodPluginType {
        switch value?.lowercased() {
        case "required": .required
        case "recommended": .recommended
        case "couldbeusable": .couldBeUsable
        case "notusable": .notUsable
        default: .optional
        }
    }
}

nonisolated enum FomodGroupType: Equatable, Sendable {
    case selectAll
    case selectAny
    case selectAtLeastOne
    case selectAtMostOne
    case selectExactlyOne

    var minimumSelectionCount: Int {
        switch self {
        case .selectAtLeastOne, .selectExactlyOne: 1
        case .selectAll, .selectAny, .selectAtMostOne: 0
        }
    }

    var maximumSelectionCount: Int? {
        switch self {
        case .selectAtMostOne, .selectExactlyOne: 1
        case .selectAll, .selectAny, .selectAtLeastOne: nil
        }
    }

    static func parse(_ value: String?) -> FomodGroupType {
        switch value?.lowercased() {
        case "selectall": .selectAll
        case "selectatleastone": .selectAtLeastOne
        case "selectatmostone": .selectAtMostOne
        case "selectexactlyone": .selectExactlyOne
        default: .selectAny
        }
    }
}

nonisolated struct FomodSelectionState: Sendable, Equatable {
    var selectedOptionIDs: Set<String> = []

    func contains(_ optionID: String) -> Bool { selectedOptionIDs.contains(optionID) }
}

nonisolated struct FomodFileEntry: Sendable {
    let source: String
    let destination: String?
    let isFolder: Bool
    let priority: Int
    let alwaysInstall: Bool
    let installIfUsable: Bool
}

nonisolated struct FomodFlag: Sendable {
    let name: String
    let value: String
}

nonisolated indirect enum FomodDependency: Sendable {
    case all([FomodDependency])
    case any([FomodDependency])
    case file(path: String, state: String)
    case flag(name: String, value: String)
    case gameVersion(String, operatorName: String)
    case unsupported(String)
}

nonisolated struct FomodTypePattern: Sendable {
    let dependency: FomodDependency
    let type: FomodPluginType
}

nonisolated struct FomodOption: Sendable, Identifiable {
    let id: String
    let name: String
    let description: String
    let type: FomodPluginType
    let typePatterns: [FomodTypePattern]
    let files: [FomodFileEntry]
    let flags: [FomodFlag]
}

nonisolated struct FomodGroup: Sendable, Identifiable {
    let id: String
    let name: String
    let type: FomodGroupType
    let options: [FomodOption]
}

nonisolated struct FomodStep: Sendable, Identifiable {
    let id: String
    let name: String
    let description: String
    let visibility: FomodDependency?
    let groups: [FomodGroup]
}

nonisolated struct FomodResolvedOption: Sendable, Identifiable {
    let option: FomodOption
    let type: FomodPluginType
    let isSelected: Bool

    var id: String { option.id }
}

nonisolated struct FomodResolvedGroup: Sendable, Identifiable {
    let group: FomodGroup
    let options: [FomodResolvedOption]

    var id: String { group.id }
}

nonisolated struct FomodResolvedStep: Sendable, Identifiable {
    let step: FomodStep
    let groups: [FomodResolvedGroup]

    var id: String { step.id }
}

nonisolated struct FomodConditionalFiles: Sendable {
    let dependency: FomodDependency
    let files: [FomodFileEntry]
}

nonisolated struct FomodEnvironment: Sendable {
    let existingFiles: Set<String>
    let activePlugins: Set<String>
    let gameVersion: String?

    func fileState(_ path: String) -> String {
        let normalized = FomodPath.normalized(path).lowercased()
        guard existingFiles.contains(normalized) else { return "Missing" }
        let ext = URL(fileURLWithPath: normalized).pathExtension.lowercased()
        if ["esp", "esm", "esl"].contains(ext) {
            return activePlugins.contains(URL(fileURLWithPath: normalized).lastPathComponent.lowercased()) ? "Active" : "Inactive"
        }
        return "Active"
    }
}

nonisolated struct FomodInstallPlan: Sendable {
    let moduleName: String
    let packageRootRelativePath: String
    let requiredFiles: [FomodFileEntry]
    let moduleDependencies: FomodDependency?
    let steps: [FomodStep]
    let conditionalFiles: [FomodConditionalFiles]
    let environment: FomodEnvironment
    let unsupportedFeatures: [String]

    var moduleDependencyIssues: [String] {
        guard let moduleDependencies, !moduleDependencies.isSatisfied(environment: environment, flags: [:]) else { return [] }
        return moduleDependencies.unsatisfiedDescriptions(environment: environment, flags: [:])
    }

    var supportIssues: [String] {
        Array(Set(unsupportedFeatures)).sorted()
    }

    var isInstallable: Bool { moduleDependencyIssues.isEmpty && supportIssues.isEmpty }

    func presentedSteps(for selection: FomodSelectionState) -> [FomodResolvedStep] {
        var flags: [String: String] = [:]
        var result: [FomodResolvedStep] = []

        for step in steps {
            if let visibility = step.visibility,
                !visibility.isSatisfied(environment: environment, flags: flags)
            {
                continue
            }

            var resolvedGroups: [FomodResolvedGroup] = []
            for group in step.groups {
                let resolvedOptions = group.options.map { option in
                    FomodResolvedOption(
                        option: option,
                        type: option.resolvedType(environment: environment, flags: flags),
                        isSelected: selection.contains(option.id)
                    )
                }
                resolvedGroups.append(FomodResolvedGroup(group: group, options: resolvedOptions))
                for resolved in resolvedOptions where resolved.isSelected && resolved.type.isUsable {
                    for flag in resolved.option.flags { flags[flag.name] = flag.value }
                }
            }
            result.append(FomodResolvedStep(step: step, groups: resolvedGroups))
        }
        return result
    }

    func initialSelection() -> FomodSelectionState {
        var selection = FomodSelectionState()
        var flags: [String: String] = [:]

        for step in steps {
            if let visibility = step.visibility,
                !visibility.isSatisfied(environment: environment, flags: flags)
            {
                continue
            }

            for group in step.groups {
                let options = group.options.map { ($0, $0.resolvedType(environment: environment, flags: flags)) }
                let usable = options.filter { $0.1.isUsable }
                let required = usable.filter { $0.1.isRequired }
                let recommended = usable.filter { $0.1 == .recommended }
                var defaults: [FomodOption]
                switch group.type {
                case .selectAll:
                    defaults = usable.map { $0.0 }
                case .selectExactlyOne:
                    defaults = (required.first ?? recommended.first ?? usable.first).map { [$0.0] } ?? []
                case .selectAtLeastOne:
                    defaults = required.isEmpty ? recommended.map { $0.0 } : required.map { $0.0 }
                    if defaults.isEmpty, let first = usable.first { defaults = [first.0] }
                case .selectAtMostOne:
                    defaults = required.isEmpty ? recommended.prefix(1).map { $0.0 } : required.prefix(1).map { $0.0 }
                case .selectAny:
                    defaults = required.isEmpty ? recommended.map { $0.0 } : required.map { $0.0 }
                }
                selection.selectedOptionIDs.formUnion(defaults.map(\.id))
                for option in defaults {
                    for flag in option.flags { flags[flag.name] = flag.value }
                }
            }
        }
        return selection
    }

    func toggled(optionID: String, in selection: FomodSelectionState) -> FomodSelectionState {
        let visible = presentedSteps(for: selection)
        guard let groupPresentation = visible.flatMap(\.groups).first(where: { $0.options.contains(where: { $0.id == optionID }) }),
            let chosen = groupPresentation.options.first(where: { $0.id == optionID }),
            chosen.type.isUsable,
            !chosen.type.isRequired,
            groupPresentation.group.type != .selectAll
        else { return selection }

        var next = selection
        if chosen.isSelected {
            if groupPresentation.group.type == .selectExactlyOne { return selection }
            let selectedCount = groupPresentation.options.filter(\.isSelected).count
            if groupPresentation.group.type == .selectAtLeastOne && selectedCount <= 1 { return selection }
            next.selectedOptionIDs.remove(optionID)
        } else {
            if groupPresentation.group.type == .selectExactlyOne || groupPresentation.group.type == .selectAtMostOne {
                for option in groupPresentation.options { next.selectedOptionIDs.remove(option.id) }
            }
            next.selectedOptionIDs.insert(optionID)
        }
        return next
    }

    func selectionIssue(for selection: FomodSelectionState) -> String? {
        guard isInstallable else { return nil }
        for resolvedStep in presentedSteps(for: selection) {
            for resolvedGroup in resolvedStep.groups {
                let options = resolvedGroup.options.filter { $0.type.isUsable }
                let selected = options.filter(\.isSelected)
                let required = options.filter { $0.type.isRequired }
                let group = resolvedGroup.group
                if required.contains(where: { !$0.isSelected }) { return "Select all required options in \(group.name)." }
                if selected.count < group.type.minimumSelectionCount { return "Select at least one option in \(group.name)." }
                if let maximum = group.type.maximumSelectionCount, selected.count > maximum {
                    return "Select no more than one option in \(group.name)."
                }
                if group.type == .selectAll && selected.count != options.count { return "All options in \(group.name) must be installed." }
            }
        }
        return nil
    }

    func resolvedFiles(for selection: FomodSelectionState, packageRoot: URL) throws -> [FomodResolvedFile] {
        guard isInstallable else { throw FomodInstallerError.unsupported(supportIssues + moduleDependencyIssues) }
        if let issue = selectionIssue(for: selection) { throw FomodInstallerError.invalidSelection(issue) }

        var chosenEntries = requiredFiles
        let resolvedSteps = presentedSteps(for: selection)
        for group in resolvedSteps.flatMap(\.groups) {
            for resolvedOption in group.options {
                let shouldInstall = resolvedOption.isSelected && resolvedOption.type.isUsable
                for entry in resolvedOption.option.files
                where shouldInstall || entry.alwaysInstall || (entry.installIfUsable && resolvedOption.type.isUsable) {
                    chosenEntries.append(entry)
                }
            }
        }
        let flags = resolvedFlags(from: resolvedSteps)
        for conditional in conditionalFiles where conditional.dependency.isSatisfied(environment: environment, flags: flags) {
            chosenEntries.append(contentsOf: conditional.files)
        }

        var expanded: [FomodResolvedFile] = []
        var order = 0
        for entry in chosenEntries {
            let newFiles = try expand(entry, packageRoot: packageRoot, sequenceStart: order)
            expanded.append(contentsOf: newFiles)
            order += newFiles.count
        }
        var byDestination: [String: FomodResolvedFile] = [:]
        for file in expanded.sorted(by: { $0.priority == $1.priority ? $0.sequence < $1.sequence : $0.priority < $1.priority }) {
            byDestination[file.destination.lowercased()] = file
        }
        return byDestination.values.sorted { $0.destination.localizedStandardCompare($1.destination) == .orderedAscending }
    }

    private func resolvedFlags(from steps: [FomodResolvedStep]) -> [String: String] {
        var flags: [String: String] = [:]
        for step in steps {
            for option in step.groups.flatMap(\.options) where option.isSelected && option.type.isUsable {
                for flag in option.option.flags { flags[flag.name] = flag.value }
            }
        }
        return flags
    }

    private func expand(_ entry: FomodFileEntry, packageRoot: URL, sequenceStart: Int) throws -> [FomodResolvedFile] {
        let source = FomodPath.normalized(entry.source)
        guard FomodPath.isSafe(source), !source.isEmpty else { throw FomodInstallerError.invalidPath(entry.source) }
        let root = packageRoot.standardizedFileURL
        let sourceURL = source.split(separator: "/").reduce(root) { $0.appending(path: String($1)) }.standardizedFileURL
        guard sourceURL.path.hasPrefix(root.path + "/") else { throw FomodInstallerError.invalidPath(entry.source) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw FomodInstallerError.missingSource(entry.source)
        }
        let destination = FomodPath.normalized(entry.destination ?? "")
        guard FomodPath.isSafe(destination) else { throw FomodInstallerError.invalidPath(entry.destination ?? "") }
        let sourceIsFolder = entry.isFolder || isDirectory.boolValue
        if sourceIsFolder {
            guard isDirectory.boolValue,
                let enumerator = FileManager.default.enumerator(
                    at: sourceURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )
            else { throw FomodInstallerError.missingSource(entry.source) }
            var result: [FomodResolvedFile] = []
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw FomodInstallerError.invalidPath(entry.source) }
                guard values.isRegularFile == true else { continue }
                let relative = String(fileURL.standardizedFileURL.path.dropFirst(sourceURL.path.count + 1)).replacingOccurrences(
                    of: "\\", with: "/")
                guard FomodPath.isSafe(relative) else { throw FomodInstallerError.invalidPath(relative) }
                let target = FomodPath.join(destination, relative)
                result.append(
                    FomodResolvedFile(
                        sourceURL: fileURL, source: FomodPath.join(source, relative), destination: target, priority: entry.priority,
                        sequence: sequenceStart + result.count))
            }
            return result
        }
        let basename = sourceURL.lastPathComponent
        let target = entry.destination == nil ? source : FomodPath.join(destination, basename)
        guard FomodPath.isSafe(target), FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw FomodInstallerError.invalidPath(target)
        }
        return [
            FomodResolvedFile(sourceURL: sourceURL, source: source, destination: target, priority: entry.priority, sequence: sequenceStart)
        ]
    }
}

nonisolated struct FomodResolvedFile: Sendable {
    let sourceURL: URL
    let source: String
    let destination: String
    let priority: Int
    let sequence: Int
}

nonisolated enum FomodInstallerError: LocalizedError, Sendable {
    case invalidXML(String)
    case invalidPath(String)
    case missingSource(String)
    case unsupported([String])
    case invalidSelection(String)

    var errorDescription: String? {
        switch self {
        case .invalidXML(let detail): "Boreal couldn’t read this FOMOD XML: \(detail)"
        case .invalidPath(let path): "The FOMOD installer contains an unsafe path: \(path)"
        case .missingSource(let path): "The FOMOD installer references a file that is not in the archive: \(path)"
        case .unsupported(let issues): "Boreal can’t safely apply this FOMOD: \(issues.joined(separator: "; "))"
        case .invalidSelection(let issue): issue
        }
    }
}

nonisolated enum FomodInstaller {
    static func gameVersion(executableAt url: URL?) -> String? {
        guard let url else { return nil }
        return FomodVersion.readExecutableVersion(at: url)
    }

    static func findConfig(in root: URL) throws -> (config: URL?, script: URL?, packageRoot: URL?) {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return (nil, nil, nil) }

        var configURL: URL?
        var scriptURL: URL?
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                let relative = try? FomodPath.relative(url, from: root)
            else { continue }
            let parts = relative.split(separator: "/").map(String.init)
            guard let fomodIndex = parts.firstIndex(where: { $0.caseInsensitiveCompare("fomod") == .orderedSame }),
                fomodIndex == parts.count - 2
            else { continue }
            if url.lastPathComponent.caseInsensitiveCompare("ModuleConfig.xml") == .orderedSame { configURL = url }
            if url.lastPathComponent.caseInsensitiveCompare("script.cs") == .orderedSame { scriptURL = url }
        }
        let packageRoot =
            configURL.map { $0.deletingLastPathComponent().deletingLastPathComponent() }
            ?? scriptURL.map { $0.deletingLastPathComponent().deletingLastPathComponent() }
        return (configURL, scriptURL, packageRoot)
    }

    static func parse(configURL: URL, packageRoot: URL, extractedRoot: URL, environment: FomodEnvironment) throws -> FomodInstallPlan {
        let delegate = FomodXMLTreeBuilder()
        let parser = XMLParser(contentsOf: configURL)
        parser?.delegate = delegate
        parser?.shouldResolveExternalEntities = false
        guard parser?.parse() == true, let root = delegate.root, root.name == "config" else {
            throw FomodInstallerError.invalidXML(parser?.parserError?.localizedDescription ?? "The config root element is missing.")
        }
        let moduleDependencies = root.child("moduleDependencies").map {
            parseDependencyContainer($0, unsupported: &delegate.unsupportedFeatures)
        }
        let requiredFiles = parseFileEntries(root.child("requiredInstallFiles"), unsupported: &delegate.unsupportedFeatures)
        let steps = parseSteps(root.child("installSteps"), unsupported: &delegate.unsupportedFeatures)
        let conditionalFiles = parseConditionalFiles(root.child("conditionalFileInstalls"), unsupported: &delegate.unsupportedFeatures)
        let packageRootRelativePath =
            packageRoot.standardizedFileURL.path == extractedRoot.standardizedFileURL.path
            ? ""
            : (try FomodPath.relative(packageRoot, from: extractedRoot))
        return FomodInstallPlan(
            moduleName: root.child("moduleName")?.text ?? "Mod Installer",
            packageRootRelativePath: packageRootRelativePath,
            requiredFiles: requiredFiles,
            moduleDependencies: moduleDependencies,
            steps: steps,
            conditionalFiles: conditionalFiles,
            environment: environment,
            unsupportedFeatures: delegate.unsupportedFeatures
        )
    }

    private static func parseSteps(_ node: FomodXMLNode?, unsupported: inout [String]) -> [FomodStep] {
        guard let node else { return [] }
        return ordered(node.children(named: "installStep"), order: node.attribute("order")).enumerated().map { index, step in
            let visibility = step.child("visible")?.child("dependencies").map { parseDependencyContainer($0, unsupported: &unsupported) }
            let groupsNode = step.child("optionalFileGroups")
            let groups = ordered(groupsNode?.children(named: "group") ?? [], order: groupsNode?.attribute("order")).enumerated().map {
                groupIndex, group in
                let type = FomodGroupType.parse(group.attribute("type"))
                let pluginsNode = group.child("plugins")
                let options = ordered(pluginsNode?.children(named: "plugin") ?? [], order: pluginsNode?.attribute("order")).enumerated().map
                { optionIndex, option in
                    parseOption(option, id: "s\(index)g\(groupIndex)o\(optionIndex)", unsupported: &unsupported)
                }
                return FomodGroup(id: "s\(index)g\(groupIndex)", name: group.attribute("name") ?? "Options", type: type, options: options)
            }
            return FomodStep(
                id: "s\(index)",
                name: step.attribute("name") ?? "Step \(index + 1)",
                description: step.attribute("description") ?? "",
                visibility: visibility,
                groups: groups
            )
        }
    }

    private static func parseOption(_ node: FomodXMLNode, id: String, unsupported: inout [String]) -> FomodOption {
        let descriptor = node.child("typeDescriptor")
        var simpleType = FomodPluginType.optional
        var patterns: [FomodTypePattern] = []
        if let type = descriptor?.child("type") {
            simpleType = FomodPluginType.parse(type.attribute("name"))
        } else if let dependencyType = descriptor?.child("dependencyType") {
            if let defaultType = dependencyType.child("defaultType")?.attribute("name") {
                simpleType = FomodPluginType.parse(defaultType)
            }
            patterns =
                dependencyType.child("patterns")?.children(named: "pattern").compactMap { pattern in
                    guard let typeName = pattern.child("type")?.attribute("name") else { return nil }
                    let dependency =
                        pattern.child("dependencies").map { parseDependencyContainer($0, unsupported: &unsupported) } ?? .all([])
                    return FomodTypePattern(dependency: dependency, type: FomodPluginType.parse(typeName))
                } ?? []
        }
        let flags =
            node.child("conditionFlags")?.children(named: "flag").compactMap { flag -> FomodFlag? in
                guard let name = flag.attribute("name"), let value = flag.text else { return nil }
                return FomodFlag(name: name, value: value)
            } ?? []
        return FomodOption(
            id: id,
            name: node.attribute("name") ?? "Option",
            description: node.child("description")?.text ?? "",
            type: simpleType,
            typePatterns: patterns,
            files: parseFileEntries(node.child("files"), unsupported: &unsupported),
            flags: flags
        )
    }

    private static func parseConditionalFiles(_ node: FomodXMLNode?, unsupported: inout [String]) -> [FomodConditionalFiles] {
        node?.child("patterns")?.children(named: "pattern").map { pattern in
            let dependency = pattern.child("dependencies").map { parseDependencyContainer($0, unsupported: &unsupported) } ?? .all([])
            return FomodConditionalFiles(dependency: dependency, files: parseFileEntries(pattern.child("files"), unsupported: &unsupported))
        } ?? []
    }

    private static func parseFileEntries(_ node: FomodXMLNode?, unsupported: inout [String]) -> [FomodFileEntry] {
        guard let node else { return [] }
        var entries: [FomodFileEntry] = []
        for child in node.children where child.name == "file" || child.name == "folder" {
            guard let source = child.attribute("source"), !source.isEmpty else {
                unsupported.append("A FOMOD file entry has no source path.")
                continue
            }
            let destination = child.attribute("destination")
            guard FomodPath.isSafe(source), destination.map(FomodPath.isSafe) ?? true else {
                unsupported.append("Unsafe source or destination path: \(source)")
                continue
            }
            let normalizedSource = FomodPath.normalized(source)
            let normalizedDestination = destination.map(FomodPath.normalized)
            entries.append(
                FomodFileEntry(
                    source: normalizedSource,
                    destination: normalizedDestination,
                    isFolder: child.name == "folder",
                    priority: Int(child.attribute("priority") ?? "0") ?? 0,
                    alwaysInstall: child.attribute("alwaysInstall")?.lowercased() == "true",
                    installIfUsable: child.attribute("installIfUsable")?.lowercased() == "true"
                ))
        }
        return entries
    }

    private static func parseDependencyContainer(_ node: FomodXMLNode, unsupported: inout [String]) -> FomodDependency {
        let children = node.children.compactMap { parseDependency($0, unsupported: &unsupported) }
        if node.attribute("operator")?.caseInsensitiveCompare("Or") == .orderedSame { return .any(children) }
        return .all(children)
    }

    private static func parseDependency(_ node: FomodXMLNode, unsupported: inout [String]) -> FomodDependency? {
        switch node.name {
        case "dependencies": return parseDependencyContainer(node, unsupported: &unsupported)
        case "filedependency":
            guard let path = node.attribute("file") else {
                unsupported.append("A file dependency has no file path.")
                return .unsupported("file dependency without a path")
            }
            return .file(path: FomodPath.normalized(path), state: node.attribute("state") ?? "Active")
        case "flagdependency":
            guard let name = node.attribute("flag"), let value = node.attribute("value") else {
                unsupported.append("A flag dependency is incomplete.")
                return .unsupported("incomplete flag dependency")
            }
            return .flag(name: name, value: value)
        case "gamedependency":
            guard let version = node.attribute("version") else {
                unsupported.append("A game-version dependency has no version.")
                return .unsupported("game version dependency without a version")
            }
            return .gameVersion(version, operatorName: node.attribute("operator") ?? "GreaterThanOrEqual")
        case "fommdependency", "fosedependency", "foseversiondependency", "scriptdependency":
            unsupported.append("The \(node.name) condition is not supported.")
            return .unsupported(node.name)
        default:
            unsupported.append("The \(node.name) condition is not supported.")
            return .unsupported(node.name)
        }
    }

    private static func ordered(_ nodes: [FomodXMLNode], order: String?) -> [FomodXMLNode] {
        switch order?.lowercased() {
        case "descending":
            nodes.sorted { ($0.attribute("name") ?? "").localizedStandardCompare($1.attribute("name") ?? "") == .orderedDescending }
        case "ascending", nil:
            nodes.sorted { ($0.attribute("name") ?? "").localizedStandardCompare($1.attribute("name") ?? "") == .orderedAscending }
        default: nodes
        }
    }
}

private nonisolated extension FomodOption {
    func resolvedType(environment: FomodEnvironment, flags: [String: String]) -> FomodPluginType {
        typePatterns.first(where: { $0.dependency.isSatisfied(environment: environment, flags: flags) })?.type ?? type
    }
}

private nonisolated extension FomodDependency {
    func isSatisfied(environment: FomodEnvironment, flags: [String: String]) -> Bool {
        return switch self {
        case .all(let dependencies): dependencies.allSatisfy { $0.isSatisfied(environment: environment, flags: flags) }
        case .any(let dependencies):
            dependencies.isEmpty || dependencies.contains { $0.isSatisfied(environment: environment, flags: flags) }
        case .file(let path, let state): environment.fileState(path).caseInsensitiveCompare(state) == .orderedSame
        case .flag(let name, let value): flags[name]?.caseInsensitiveCompare(value) == .orderedSame
        case .gameVersion(let expected, let operatorName):
            environment.gameVersion.map { FomodVersion.compare($0, expected, operatorName: operatorName) } ?? false
        case .unsupported: false
        }
    }

    func unsatisfiedDescriptions(environment: FomodEnvironment, flags: [String: String]) -> [String] {
        guard !isSatisfied(environment: environment, flags: flags) else { return [] }
        return switch self {
        case .all(let dependencies): dependencies.flatMap { $0.unsatisfiedDescriptions(environment: environment, flags: flags) }
        case .any: ["One of the installer requirements is not present."]
        case .file(let path, let state): ["Required file \(path) must be \(state.lowercased())."]
        case .flag(let name, let value): ["Installer condition \(name)=\(value) is not satisfied."]
        case .gameVersion(let expected, _): ["This installer requires Skyrim version \(expected)."]
        case .unsupported(let name): ["Unsupported installer condition: \(name)."]
        }
    }
}

private nonisolated enum FomodVersion {
    static func readExecutableVersion(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        for label in ["FileVersion", "ProductVersion"] {
            let key = Data(label.utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })
            guard let keyRange = data.range(of: key) else { continue }
            let limit = min(data.count - 1, keyRange.upperBound + 192)
            var cursor = keyRange.upperBound
            while cursor + 1 < limit {
                var units: [UInt16] = []
                var scan = cursor
                while scan + 1 < limit {
                    let value = UInt16(data[scan]) | (UInt16(data[scan + 1]) << 8)
                    guard (value >= 48 && value <= 57) || value == 46 else { break }
                    units.append(value)
                    scan += 2
                }
                if units.count >= 5,
                    units.filter({ $0 == 46 }).count >= 2
                {
                    return String(decoding: units, as: UTF16.self)
                }
                cursor += 2
            }
        }
        return nil
    }

    static func compare(_ current: String, _ expected: String, operatorName: String) -> Bool {
        let comparison = compareVersions(current, expected)
        return switch operatorName.lowercased() {
        case "equal", "equals", "=", "==": comparison == .orderedSame
        case "notequal", "not equal", "!=": comparison != .orderedSame
        case "lessthan", "<": comparison == .orderedAscending
        case "lessthanorequal", "<=": comparison != .orderedDescending
        case "greaterthan", ">": comparison == .orderedDescending
        case "greaterthanorequal", "greaterthanorequalto", ">=", "": comparison != .orderedAscending
        default: false
        }
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let right = rhs.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

private nonisolated enum FomodPath {
    static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func join(_ lhs: String, _ rhs: String) -> String {
        [normalized(lhs), normalized(rhs)].filter { !$0.isEmpty && $0 != "." }.joined(separator: "/")
    }

    static func isSafe(_ path: String) -> Bool {
        let path = path.replacingOccurrences(of: "\\", with: "/")
        guard !path.contains("\0"), !path.hasPrefix("/") else { return false }
        let normalized = self.normalized(path)
        if normalized.isEmpty || normalized == "." { return true }
        return !normalized.hasPrefix("/")
            && !normalized.split(separator: "/").contains(where: { $0 == ".." || $0.contains(":") })
    }

    static func relative(_ url: URL, from root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { throw FomodInstallerError.invalidPath(path) }
        let result = String(path.dropFirst(rootPath.count + 1))
        guard isSafe(result) else { throw FomodInstallerError.invalidPath(result) }
        return normalized(result)
    }
}

private nonisolated final class FomodXMLNode {
    let name: String
    let attributes: [String: String]
    var children: [FomodXMLNode] = []
    var rawText = ""

    init(name: String, attributes: [String: String]) {
        self.name = name.lowercased()
        self.attributes = Dictionary(uniqueKeysWithValues: attributes.map { ($0.key.lowercased(), $0.value) })
    }

    func attribute(_ name: String) -> String? { attributes[name.lowercased()] }
    func child(_ name: String) -> FomodXMLNode? { children.first { $0.name == name.lowercased() } }
    func children(named name: String) -> [FomodXMLNode] { children.filter { $0.name == name.lowercased() } }
    var text: String? {
        let value = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private nonisolated final class FomodXMLTreeBuilder: NSObject, XMLParserDelegate {
    private(set) var root: FomodXMLNode?
    private var stack: [FomodXMLNode] = []
    var unsupportedFeatures: [String] = []

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = FomodXMLNode(name: qName ?? elementName, attributes: attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.rawText.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let value = String(data: CDATABlock, encoding: .utf8) { stack.last?.rawText.append(value) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }
}
