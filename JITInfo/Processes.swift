import Foundation
import Darwin

// MARK: - Process entry

struct ProcessEntry: Identifiable {
    let pid: pid_t
    let name: String
    let state: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let isSelf: Bool

    var id: pid_t { pid }
}

// MARK: - libproc helpers

private let PROC_PIDTASKINFO: Int32 = 4

private struct ProcTaskInfo {
    var virtualSize: UInt64 = 0
    var residentSize: UInt64 = 0
    var totalUser: UInt64 = 0
    var totalSystem: UInt64 = 0
    var threadsUser: UInt64 = 0
    var threadsSystem: UInt64 = 0
    var policy: Int32 = 0
    var faults: Int32 = 0
    var pageins: Int32 = 0
    var cowFaults: Int32 = 0
    var messagesSent: Int32 = 0
    var messagesReceived: Int32 = 0
    var syscallsMade: Int32 = 0
    var syscallsMadeDerived: Int32 = 0
    var syscalls: Int32 = 0
    var csw: Int32 = 0
    var qlen: Int32 = 0
    var cpuUsage: Int32 = 0
    var jetsamPriority: Int32 = 0
    var physFootprint: UInt64 = 0
}

@_silgen_name("proc_pidinfo")
private func proc_pidinfo(_ pid: Int32,
                          _ flavor: Int32,
                          _ arg: UInt64,
                          _ buffer: UnsafeMutableRawPointer?,
                          _ bufferSize: Int32) -> Int32

private func taskInfo(pid: pid_t) -> ProcTaskInfo? {
    var info = ProcTaskInfo()
    let size = Int32(MemoryLayout<ProcTaskInfo>.stride)
    let rc = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(size)) {
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, size)
        }
    }
    return rc == size ? info : nil
}

// MARK: - Process manager

enum ProcessManager {

    private struct Snapshot {
        let user: UInt64
        let sys: UInt64
        let wall: TimeInterval
    }

    private static var lastSnapshots: [pid_t: Snapshot] = [:]

    static func list() -> [ProcessEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, u_int(mib.count), &procs, &size, nil, 0) == 0 else { return [] }

        let now = Date().timeIntervalSince1970
        let selfPID = getpid()
        let cpuCount = Double(ProcessInfo.processInfo.processorCount)
        var entries: [ProcessEntry] = []
        var current: [pid_t: Snapshot] = [:]

        for p in procs where p.kp_proc.p_pid > 0 {
            let pid = p.kp_proc.p_pid
            let name = commString(p.kp_proc.p_comm)
            let state = stateString(p.kp_proc.p_stat)

            let user = timevalMicros(p.kp_proc.p_ru.ru_utime)
            let sys = timevalMicros(p.kp_proc.p_ru.ru_stime)
            var cpu = 0.0
            if let prev = lastSnapshots[pid] {
                let dUser = user > prev.user ? user - prev.user : 0
                let dSys = sys > prev.sys ? sys - prev.sys : 0
                let dWall = now - prev.wall
                if dWall > 0 {
                    cpu = min((Double(dUser + dSys) / 1_000_000.0) / dWall * 100.0,
                              100.0 * cpuCount)
                }
            }
            current[pid] = Snapshot(user: user, sys: sys, wall: now)

            let memory = taskInfo(pid: pid)?.residentSize ?? 0

            entries.append(ProcessEntry(pid: pid,
                                        name: name.isEmpty ? "\(pid)" : name,
                                        state: state,
                                        cpuPercent: cpu,
                                        memoryBytes: memory,
                                        isSelf: pid == selfPID))
        }

        lastSnapshots = current

        return entries.sorted {
            let a = $0.isSelf, b = $1.isSelf
            if a != b { return a }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    static func terminate(pid: pid_t) -> Result<Void, String> {
        if kill(pid, SIGKILL) == 0 {
            return .success(())
        }
        return .failure(String(cString: strerror(errno)))
    }

    // MARK: helpers

    private static func commString<T>(_ comm: T) -> String {
        withUnsafeBytes(of: comm) { raw in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    private static func stateString(_ stat: CChar) -> String {
        let key: String
        switch stat {
        case 1: key = "processes.state.idle"
        case 2: key = "processes.state.running"
        case 3: key = "processes.state.sleeping"
        case 4: key = "processes.state.stopped"
        case 5: key = "processes.state.zombie"
        case 6: key = "processes.state.uninterruptible"
        default: return "\(stat)"
        }
        return LanguageManager.shared.localize(key)
    }

    private static func timevalMicros(_ tv: timeval) -> UInt64 {
        UInt64(max(tv.tv_sec, 0)) * 1_000_000 + UInt64(max(tv.tv_usec, 0))
    }
}
