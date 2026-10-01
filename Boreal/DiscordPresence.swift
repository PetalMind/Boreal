import Darwin
import Foundation
import Observation

/// Local Rich Presence transport. No user credentials or network requests.
@MainActor
@Observable
final class DiscordPresence {
    static let shared = DiscordPresence()
    static let enabledKey = "discordRichPresenceEnabled"
    static let applicationIDKey = "discordApplicationID"

    private(set) var status = String(localized: "Discord integration is disabled.")
    private var game: OverlayGame?
    private var timer: Timer?
    private var socketFD: Int32 = -1
    private var input = Data()
    private var output = Data()
    private var ready = false
    private var clientID = ""
    private var pendingNonce: String?
    private var deadline = Date.distantFuture
    private var retryAt = Date.distantPast
    private var needsUpdate = true

    private init() {}

    func synchronize(games: [OverlayGame]) {
        // Launcher/installer processes must not be advertised as a game.
        let current = games.first { !$0.processIDs.isEmpty }
        if current?.id != game?.id || current?.launchedAt != game?.launchedAt {
            game = current
            needsUpdate = true
        }
        start()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func settingsChanged() {
        clearAndDisconnect()
        retryAt = .distantPast
        needsUpdate = true
        start()
        tick()
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        clearAndDisconnect()
    }

    private func tick() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else {
            if socketFD >= 0 { clearAndDisconnect() }
            status = String(localized: "Discord integration is disabled.")
            return
        }
        let id = (UserDefaults.standard.string(forKey: Self.applicationIDKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard (17...20).contains(id.count), id.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = UInt64(id), number > 0 else {
            if socketFD >= 0 { clearAndDisconnect() }
            status = String(localized: "Enter a valid Discord Application ID.")
            return
        }
        if clientID != id { clearAndDisconnect(); clientID = id; retryAt = .distantPast }
        if socketFD < 0 {
            guard Date.now >= retryAt else { return }
            guard connectSocket() else {
                status = String(localized: "Waiting for the Discord desktop app…")
                retryAt = .now.addingTimeInterval(15)
                return
            }
            status = String(localized: "Connecting to Discord…")
            deadline = .now.addingTimeInterval(10)
            enqueue(opcode: 0, payload: ["v": 1, "client_id": id])
        }
        flush()
        guard socketFD >= 0 else { return }
        receive()
        guard socketFD >= 0 else { return }
        if Date.now > deadline {
            fail(String(localized: "Discord did not respond. Retrying…"))
            return
        }
        if ready, needsUpdate, pendingNonce == nil {
            needsUpdate = false
            sendActivity(game)
            flush()
        }
    }

    private func connectSocket() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        var directories = ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"].compactMap { environment[$0] }
        directories += [NSTemporaryDirectory(), "/tmp"]
        for directory in Set(directories) {
            for index in 0..<10 {
                let path = URL(fileURLWithPath: directory).appendingPathComponent("discord-ipc-\(index)").path
                guard FileManager.default.fileExists(atPath: path) else { continue }
                var address = sockaddr_un()
                address.sun_family = sa_family_t(AF_UNIX)
                let bytes = Array(path.utf8) + [UInt8(0)]
                guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { continue }
                withUnsafeMutableBytes(of: &address.sun_path) { destination in
                    destination.copyBytes(from: bytes)
                }
                address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
                let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else { continue }
                _ = fcntl(fd, F_SETFL, O_NONBLOCK)
                _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
                var noSignal: Int32 = 1
                _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                let result = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                if result == 0 { socketFD = fd; return true }
                Darwin.close(fd)
            }
        }
        return false
    }

    private func sendActivity(_ game: OverlayGame?) {
        var activity: Any = NSNull()
        if let game {
            var value: [String: Any] = [
                "type": 0, "name": clipped(game.name), "details": clipped(game.name),
                "state": String(localized: "Launched through Boreal"),
                "timestamps": ["start": Int(game.launchedAt.timeIntervalSince1970)],
                "buttons": [["label": "Boreal", "url": "https://github.com/PetalMind/Boreal"]]
            ]
            if let image = game.discordArtworkURL, let url = URL(string: image), url.scheme == "https" {
                value["assets"] = ["large_image": image, "large_text": clipped(game.name)]
            }
            if let page = game.discordStoreURL, let url = URL(string: page), url.scheme == "https" {
                value["buttons"] = [
                    ["label": String(localized: "Game page"), "url": page],
                    ["label": "Boreal", "url": "https://github.com/PetalMind/Boreal"]
                ]
            }
            activity = value
        }
        let nonce = UUID().uuidString
        pendingNonce = nonce
        deadline = .now.addingTimeInterval(10)
        enqueue(opcode: 1, payload: ["cmd": "SET_ACTIVITY", "args": ["pid": getpid(), "activity": activity], "nonce": nonce])
    }

    private func clipped(_ value: String) -> String {
        var result = ""
        for character in value {
            guard result.utf8.count + String(character).utf8.count <= 128 else { break }
            result.append(character)
        }
        return result
    }

    private func enqueue(opcode: UInt32, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        enqueue(opcode: opcode, data: data)
    }

    private func enqueue(opcode: UInt32, data: Data) {
        for word in [opcode, UInt32(data.count)] {
            var little = word.littleEndian
            withUnsafeBytes(of: &little) { output.append(contentsOf: $0) }
        }
        output.append(data)
    }

    private func flush() {
        guard socketFD >= 0, !output.isEmpty else { return }
        let written = output.withUnsafeBytes { Darwin.write(socketFD, $0.baseAddress, $0.count) }
        if written > 0 { output.removeFirst(written) }
        else if written < 0, errno != EAGAIN, errno != EWOULDBLOCK, errno != EINTR {
            fail(String(localized: "Discord disconnected. Retrying…"))
        }
    }

    private func receive() {
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Bound work on the main thread even if the peer sends excessive data.
        for _ in 0..<16 {
            let count = Darwin.read(socketFD, &buffer, buffer.count)
            if count == 0 { fail(String(localized: "Discord disconnected. Retrying…")); return }
            if count < 0 {
                if errno != EAGAIN, errno != EWOULDBLOCK, errno != EINTR {
                    fail(String(localized: "Discord disconnected. Retrying…"))
                }
                break
            }
            input.append(contentsOf: buffer.prefix(count))
        }
        while input.count >= 8 {
            let header = Array(input.prefix(8))
            let opcode = (0..<4).reduce(UInt32(0)) { $0 | UInt32(header[$1]) << ($1 * 8) }
            let length = (0..<4).reduce(UInt32(0)) { $0 | UInt32(header[$1 + 4]) << ($1 * 8) }
            guard length <= 65536 else { fail(String(localized: "Invalid response from Discord.")); return }
            guard input.count >= 8 + Int(length) else { break }
            let body = Data(input.dropFirst(8).prefix(Int(length)))
            input.removeFirst(8 + Int(length))
            if opcode == 3 { enqueue(opcode: 4, data: body); continue }
            if opcode == 2 { fail(String(localized: "Discord rejected the connection. Check Application ID.")); return }
            guard opcode == 1, let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { continue }
            if payload["evt"] as? String == "ERROR" {
                fail(String(localized: "Discord rejected the activity. Check Application ID and Discord settings."))
                return
            }
            if payload["evt"] as? String == "READY" {
                ready = true
                needsUpdate = true
                deadline = .distantFuture
            }
            if let nonce = payload["nonce"] as? String, nonce == pendingNonce {
                pendingNonce = nil
                deadline = .distantFuture
                status = game == nil ? String(localized: "Connected — waiting for a game.") : String(localized: "Game activity shared with Discord.")
            }
        }
        if input.count > 65544 { fail(String(localized: "Invalid response from Discord.")) }
    }

    private func clearAndDisconnect() {
        if ready, socketFD >= 0 {
            output.removeAll()
            sendActivity(nil)
            flush()
        }
        disconnect()
    }

    private func disconnect() {
        if socketFD >= 0 { Darwin.close(socketFD) }
        socketFD = -1
        ready = false
        input.removeAll()
        output.removeAll()
        pendingNonce = nil
        deadline = .distantFuture
        needsUpdate = true
    }

    private func fail(_ message: String) {
        disconnect()
        status = message
        retryAt = .now.addingTimeInterval(15)
    }
}
