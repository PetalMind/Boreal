import Foundation

enum CompatibilityRating: String, Codable, CaseIterable, Sendable {
    case excellent = "Excellent", good = "Good", limited = "Limited", unknown = "Unknown", unsupported = "Unsupported"

    var symbol: String {
        switch self {
        case .excellent: "checkmark.seal.fill"
        case .good: "checkmark.circle.fill"
        case .limited: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle.fill"
        case .unsupported: "xmark.octagon.fill"
        }
    }
}

enum ApplicationStatus: String, Codable, Sendable {
    case ready = "Ready", running = "Running", installing = "Installing", needsAttention = "Needs Attention"
}

struct WindowsApplication: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var publisher: String
    var executablePath: String
    var installerPath: String
    var environmentID: UUID
    var status: ApplicationStatus = .ready
    var compatibility: CompatibilityRating = .unknown
    var windowsVersion = "Windows 11"
    var graphics = "Automatic"
    var storageBytes: Int64 = 0
    var lastOpened: Date?
    var iconSymbol = "app.dashed"
}

struct WindowsEnvironment: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var windowsVersion = "Windows 11"
    var architecture = "64-bit"
    var runtime = "Boreal Runtime — not installed"
    var graphics = "Automatic"
    var storageBytes: Int64 = 0
    var components: [String] = []
    var createdAt = Date()
    var runtimeID: String?
    var rootPath: String?
    var prefixPath: String?
    var logsPath: String?
}

struct RuntimeDownload: Identifiable, Hashable, Sendable {
    enum State: String, Sendable { case installed = "Installed", available = "Available" }
    let id = UUID()
    var name: String
    var detail: String
    var state: State
    var symbol: String
}

struct InstallCandidate: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    var name: String { url.deletingPathExtension().lastPathComponent }
    var fileType: String { url.pathExtension.uppercased() }
}

enum SidebarDestination: Hashable {
    case library, environments, downloads
    case application(UUID)
}
