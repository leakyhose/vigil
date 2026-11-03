import Darwin
import Foundation

enum ProcessInfoLookup {
    /// True if a process with this pid exists (including ones owned by other users).
    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Executable paths of the process's ancestors, nearest first.
    static func ancestorPaths(of pid: pid_t) -> [String] {
        var paths: [String] = []
        var current = pid
        while let parent = parent(of: current), parent > 1, paths.count < 32 {
            paths.append(executablePath(of: parent) ?? "")
            current = parent
        }
        return paths
    }
}
