import AppKit
import Darwin
import Foundation
import ScreenCaptureKit

struct ResolvedGameWindow: @unchecked Sendable {
    let window: SCWindow
    let windowID: CGWindowID
    let processID: pid_t
    let frame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    let title: String?
    let displayID: CGDirectDisplayID?
}

enum GameWindowResolver {
    static func resolve(gamePID: pid_t, timeout: Duration = .seconds(15)) async throws -> ResolvedGameWindow {
        let deadline = ContinuousClock.now + timeout
        var lastError: Error?

        while ContinuousClock.now < deadline {
            do {
                let window = try await findWindow(gamePID: gamePID)
                if let window { return window }
            } catch {
                lastError = error
                if isPermissionError(error) { throw FrameGenerationError.screenCapturePermissionDenied }
            }

            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(250))
        }

        if let lastError, isPermissionError(lastError) {
            throw FrameGenerationError.screenCapturePermissionDenied
        }
        throw FrameGenerationError.gameWindowNotFound
    }

    private static func findWindow(gamePID: pid_t) async throws -> ResolvedGameWindow? {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        let processIDs = processTree(root: gamePID)
        let candidates = content.windows.compactMap { window -> (SCWindow, pid_t, Int, CGFloat)? in
            guard let owningApplication = window.owningApplication else { return nil }
            let processID = owningApplication.processID
            guard processIDs.contains(processID),
                  window.frame.width >= 64,
                  window.frame.height >= 64 else { return nil }

            let area = max(0, window.frame.width) * max(0, window.frame.height)
            let exactPIDBonus = processID == gamePID ? 10_000_000 : 0
            let activeBonus = window.isActive ? 1_000_000 : 0
            return (window, processID, exactPIDBonus + (window.isOnScreen ? 100_000 : 0), area + CGFloat(activeBonus))
        }

        guard let selected = candidates.max(by: { lhs, rhs in
            let lhsScore = lhs.2 + Int(lhs.3)
            let rhsScore = rhs.2 + Int(rhs.3)
            return lhsScore < rhsScore
        }) else {
            return nil
        }

        let window = selected.0
        let scale = backingScaleFactor(for: window.frame)
        let displayID = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
        return ResolvedGameWindow(
            window: window,
            windowID: window.windowID,
            processID: selected.1,
            frame: window.frame,
            pixelWidth: max(1, Int((window.frame.width * scale).rounded())),
            pixelHeight: max(1, Int((window.frame.height * scale).rounded())),
            title: window.title,
            displayID: displayID?.uint32Value
        )
    }

    private static func backingScaleFactor(for frame: CGRect) -> CGFloat {
        NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.backingScaleFactor ?? 1
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && (nsError.code == -3801 || nsError.code == -3803)
    }

    private static func processTree(root: pid_t) -> Set<pid_t> {
        let bufferCapacity = 4096
        var pids = [pid_t](repeating: 0, count: bufferCapacity)
        let byteCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard byteCount > 0 else { return [root] }

        let processCount = min(Int(byteCount) / MemoryLayout<pid_t>.stride, pids.count)
        var parentByPID: [pid_t: pid_t] = [:]
        for pid in pids.prefix(processCount) where pid > 0 {
            var info = proc_bsdinfo()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                proc_pidinfo(
                    pid,
                    PROC_PIDTBSDINFO,
                    0,
                    UnsafeMutableRawPointer(pointer),
                    Int32(MemoryLayout<proc_bsdinfo>.stride)
                )
            }
            if result == MemoryLayout<proc_bsdinfo>.stride {
                parentByPID[pid] = pid_t(info.pbi_ppid)
            }
        }

        var result: Set<pid_t> = [root]
        var changed = true
        while changed {
            changed = false
            for (pid, parent) in parentByPID where result.contains(parent) && !result.contains(pid) {
                result.insert(pid)
                changed = true
            }
        }
        return result
    }
}
