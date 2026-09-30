import CryptoKit
import Foundation
import SwiftUI

nonisolated enum Witcher3D3DMetalFixManager {
    static let proxySHA256 = "46862167d7471bd41deee3edb11665b3dcecc86f20fe4ddcd666764cefe1827a"

    enum Status: Equatable, Sendable {
        case available
        case installed
        case gameUpdated
        case recoveryRequired(String)
    }

    private enum AliasOwnership: String, Codable, Sendable {
        case borealSymbolicLink
        case borealDirectoryCopy
        case preexisting
    }

    private struct Receipt: Codable, Sendable {
        var formatVersion = 1
        var gameRootPath: String
        var originalDLLSHA256: String
        var aliasOwnership: AliasOwnership
    }

    private struct Layout {
        let root: URL
        let bin: URL
        let directX12: URL
        let alias: URL
        let targetDLL: URL
        let originalDLL: URL
        let receipt: URL
        let legacyReceipt: URL

        init(gameRoot: URL) {
            root = gameRoot.standardizedFileURL
            bin = root.appending(path: "bin", directoryHint: .isDirectory)
            directX12 = bin.appending(path: "x64_dx12", directoryHint: .isDirectory)
            alias = bin.appending(path: "x64", directoryHint: .isDirectory)
            targetDLL = directX12.appending(path: "amd_fidelityfx_loader_dx12.dll")
            originalDLL = directX12.appending(path: "amd_fidelityfx_loader_dx12_orig.dll")
            receipt = bin.appending(path: ".boreal-witcher3-d3dmetal-fix.json")
            legacyReceipt = bin.appending(path: ".boreal-witcher3-crossover-fix.json")
        }
    }

    enum Failure: LocalizedError, Sendable {
        case unsupportedInstallation
        case missingDirectX12Executable
        case missingOriginalLoader
        case invalidBundledProxy
        case missingOriginalBackup
        case unknownOriginalBackup
        case damagedOriginalBackup
        case malformedReceipt
        case fixNotInstalled
        case symbolicLinkConflict
        case restoreIncomplete

        var errorDescription: String? {
            switch self {
            case .unsupportedInstallation:
                "This repair requires the Witcher 3 DirectX 12 game files managed by Boreal."
            case .missingDirectX12Executable:
                "The Witcher 3 DirectX 12 executable was not found in bin/x64_dx12."
            case .missingOriginalLoader:
                "The game's FidelityFX loader is missing. Reinstall or verify the Witcher 3 game files first."
            case .invalidBundledProxy:
                "The bundled D3DMetal repair failed its integrity check. No game files were changed."
            case .missingOriginalBackup:
                "The original FidelityFX loader backup is missing, so Boreal cannot safely restore it."
            case .unknownOriginalBackup:
                "A different amd_fidelityfx_loader_dx12_orig.dll already exists and is not managed by Boreal. It was left untouched."
            case .damagedOriginalBackup:
                "The saved original loader has changed. Boreal left the game files untouched."
            case .malformedReceipt:
                "Boreal's repair record is unreadable or belongs to a different game folder. No files were changed."
            case .fixNotInstalled:
                "Boreal could not find an installed repair to restore."
            case .symbolicLinkConflict:
                "A game DLL path is a symbolic link. Boreal left it untouched to avoid changing a file outside the game folder."
            case .restoreIncomplete:
                "The original DLL is restored, but Boreal could not remove an older alias it created. The repair record was kept so cleanup can be retried."
            }
        }
    }

    static func bundledProxyURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "amd_fidelityfx_loader_dx12", withExtension: "dll")
    }

    static func supports(gameRoot: URL, fileManager: FileManager = .default) -> Bool {
        let executable = gameRoot.appending(path: "bin/x64_dx12/witcher3.exe")
        return fileManager.isReadableFile(atPath: executable.path)
    }

    static func status(in gameRoot: URL, fileManager: FileManager = .default) -> Status {
        guard supports(gameRoot: gameRoot, fileManager: fileManager) else {
            return .recoveryRequired("Boreal needs the Witcher 3 DirectX 12 executable in bin/x64_dx12.")
        }
        let layout = Layout(gameRoot: gameRoot)
        guard !isSymbolicLink(at: layout.targetDLL.path, fileManager: fileManager),
              !isSymbolicLink(at: layout.originalDLL.path, fileManager: fileManager) else {
            return .recoveryRequired(Failure.symbolicLinkConflict.errorDescription ?? "A game DLL path is a symbolic link.")
        }
        guard fileManager.isReadableFile(atPath: layout.targetDLL.path) else {
            return .recoveryRequired("This game build does not contain amd_fidelityfx_loader_dx12.dll.")
        }
        guard let currentHash = sha256(of: layout.targetDLL) else {
            return .recoveryRequired("Boreal could not read the current game files or its repair record.")
        }
        let receipt: Receipt?
        do {
            receipt = try readReceipt(in: layout, fileManager: fileManager)
        } catch {
            return .recoveryRequired("Boreal could not read the current game files or its repair record.")
        }
        if currentHash == proxySHA256 {
            guard fileManager.isReadableFile(atPath: layout.originalDLL.path),
                  let originalHash = sha256(of: layout.originalDLL),
                  originalHash != proxySHA256 else {
                return .recoveryRequired("The repair proxy is present, but a usable original DLL backup is missing.")
            }
            if let receipt, receipt.originalDLLSHA256 != originalHash {
                return .recoveryRequired("The original DLL backup changed after the repair was installed.")
            }
            return .installed
        }
        if let receipt {
            if fileManager.fileExists(atPath: layout.originalDLL.path) {
                guard let originalHash = sha256(of: layout.originalDLL),
                      originalHash == receipt.originalDLLSHA256 else {
                    return .recoveryRequired("The saved original DLL changed after the repair was installed.")
                }
            }
            return .gameUpdated
        }
        if fileManager.fileExists(atPath: layout.originalDLL.path) {
            return .recoveryRequired("An original DLL backup already exists without a Boreal repair record. Boreal will not overwrite it.")
        }
        return .available
    }

    @discardableResult
    static func apply(
        to gameRoot: URL,
        proxyURL: URL,
        fileManager: FileManager = .default
    ) throws -> String {
        guard supports(gameRoot: gameRoot, fileManager: fileManager) else { throw Failure.unsupportedInstallation }
        let layout = Layout(gameRoot: gameRoot)
        guard !isSymbolicLink(at: layout.targetDLL.path, fileManager: fileManager),
              !isSymbolicLink(at: layout.originalDLL.path, fileManager: fileManager) else {
            throw Failure.symbolicLinkConflict
        }
        guard fileManager.isReadableFile(atPath: layout.directX12.appending(path: "witcher3.exe").path) else {
            throw Failure.missingDirectX12Executable
        }
        guard fileManager.isReadableFile(atPath: layout.targetDLL.path) else { throw Failure.missingOriginalLoader }

        let proxyData = try Data(contentsOf: proxyURL)
        guard sha256(of: proxyData) == proxySHA256 else { throw Failure.invalidBundledProxy }
        let currentData = try Data(contentsOf: layout.targetDLL)
        let currentHash = sha256(of: currentData)
        let priorReceiptData = try optionalData(at: layout.receipt, fileManager: fileManager)
        let legacyReceiptData = try optionalData(at: layout.legacyReceipt, fileManager: fileManager)
        let priorReceipt = try decodeReceipt(priorReceiptData ?? legacyReceiptData, for: layout.root)
        let priorBackupData = try optionalData(at: layout.originalDLL, fileManager: fileManager)

        let isAlreadyPatched = currentHash == proxySHA256
        let originalHash: String
        if isAlreadyPatched {
            guard let priorBackupData else { throw Failure.missingOriginalBackup }
            originalHash = sha256(of: priorBackupData)
            guard originalHash != proxySHA256 else { throw Failure.damagedOriginalBackup }
            if let priorReceipt, priorReceipt.originalDLLSHA256 != originalHash {
                throw Failure.damagedOriginalBackup
            }
        } else {
            originalHash = currentHash
        }

        if !isAlreadyPatched, let priorBackupData {
            guard let priorReceipt,
                  sha256(of: priorBackupData) == priorReceipt.originalDLLSHA256 else {
                throw Failure.unknownOriginalBackup
            }
        }

        let stagedReceipt = Receipt(
            gameRootPath: layout.root.path,
            originalDLLSHA256: originalHash,
            aliasOwnership: priorReceipt?.aliasOwnership ?? .preexisting
        )
        do {
            if !isAlreadyPatched {
                try currentData.write(to: layout.originalDLL, options: .atomic)
                try writeReceipt(stagedReceipt, to: layout.receipt)
                try proxyData.write(to: layout.targetDLL, options: .atomic)
            }
            if let priorReceipt,
               !removeManagedAlias(layout, ownership: priorReceipt.aliasOwnership, fileManager: fileManager) {
                throw Failure.restoreIncomplete
            }
            let finalReceipt = Receipt(
                gameRootPath: layout.root.path,
                originalDLLSHA256: originalHash,
                aliasOwnership: .preexisting
            )
            try writeReceipt(finalReceipt, to: layout.receipt)
            if hasEntry(at: layout.legacyReceipt.path, fileManager: fileManager) {
                try fileManager.removeItem(at: layout.legacyReceipt)
            }
        } catch {
            if !isAlreadyPatched {
                try? currentData.write(to: layout.targetDLL, options: .atomic)
                try? restoreFile(priorBackupData, at: layout.originalDLL, fileManager: fileManager)
            }
            try? restoreFile(priorReceiptData, at: layout.receipt, fileManager: fileManager)
            throw error
        }
        return isAlreadyPatched
            ? "The repair is installed. The original FidelityFX loader is backed up for restoration."
            : "The D3DMetal fix is installed. Restart the game for the startup and display fixes to take effect."
    }

    @discardableResult
    static func restore(in gameRoot: URL, fileManager: FileManager = .default) throws -> String {
        let layout = Layout(gameRoot: gameRoot)
        guard !isSymbolicLink(at: layout.targetDLL.path, fileManager: fileManager),
              !isSymbolicLink(at: layout.originalDLL.path, fileManager: fileManager) else {
            throw Failure.symbolicLinkConflict
        }
        guard let currentHash = sha256(of: layout.targetDLL) else { throw Failure.fixNotInstalled }
        let receiptData = try optionalData(at: layout.receipt, fileManager: fileManager)
        let legacyReceiptData = try optionalData(at: layout.legacyReceipt, fileManager: fileManager)
        let receipt = try decodeReceipt(receiptData ?? legacyReceiptData, for: layout.root)
        let backupData = try optionalData(at: layout.originalDLL, fileManager: fileManager)
        let proxyIsActive = currentHash == proxySHA256

        guard proxyIsActive || receipt != nil else { throw Failure.fixNotInstalled }
        if proxyIsActive {
            guard let backupData else { throw Failure.missingOriginalBackup }
            let backupHash = sha256(of: backupData)
            guard backupHash != proxySHA256,
                  receipt.map({ $0.originalDLLSHA256 == backupHash }) ?? true else {
                throw Failure.damagedOriginalBackup
            }
            try backupData.write(to: layout.targetDLL, options: .atomic)
        } else if let receipt, let backupData,
                  sha256(of: backupData) != receipt.originalDLLSHA256 {
            throw Failure.damagedOriginalBackup
        }

        if let receipt,
           !removeManagedAlias(layout, ownership: receipt.aliasOwnership, fileManager: fileManager) {
            throw Failure.restoreIncomplete
        }
        if backupData != nil { try fileManager.removeItem(at: layout.originalDLL) }
        if receiptData != nil { try fileManager.removeItem(at: layout.receipt) }
        if legacyReceiptData != nil { try fileManager.removeItem(at: layout.legacyReceipt) }
        return proxyIsActive
            ? "The original FidelityFX loader has been restored and the repair files removed."
            : "The current game DLL was kept. Boreal removed its saved repair files."
    }

    private static func pointsToDirectX12(_ destination: String, aliasURL: URL, targetURL: URL) -> Bool {
        if destination == "x64_dx12" { return true }
        let resolved = URL(fileURLWithPath: destination, relativeTo: aliasURL.deletingLastPathComponent())
            .standardizedFileURL
        return resolved.path == targetURL.standardizedFileURL.path
    }

    @discardableResult
    private static func removeManagedAlias(_ layout: Layout, ownership: AliasOwnership, fileManager: FileManager) -> Bool {
        switch ownership {
        case .borealSymbolicLink:
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: layout.alias.path),
                  pointsToDirectX12(destination, aliasURL: layout.alias, targetURL: layout.directX12) else { return true }
            do {
                try fileManager.removeItem(at: layout.alias)
                return true
            } catch {
                return false
            }
        case .borealDirectoryCopy:
            let marker = layout.alias.appending(path: ".ffxproxy-copy")
            guard fileManager.fileExists(atPath: marker.path),
                  (try? fileManager.destinationOfSymbolicLink(atPath: layout.alias.path)) == nil else { return true }
            do {
                try fileManager.removeItem(at: layout.alias)
                return true
            } catch {
                return false
            }
        case .preexisting:
            return true
        }
    }

    private static func readReceipt(in layout: Layout, fileManager: FileManager) throws -> Receipt? {
        let current = try optionalData(at: layout.receipt, fileManager: fileManager)
        let legacy = try optionalData(at: layout.legacyReceipt, fileManager: fileManager)
        return try decodeReceipt(current ?? legacy, for: layout.root)
    }

    private static func decodeReceipt(_ data: Data?, for gameRoot: URL) throws -> Receipt? {
        guard let data else { return nil }
        guard let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              receipt.formatVersion == 1,
              receipt.gameRootPath == gameRoot.standardizedFileURL.path else {
            throw Failure.malformedReceipt
        }
        return receipt
    }

    private static func writeReceipt(_ receipt: Receipt, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipt).write(to: url, options: .atomic)
    }

    private static func optionalData(at url: URL, fileManager: FileManager) throws -> Data? {
        guard hasEntry(at: url.path, fileManager: fileManager) else { return nil }
        return try Data(contentsOf: url)
    }

    private static func restoreFile(_ data: Data?, at url: URL, fileManager: FileManager) throws {
        if let data {
            try data.write(to: url, options: .atomic)
        } else if hasEntry(at: url.path, fileManager: fileManager) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func hasEntry(at path: String, fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: path)
            || (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private static func isSymbolicLink(at path: String, fileManager: FileManager) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return sha256(of: data)
    }

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct Witcher3D3DMetalFixSection: View {
    let gameRoot: URL
    let isD3DMetalEnabled: Bool
    let isModOperationActive: Bool

    @State private var status: Witcher3D3DMetalFixManager.Status = .available
    @State private var isWorking = false
    @State private var operationMessage: String?

    private var canRunOperation: Bool {
        switch status {
        case .available, .installed, .gameUpdated: true
        case .recoveryRequired: false
        }
    }

    private var primaryActionTitle: String {
        status == .installed ? "Restore Original Files" : "Apply D3DMetal Fix"
    }

    private var primaryActionIsRestore: Bool {
        status == .installed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: status == .installed ? "checkmark.shield.fill" : "display")
                    .font(.title3)
                    .foregroundStyle(status == .installed ? .green : .cyan)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Witcher 3 5.00b D3DMetal fix")
                        .font(.headline)
                    Text("Skips one stream output pipeline that can hang D3DMetal's shader converter at startup and marks the game DPI-aware before it reads display modes. Boreal applies this repair to the game's DX12 FidelityFX loader.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !isD3DMetalEnabled {
                        Text("Select a verified Boreal Game Porting Toolkit runtime with D3DMetal to apply this repair.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    statusDescription
                        .font(.caption)
                        .foregroundStyle(status == .installed ? .green : .secondary)
                    Text("Close the game before applying or restoring the fix. Boreal keeps the original game DLL so you can restore it later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }

            if isWorking {
                ProgressView("Updating Witcher 3 files…")
                    .controlSize(.small)
            }

            HStack(spacing: 10) {
                if canRunOperation {
                    Button(primaryActionTitle, systemImage: status == .installed ? "arrow.uturn.backward" : "wrench.and.screwdriver") {
                        run(primaryActionIsRestore ? .restore : .apply)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || isModOperationActive || (!primaryActionIsRestore && !isD3DMetalEnabled))
                }
                if status == .gameUpdated {
                    Button("Remove Stored Fix Files", systemImage: "trash") {
                        run(.restore)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking || isModOperationActive)
                }
                if let operationMessage {
                    Text(operationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .background(.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.cyan.opacity(0.2))
        }
        .task(id: gameRoot.path) {
            await refreshStatus()
        }
    }

    @ViewBuilder
    private var statusDescription: some View {
        switch status {
        case .available:
            Text("DirectX 12 game files found. The original FidelityFX loader will be saved before the repair is installed.")
        case .installed:
            Text("The fix is installed. The original DLL backup is available for restoration.")
        case .gameUpdated:
            Text("The game DLL changed after installation. Reapply after a game update, or remove the stored fix files.")
        case .recoveryRequired(let message):
            Text(message)
        }
    }

    private enum Operation: Sendable {
        case apply
        case restore
    }

    private func run(_ operation: Operation) {
        guard let proxyURL = Witcher3D3DMetalFixManager.bundledProxyURL() else {
            operationMessage = "The bundled repair DLL is missing."
            return
        }
        isWorking = true
        operationMessage = nil
        Task {
            defer { isWorking = false }
            do {
                let message = try await Task.detached(priority: .userInitiated) {
                    switch operation {
                    case .apply:
                        try Witcher3D3DMetalFixManager.apply(to: gameRoot, proxyURL: proxyURL)
                    case .restore:
                        try Witcher3D3DMetalFixManager.restore(in: gameRoot)
                    }
                }.value
                operationMessage = message
            } catch {
                operationMessage = error.localizedDescription
            }
            await refreshStatus()
        }
    }

    @MainActor
    private func refreshStatus() async {
        let nextStatus = await Task.detached(priority: .utility) {
            Witcher3D3DMetalFixManager.status(in: gameRoot)
        }.value
        status = nextStatus
    }
}
