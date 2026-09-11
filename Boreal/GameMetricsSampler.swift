import Darwin
import Foundation
import IOKit

nonisolated struct FrameMetricsReading: Sendable {
    let framesPerSecond: Double?
    let intervals: [Double]
    let token: String?
    let source: GameMetricSource
    let isMeasured: Bool
}

nonisolated struct HostMetricsReading: Sendable {
    let cpuUsage: Double?
    let gpuUsage: Double?
    let memoryUsedBytes: UInt64?
    let memoryTotalBytes: UInt64?
    let gpuTemperatureCelsius: Double?
    let memoryPressure: MemoryPressureLevel?
    let swapUsedBytes: UInt64?
    let gpuAllocatedBytes: UInt64?
    let thermalState: String?
}

nonisolated struct ProcessMetricsReading: Sendable {
    let cpuUsage: Double?
    let memoryUsedBytes: UInt64?
}

nonisolated protocol GameMetricsProvider: Sendable {
    var capabilities: MetricsCapabilities { get }
}

nonisolated protocol FrameMetricsProviding: GameMetricsProvider {
    var capabilities: MetricsCapabilities { get }
    func configure(logURL: URL?, enabled: Bool) async
    func read() async -> FrameMetricsReading
    func reset() async
}

nonisolated protocol HostMetricsProviding: GameMetricsProvider {
    func read() async -> HostMetricsReading
    func reset() async
}

nonisolated protocol HardwareTelemetryProviding: GameMetricsProvider {
    func read() async -> HostMetricsReading
    func reset() async
}

nonisolated protocol ProcessMetricsProviding: GameMetricsProvider {
    func configure(processIDs: [Int32]) async
    func read() async -> ProcessMetricsReading
    func reset() async
}

actor WineFPSMetricsProvider: FrameMetricsProviding {
    nonisolated let capabilities = MetricsCapabilities(
        fps: .available, frameTime: .available, averageFPS: .available,
        onePercentLow: .available, zeroPointOnePercentLow: .available,
        p95FrameTime: .available, p99FrameTime: .available
    )
    private var logURL: URL?
    private var lastFileSignature: String?
    private var latest: FrameMetricsReading

    init() {
        latest = FrameMetricsReading(framesPerSecond: nil, intervals: [], token: nil, source: .wineDebugLog, isMeasured: false)
    }

    func configure(logURL: URL?, enabled: Bool) {
        let changed = self.logURL != logURL
        self.logURL = enabled ? logURL : nil
        if changed {
            lastFileSignature = nil
            latest = FrameMetricsReading(framesPerSecond: nil, intervals: [], token: nil, source: .wineDebugLog, isMeasured: false)
        }
    }

    func read() -> FrameMetricsReading {
        guard let logURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              modifiedAt.timeIntervalSinceNow > -8,
              let size = attributes[.size] as? NSNumber else {
            return FrameMetricsReading(framesPerSecond: nil, intervals: [], token: nil, source: .wineDebugLog, isMeasured: false)
        }
        let signature = "\(size.int64Value)-\(modifiedAt.timeIntervalSinceReferenceDate)"
        guard signature != lastFileSignature else { return latest }
        lastFileSignature = signature
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return latest }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return latest }
        let tailSize: UInt64 = 4 * 1_024 * 1_024
        try? handle.seek(toOffset: end > tailSize ? end - tailSize : 0)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8),
              let fps = Self.frameRate(inLogText: text), fps > 0 else { return latest }
        latest = FrameMetricsReading(
            framesPerSecond: fps, intervals: [1_000 / fps], token: signature,
            source: .wineDebugLog, isMeasured: false
        )
        return latest
    }

    func reset() {
        logURL = nil
        lastFileSignature = nil
        latest = FrameMetricsReading(framesPerSecond: nil, intervals: [], token: nil, source: .wineDebugLog, isMeasured: false)
    }

    nonisolated static func frameRate(inLogText text: String) -> Double? {
        let pattern = #"(?:approx\s+)?([0-9]+(?:\.[0-9]+)?)\s*(?:frames\s+per\s+second|fps)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Double(text[valueRange]),
              (0..<1_000).contains(value) else { return nil }
        return value
    }
}

