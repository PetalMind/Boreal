import Foundation

actor PerformanceSessionRecorder {
    private struct ActiveSession {
        let id: UUID
        let game: OverlayGame
        let startedAt: Date
        var samples: [GamePerformanceSample]
    }

    private var active: ActiveSession?
    private(set) var lastDocument: PerformanceSessionDocument?
    private let directoryURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directoryURL = base.appending(path: "Boreal/Performance Sessions", directoryHint: .isDirectory)
    }

    func start(for game: OverlayGame) {
        if active?.game.id == game.id, active?.game.launchedAt == game.launchedAt { return }
        if active != nil { _ = finish() }
        active = ActiveSession(id: UUID(), game: game, startedAt: .now, samples: [])
    }

    func append(_ snapshot: GamePerformanceSnapshot, for gameID: UUID? = nil, at timestamp: Date = .now) {
        guard let active, gameID == nil || active.game.id == gameID else { return }
        self.active?.samples.append(GamePerformanceSample(timestamp: timestamp, snapshot: snapshot))
        // The controller appends at 10 Hz, while the live sampler remains at
        // 20 Hz. Keep the complete session so percentile statistics and the
        // exported timeline do not silently lose the beginning of a run.
    }

    @discardableResult
    func finish(at end: Date = .now) -> PerformanceSessionDocument? {
        guard let active else { return nil }
        let document = PerformanceSessionDocument(
            id: active.id,
            gameID: active.game.id,
            gameName: active.game.name,
            graphics: OverlayGraphicsDescriptor(
                gameAPI: active.game.gameAPI,
                translator: active.game.translator,
                hostAPI: active.game.hostAPI,
                runtime: active.game.runtime
            ),
            startedAt: active.startedAt,
            endedAt: end,
            samples: active.samples,
            summary: Self.summary(samples: active.samples, startedAt: active.startedAt, endedAt: end)
        )
        self.active = nil
        lastDocument = document
        persist(document)
        return document
    }

    func latest() -> PerformanceSessionDocument? {
        if let lastDocument { return lastDocument }
        let value = loadPersistedSessions().first
        lastDocument = value
        return value
    }

    func loadPersistedSessions() -> [PerformanceSessionDocument] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder.boreal.decode(PerformanceSessionDocument.self, from: data)
        }.sorted { $0.startedAt > $1.startedAt }
    }

    func exportJSON(_ document: PerformanceSessionDocument, to url: URL) throws {
        let data = try JSONEncoder.boreal.encode(document)
        try data.write(to: url, options: .atomic)
    }

    func exportCSV(_ document: PerformanceSessionDocument, to url: URL) throws {
        try csv(for: document).data(using: .utf8)?.write(to: url, options: .atomic)
    }

    func compare(_ first: PerformanceSessionDocument, _ second: PerformanceSessionDocument) -> PerformanceSessionComparison {
        PerformanceSessionComparison(first: first.summary, second: second.summary)
    }

    func benchmarkBaseline(for document: PerformanceSessionDocument) -> RendererBenchmarkBaseline {
        RendererBenchmarkBaseline(
            sessionID: document.id,
            gameName: document.gameName,
            graphics: document.graphics,
            createdAt: document.endedAt,
            summary: document.summary
        )
    }

    private func persist(_ document: PerformanceSessionDocument) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let fileName = document.startedAt.ISO8601Format() + "." + document.id.uuidString + ".json"
            let url = directoryURL.appending(path: fileName)
            try exportJSON(document, to: url)
            UserDefaults.standard.set(url.path, forKey: "gameOverlayLastPerformanceSession")
        } catch {
            // Recording must never interfere with the running game or overlay.
        }
    }

    private func csv(for document: PerformanceSessionDocument) -> String {
        var lines = [
            "timestamp,elapsed_seconds,fps,average_fps,frame_time_ms,frame_time_measured,game_cpu_percent,game_memory_bytes,system_cpu_percent,system_gpu_percent,system_memory_bytes,swap_bytes,thermal_state",
        ]
        lines += document.samples.map { sample in
            let s = sample.snapshot
            let elapsed = sample.timestamp.timeIntervalSince(document.startedAt)
            return [
                ISO8601DateFormatter().string(from: sample.timestamp), String(format: "%.3f", elapsed),
                csv(s.framesPerSecond), csv(s.averageFramesPerSecond), csv(s.frameTimeMilliseconds),
                s.frameTimeIsMeasured ? "true" : "false", csv(s.gameCPUUsage), csv(s.gameMemoryUsedBytes),
                csv(s.systemCPUUsage), csv(s.systemGPUUsage), csv(s.systemMemoryUsedBytes), csv(s.swapUsedBytes),
                csv(s.thermalState),
            ].joined(separator: ",")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func csv<T>(_ value: T?) -> String {
        guard let value else { return "" }
        let text = String(describing: value)
        return text.contains(",") ? "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\"" : text
    }

    private static func summary(samples: [GamePerformanceSample], startedAt: Date, endedAt: Date) -> PerformanceSessionSummary {
        let snapshots = samples.map(\.snapshot)
        let averageFPS = snapshots.compactMap(\.averageFramesPerSecond).last
            ?? average(snapshots.compactMap(\.framesPerSecond))
        let onePercent = snapshots.compactMap(\.onePercentLowFPS).last
        let zeroPointOne = snapshots.compactMap(\.zeroPointOnePercentLowFPS).last
        let p95 = snapshots.compactMap(\.p95FrameTimeMilliseconds).last
        let p99 = snapshots.compactMap(\.p99FrameTimeMilliseconds).last
        let peakMemory = snapshots.compactMap(\.gameMemoryUsedBytes).max()
        var seriousDuration = 0.0
        for pair in zip(samples, samples.dropFirst()) {
            let state = pair.0.snapshot.thermalState
            if state == "Serious" || state == "Critical" {
                seriousDuration += max(0, pair.1.timestamp.timeIntervalSince(pair.0.timestamp))
            }
        }
        return PerformanceSessionSummary(
            durationSeconds: max(0, endedAt.timeIntervalSince(startedAt)), averageFPS: averageFPS,
            onePercentLowFPS: onePercent, zeroPointOnePercentLowFPS: zeroPointOne,
            p95FrameTimeMilliseconds: p95, p99FrameTimeMilliseconds: p99,
            peakMemoryBytes: peakMemory, seriousThermalDurationSeconds: seriousDuration,
            frameCount: snapshots.last?.frameCount ?? 0, sampleCount: samples.count
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private extension JSONEncoder {
    static var boreal: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var boreal: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
