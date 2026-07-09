#if canImport(AppKit)
import AppKit
import Darwin
import Foundation

/// Resolves the app a link click originated from, given the Apple Event sender PID.
///
/// Edge case handled here: some Electron/Chromium apps send the `GetURL` event from a
/// helper process that has no bundle identifier. We walk up the parent-process chain
/// until we find a process that belongs to an app bundle.
public enum SourceAppResolver {
    /// Best-effort bundle ID for a sender PID. Returns nil for daemons/unknown senders.
    public static func bundleID(forPID pid: pid_t) -> String? {
        var current = pid
        for _ in 0..<10 { // bounded walk; helper chains are shallow
            if let app = NSRunningApplication(processIdentifier: current),
               let id = app.bundleIdentifier {
                return id
            }
            guard let parent = parentPID(of: current), parent > 1, parent != current else {
                return nil
            }
            current = parent
        }
        return nil
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
#endif