actor MetalHUDMetricsProvider: FrameMetricsProviding {
    nonisolated let capabilities = MetricsCapabilities(
        fps: .available, frameTime: .available, averageFPS: .available,
        onePercentLow: .available, zeroPointOnePercentLow: .available,
        p95FrameTime: .available, p99FrameTime: .available
    )
    private var process: Process?
    private var outputPipe: Pipe?
    private var buffer = ""
    private var latest: FrameMetricsReading

    init() {
        latest = FrameMetricsReading(framesPerSecond: nil, intervals: [], token: nil, source: .metalHUD, isMeasured: true)
    }

    func configure(logURL: URL?, enabled: Bool) {
        if enabled { startReader() } else { stopReader() }
    }

    func read() -> FrameMetricsReading {
        guard let token = latest.token,
              let tokenDate = Double(token),
              Date().timeIntervalSince1970 - tokenDate < 3 else {
            return FrameMetricsReading(framesPerSecond: nil, intervals: [], token: nil, source: .metalHUD, isMeasured: true)
        }
        return latest
    }

    func reset() { stopReader() }

    private func startReader() {
        guard process == nil else { return }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "compact", "--info", "--predicate", "subsystem == \"com.apple.metal.hud\""]
        process.standardOutput = output
        process.standardError = Pipe()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.consume(data) }
        }
        process.terminationHandler = { [weak self, output] _ in
            output.fileHandleForReading.readabilityHandler = nil
            Task { await self?.terminated() }
        }
        do { try process.run() } catch { output.fileHandleForReading.readabilityHandler = nil; return }
        self.process = process
        outputPipe = output
    }

    private func consume(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer.append(chunk)
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        buffer = String(lines.last ?? "")
        for line in lines.dropLast() {
            if let reading = Self.reading(in: String(line)) { latest = reading }
        }
        if buffer.count > 16_384 { buffer = String(buffer.suffix(16_384)) }
    }

    private func terminated() { process = nil; outputPipe = nil }

    private func stopReader() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        outputPipe = nil
        buffer.removeAll(keepingCapacity: true)
        latest = FrameMetricsReading(framesPerSecond: nil, intervals: [], token: nil, source: .metalHUD, isMeasured: true)
    }

    nonisolated static func reading(in line: String) -> FrameMetricsReading? {
        guard let marker = line.range(of: "metal-HUD:") else { return nil }
        let fields = line[marker.upperBound...].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard fields.count >= 5 else { return nil }
        let intervals = stride(from: 3, to: fields.count, by: 2).map { fields[$0] }.filter { (0..<1_000).contains($0) }
        guard !intervals.isEmpty else { return nil }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return nil }
        return FrameMetricsReading(
            framesPerSecond: 1_000 / average, intervals: intervals,
            token: String(Date().timeIntervalSince1970), source: .metalHUD, isMeasured: true
        )
    }
}

