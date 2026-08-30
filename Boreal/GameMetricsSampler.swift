import Darwin
import Foundation
import IOKit

actor GameMetricsSampler {
    private struct CPUTicks {
        let total: UInt64
        let idle: UInt64
    }

    private var previousTicks: CPUTicks?
    private var recentFrameRates: [Double] = []
    private var sampledGameID: UUID?

    func sample(frameRateLogURL: URL? = nil, gameID: UUID? = nil) -> GamePerformanceSnapshot {
        if sampledGameID != gameID {
            sampledGameID = gameID
            recentFrameRates.removeAll(keepingCapacity: true)
        }
        let currentTicks = cpuTicks()
        let cpuUsage: Double?
        if let previousTicks, let currentTicks {
            let total = currentTicks.total - previousTicks.total
            let idle = currentTicks.idle - previousTicks.idle
            cpuUsage = total > 0 ? (Double(total - idle) / Double(total)) * 100 : nil
        } else {
            cpuUsage = nil
        }
        previousTicks = currentTicks

        let memory = memoryUsage()
        let gpu = gpuStatistics()
        let framesPerSecond = frameRate(in: frameRateLogURL)
        if let framesPerSecond {
            recentFrameRates.append(framesPerSecond)
            recentFrameRates = Array(recentFrameRates.suffix(120))
        }
        return GamePerformanceSnapshot(
            framesPerSecond: framesPerSecond,
            cpuUsage: cpuUsage,
            gpuUsage: gpu.utilization,
            memoryUsedBytes: memory?.used,
            memoryTotalBytes: memory?.total,
            cpuTemperatureCelsius: nil,
            gpuTemperatureCelsius: gpu.temperature,
            frameTimeMilliseconds: framesPerSecond.flatMap { $0 > 0 ? 1_000 / $0 : nil },
            onePercentLowFPS: onePercentLow,
            thermalState: thermalState
        )
    }

    private var onePercentLow: Double? {
        guard recentFrameRates.count >= 10 else { return nil }
        let sorted = recentFrameRates.sorted()
        let count = max(1, Int(ceil(Double(sorted.count) * 0.01)))
        return sorted.prefix(count).reduce(0, +) / Double(count)
    }

    private var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Normal"
        case .fair: "Elevated"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    private func frameRate(in logURL: URL?) -> Double? {
        guard let logURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              modifiedAt.timeIntervalSinceNow > -8,
              let handle = try? FileHandle(forReadingFrom: logURL) else {
            return nil
        }

        defer { try? handle.close() }

        guard let end = try? handle.seekToEnd() else {
            return nil
        }

        // Wine may emit thousands of unrelated lines between two +fps records.
        // Keep the read bounded, but large enough to find the latest record in
        // sessions started with the older verbose WINEDEBUG configuration.
        let tailSize: UInt64 = 4 * 1_024 * 1_024
        try? handle.seek(toOffset: end > tailSize ? end - tailSize : 0)

        let data: Data
        do {
            data = try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let pattern = #"(?:approx\s+)?([0-9]+(?:\.[0-9]+)?)\s*(?:frames\s+per\s+second|fps)"#

        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: .caseInsensitive
        ) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)

        guard let match = expression.matches(in: text, range: range).last,
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Double(text[valueRange]),
              (0..<1_000).contains(value) else {
            return nil
        }

        return value
    }

    private func cpuTicks() -> CPUTicks? {
        var info: processor_info_array_t?
        var cpuCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
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
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(statistics.active_count + statistics.inactive_count + statistics.wire_count + statistics.compressor_page_count)
        return (usedPages * pageSize, ProcessInfo.processInfo.physicalMemory)
    }

    private func gpuStatistics() -> (utilization: Double?, temperature: Double?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return (nil, nil)
        }
        defer { IOObjectRelease(iterator) }

        var utilization: Double?
        var temperature: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                let statistics = dictionary["PerformanceStatistics"] as? [String: Any] ?? dictionary
                utilization = utilization ?? numericValue(in: statistics, matching: ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"])
                temperature = temperature ?? numericValue(in: statistics, matching: ["Temperature(C)", "GPU Temperature", "Temperature"])
            }
            service = IOIteratorNext(iterator)
        }
        return (utilization.map { min(max($0, 0), 100) }, normalizedTemperature(temperature))
    }

    private func numericValue(in dictionary: [String: Any], matching keys: [String]) -> Double? {
        for key in keys {
            if let number = dictionary[key] as? NSNumber { return number.doubleValue }
        }
        return nil
    }

    private func normalizedTemperature(_ value: Double?) -> Double? {
        guard let value else { return nil }
        if value > 1_000 { return value / 65_536 }
        if value > 200 { return value / 10 }
        return (0...150).contains(value) ? value : nil
    }
}