actor HostMetricsProvider: HostMetricsProviding, HardwareTelemetryProviding {
    nonisolated let capabilities = MetricsCapabilities(
        systemCPU: .available, systemGPU: .available, systemMemory: .available,
        swap: .available, gpuMappedMemory: .available, gpuTemperature: .available,
        cpuTemperature: .unsupported, memoryPressure: .available, thermalState: .available
    )
    private struct CPUTicks { let total: UInt64; let idle: UInt64 }
    private var previousTicks: CPUTicks?
    private var cachedCPU: Double?
    private var cachedGPU: Double?
    private var cachedMemory: (used: UInt64, total: UInt64)?
    private var cachedTemperature: Double?
    private var cachedPressure: MemoryPressureLevel?
    private var cachedSwap: UInt64?
    private var cachedAllocated: UInt64?
    private var cachedThermal: String?
    private var lastFastReadAt = Date.distantPast
    private var lastSlowReadAt = Date.distantPast

    func read() -> HostMetricsReading {
        let now = Date.now
        if now.timeIntervalSince(lastFastReadAt) >= 0.5 {
            let current = cpuTicks()
            if let previousTicks, let current {
                let total = current.total &- previousTicks.total
                let idle = current.idle &- previousTicks.idle
                cachedCPU = total > 0 ? Double(total - min(idle, total)) / Double(total) * 100 : nil
            } else { cachedCPU = nil }
            previousTicks = current
            cachedGPU = gpuStatistics().utilization
            lastFastReadAt = now
        }
        if now.timeIntervalSince(lastSlowReadAt) >= 1.0 {
            let gpu = gpuStatistics()
            cachedMemory = memoryUsage()
            cachedTemperature = gpu.temperature
            cachedPressure = memoryPressure()
            cachedSwap = swapUsage()
            cachedAllocated = gpu.allocated
            cachedThermal = Self.thermalState
            lastSlowReadAt = now
        }
        return HostMetricsReading(
            cpuUsage: cachedCPU, gpuUsage: cachedGPU,
            memoryUsedBytes: cachedMemory?.used, memoryTotalBytes: cachedMemory?.total,
            gpuTemperatureCelsius: cachedTemperature, memoryPressure: cachedPressure,
            swapUsedBytes: cachedSwap, gpuAllocatedBytes: cachedAllocated,
            thermalState: cachedThermal
        )
    }

    func reset() {
        previousTicks = nil
        cachedCPU = nil; cachedGPU = nil; cachedMemory = nil; cachedTemperature = nil
        cachedPressure = nil; cachedSwap = nil; cachedAllocated = nil; cachedThermal = nil
        lastFastReadAt = .distantPast; lastSlowReadAt = .distantPast
    }

    private static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Normal"
        case .fair: "Elevated"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    private func cpuTicks() -> CPUTicks? {
        var info: processor_info_array_t?
        var cpuCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        var total: UInt64 = 0
        var idle: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            let idleTicks = UInt64(info[base + Int(CPU_STATE_IDLE)])
            total += user + system + nice + idleTicks
            idle += idleTicks
        }
        return CPUTicks(total: total, idle: idle)
    }

    private func memoryUsage() -> (used: UInt64, total: UInt64)? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(statistics.active_count) + UInt64(statistics.inactive_count) + UInt64(statistics.wire_count) + UInt64(statistics.compressor_page_count)
        let reclaimable = UInt64(statistics.external_page_count) + UInt64(statistics.purgeable_count)
        let used = (usedPages - min(usedPages, reclaimable)) * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        return (min(used, total), total)
    }

    private func memoryPressure() -> MemoryPressureLevel? {
        var value: UInt32 = 0
        var size = MemoryLayout.size(ofValue: value)
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return nil }
        switch value {
        case UInt32(DispatchSource.MemoryPressureEvent.normal.rawValue): return .normal
        case UInt32(DispatchSource.MemoryPressureEvent.warning.rawValue): return .warning
        case UInt32(DispatchSource.MemoryPressureEvent.critical.rawValue): return .critical
        default: return nil
        }
    }

    private func swapUsage() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout.size(ofValue: usage)
        return sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 ? usage.xsu_used : nil
    }

    private func gpuStatistics() -> (utilization: Double?, temperature: Double?, allocated: UInt64?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return (nil, nil, nil) }
        defer { IOObjectRelease(iterator) }
        var utilization: Double?
        var temperature: Double?
        var allocated: UInt64?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                let statistics = dictionary["PerformanceStatistics"] as? [String: Any] ?? dictionary
                if let bytes = statistics["Alloc system memory"] as? NSNumber { allocated = (allocated ?? 0) + bytes.uint64Value }
                utilization = utilization ?? numericValue(in: statistics, matching: ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"])
                temperature = temperature ?? numericValue(in: statistics, matching: ["Temperature(C)", "GPU Temperature", "Temperature"])
            }
            service = IOIteratorNext(iterator)
        }
        return (utilization.map { min(max($0, 0), 100) }, normalizedTemperature(temperature), allocated)
    }

    private func numericValue(in dictionary: [String: Any], matching keys: [String]) -> Double? {
        for key in keys { if let number = dictionary[key] as? NSNumber { return number.doubleValue } }
        return nil
    }

    private func normalizedTemperature(_ value: Double?) -> Double? {
        guard let value else { return nil }
        if value > 1_000 { return value / 65_536 }
        if value > 200 { return value / 10 }
        return (0...150).contains(value) ? value : nil
    }
}

actor ProcessMetricsProvider: ProcessMetricsProviding {
    nonisolated let capabilities = MetricsCapabilities(gameCPU: .available, gameMemory: .available)
    private var processIDs: [Int32] = []
    private var previous: [Int32: (user: UInt64, system: UInt64)] = [:]
    private var lastReadAt = Date.distantPast
    private var lastWallTime = Date.now
    private var cached = ProcessMetricsReading(cpuUsage: nil, memoryUsedBytes: nil)

    func configure(processIDs: [Int32]) {
        let value = Array(Set(processIDs.filter { $0 > 0 })).sorted()
        if value != self.processIDs { previous.removeAll(); lastWallTime = .now }
        self.processIDs = value
    }

    func read() -> ProcessMetricsReading {
        if Date().timeIntervalSince(lastReadAt) < 0.5 { return cached }
        guard !processIDs.isEmpty else { cached = ProcessMetricsReading(cpuUsage: nil, memoryUsedBytes: nil); return cached }
        let now = Date()
        var cpuTicks: UInt64 = 0
        var resident: UInt64 = 0
        var current: [Int32: (user: UInt64, system: UInt64)] = [:]
        for pid in processIDs {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            current[pid] = (info.pti_total_user, info.pti_total_system)
            cpuTicks += info.pti_total_user + info.pti_total_system
            resident += UInt64(info.pti_resident_size)
        }
        let elapsed = max(now.timeIntervalSince(lastWallTime), 0.001)
        let previousTicks = previous.values.reduce(UInt64(0)) { $0 + $1.user + $1.system }
        let cpu = cpuTicks >= previousTicks ? min(100 * Double(ProcessInfo.processInfo.activeProcessorCount), Double(cpuTicks - previousTicks) / 1_000_000_000 / elapsed * 100) : nil
        previous = current
        lastWallTime = now
        lastReadAt = now
        cached = ProcessMetricsReading(cpuUsage: cpu, memoryUsedBytes: resident > 0 ? resident : nil)
        return cached
    }

    func reset() { processIDs.removeAll(); previous.removeAll(); cached = ProcessMetricsReading(cpuUsage: nil, memoryUsedBytes: nil); lastReadAt = .distantPast }
}

actor GameMetricsSampler {
    private let wine = WineFPSMetricsProvider()
    private let metal = MetalHUDMetricsProvider()
    private let host = HostMetricsProvider()
    private let process = ProcessMetricsProvider()
    private var frameHistory: [Double] = []
    private var sampledGameID: UUID?
    private var lastFrameToken: String?
    private var logURL: URL?
    private var metalEnabled = false
    private var processConfigured = false

    func configure(for game: OverlayGame) async {
        let changed = sampledGameID != game.id
        if changed { await resetHistory() }
        sampledGameID = game.id
        logURL = game.performanceLogURL
        metalEnabled = game.graphics.caseInsensitiveCompare("D3DMetal") == .orderedSame || game.translator.caseInsensitiveCompare("D3DMetal") == .orderedSame
        processConfigured = !game.processIDs.isEmpty
        // Keep Wine +fps armed as the fallback when Metal HUD is enabled but
        // the current runtime does not actually emit HUD records.
        await wine.configure(logURL: game.performanceLogURL, enabled: true)
        await metal.configure(logURL: game.performanceLogURL, enabled: metalEnabled)
        await process.configure(processIDs: game.processIDs)
    }

    func sample() async -> GamePerformanceSnapshot {
        guard sampledGameID != nil else { return .unavailable }
        async let hostReading = host.read()
        async let processReading = process.read()
        async let metalReading = metal.read()
        async let wineReading = wine.read()
        let host = await hostReading
        let process = await processReading
        let metal = await metalReading
        let wine = await wineReading
        let frame = metal.framesPerSecond != nil ? metal : wine
        if let token = frame.token, token != lastFrameToken {
            frameHistory.append(contentsOf: frame.intervals.filter { $0 > 0 && $0.isFinite })
            frameHistory = Array(frameHistory.suffix(10_000))
            lastFrameToken = token
        }
        let capabilities = makeCapabilities(frame: frame, host: host, process: process)
        return GamePerformanceSnapshot(
            framesPerSecond: frame.framesPerSecond,
            averageFramesPerSecond: averageFPS,
            gameCPUUsage: process.cpuUsage,
            gameMemoryUsedBytes: process.memoryUsedBytes,
            systemCPUUsage: host.cpuUsage,
            systemGPUUsage: host.gpuUsage,
            systemMemoryUsedBytes: host.memoryUsedBytes,
            systemMemoryTotalBytes: host.memoryTotalBytes,
            cpuTemperatureCelsius: nil,
            gpuTemperatureCelsius: host.gpuTemperatureCelsius,
            frameTimeMilliseconds: frameHistory.last ?? frame.intervals.first,
            frameTimeIsMeasured: frame.isMeasured,
            onePercentLowFPS: lowPercent(0.01),
            zeroPointOnePercentLowFPS: lowPercent(0.001),
            p95FrameTimeMilliseconds: quantile(0.95),
            p99FrameTimeMilliseconds: quantile(0.99),
            thermalState: host.thermalState,
            memoryPressure: host.memoryPressure,
            swapUsedBytes: host.swapUsedBytes,
            gpuAllocatedBytes: host.gpuAllocatedBytes,
            fpsSource: frame.framesPerSecond == nil ? nil : frame.source,
            frameCount: frameHistory.count,
            capabilities: capabilities
        )
    }

    func reset() async {
        await resetHistory()
        sampledGameID = nil
        logURL = nil
        processConfigured = false
        await wine.reset(); await metal.reset(); await host.reset(); await process.reset()
    }

    private func resetHistory() async {
        frameHistory.removeAll(keepingCapacity: true)
        lastFrameToken = nil
        await host.reset(); await process.reset()
    }

    private var averageFPS: Double? {
        guard !frameHistory.isEmpty else { return nil }
        let total = frameHistory.reduce(0, +)
        return total > 0 ? 1_000 * Double(frameHistory.count) / total : nil
    }

    private func lowPercent(_ fraction: Double) -> Double? {
        guard frameHistory.count >= 20 else { return nil }
        let slowest = frameHistory.sorted(by: >).prefix(max(1, Int(ceil(Double(frameHistory.count) * fraction))))
        let total = slowest.reduce(0, +)
        return total > 0 ? 1_000 * Double(slowest.count) / total : nil
    }

    private func quantile(_ fraction: Double) -> Double? {
        guard frameHistory.count >= 20 else { return nil }
        let sorted = frameHistory.sorted()
        let index = min(sorted.count - 1, max(0, Int(ceil(fraction * Double(sorted.count))) - 1))
        return sorted[index]
    }

    private func makeCapabilities(frame: FrameMetricsReading, host: HostMetricsReading, process: ProcessMetricsReading) -> MetricsCapabilities {
        let hasFrameSource = metalEnabled || logURL != nil
        return MetricsCapabilities(
            fps: frame.framesPerSecond == nil ? (hasFrameSource ? .warmingUp : .unsupported) : .available,
            frameTime: frame.intervals.isEmpty ? (hasFrameSource ? .warmingUp : .unsupported) : .available,
            averageFPS: averageFPS == nil ? .warmingUp : .available,
            onePercentLow: lowPercent(0.01) == nil ? .warmingUp : .available,
            zeroPointOnePercentLow: lowPercent(0.001) == nil ? .warmingUp : .available,
            p95FrameTime: quantile(0.95) == nil ? .warmingUp : .available,
            p99FrameTime: quantile(0.99) == nil ? .warmingUp : .available,
            gameCPU: process.cpuUsage == nil ? (processConfigured ? .warmingUp : .unsupported) : .available,
            gameMemory: process.memoryUsedBytes == nil ? (processConfigured ? .warmingUp : .unsupported) : .available,
            systemCPU: host.cpuUsage == nil ? .warmingUp : .available,
            systemGPU: host.gpuUsage == nil ? .unavailable : .available,
            systemMemory: host.memoryUsedBytes == nil ? .unavailable : .available,
            swap: host.swapUsedBytes == nil ? .unavailable : .available,
            gpuMappedMemory: host.gpuAllocatedBytes == nil ? .unavailable : .available,
            gpuTemperature: host.gpuTemperatureCelsius == nil ? .unavailable : .available,
            cpuTemperature: .unsupported,
            memoryPressure: host.memoryPressure == nil ? .unavailable : .available,
            thermalState: host.thermalState == nil ? .unavailable : .available
        )
    }

    // Kept for existing parser callers and lightweight compatibility tests.
    nonisolated static func frameRate(inLogText text: String) -> Double? {
        WineFPSMetricsProvider.frameRate(inLogText: text) ?? MetalHUDMetricsProvider.reading(in: text)?.framesPerSecond
    }

    // Compatibility entry point for integrations that still supply the old
    // three arguments. The controller uses configure/sample for live sessions.
    func sample(frameRateLogURL: URL? = nil, gameID: UUID? = nil, metalHUDEnabled: Bool = false) async -> GamePerformanceSnapshot {
        let game = OverlayGame(id: gameID ?? UUID(), name: "Game", launchedAt: .now, performanceLogURL: frameRateLogURL, graphics: metalHUDEnabled ? "D3DMetal" : "WineD3D")
        await configure(for: game)
        return await sample()
    }
}

/// Public architectural names used by future renderer-native providers and
/// the overlay documentation. The current sampler is the concrete monitor and
/// aggregator, while the provider protocols keep those responsibilities split.
typealias GamePerformanceMonitor = GameMetricsSampler
typealias MetricsAggregator = GameMetricsSampler
