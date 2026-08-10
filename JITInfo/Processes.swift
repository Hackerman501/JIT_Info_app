import Foundation
import Darwin

// MARK: - Process entry

struct ProcessEntry: Identifiable {
    let pid: pid_t
    let name: String
    let state: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let virtualBytes: UInt64
    let parentPid: pid_t?
    let isSelf: Bool

    var id: pid_t { pid }
}

struct ProcessListResult {
    let entries: [ProcessEntry]
    let restricted: Bool
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

@_silgen_name("proc_listallpids")
private func proc_listallpids(_ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_name")
private func proc_name(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

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

    static func list() -> ProcessListResult {
        let now = Date().timeIntervalSince1970
        let cpuCount = Double(ProcessInfo.processInfo.processorCount)

        // Since iOS 9 (WWDC 2015, session 703) the sandbox blocks the whole
        // process table for apps: KERN_PROC_ALL via sysctl fails with EPERM,
        // and proc_listallpids is only a thin wrapper around that same sysctl,
        // so it returns 0 on stock iOS. Apps may only query their own process.
        let pidCount = Int(proc_listallpids(nil, 0))
        guard pidCount > 0, pidCount < 8192 else {
            return selfOnlyResult(now: now, cpuCount: cpuCount)
        }

        var pids = [pid_t](repeating: 0, count: pidCount)
        let written = Int(proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count)))
        guard written > 0 else {
            return selfOnlyResult(now: now, cpuCount: cpuCount)
        }

        // Best-effort process states; stays empty inside the sandbox.
        let stateMap = processStateMap()

        var entries: [ProcessEntry] = []
        var current: [pid_t: Snapshot] = [:]

        for pid in pids.prefix(min(written, pids.count)) where pid > 0 {
            let name = processName(pid)
            let meta = stateMap[pid]
            let state = meta.map { stateString($0.state) } ?? LanguageManager.shared.localize("processes.state.unknown")
            entries.append(buildEntry(pid: pid, name: name, state: state, ppid: meta?.ppid, now: now, cpuCount: cpuCount, current: &current))
        }

        lastSnapshots = current

        return ProcessListResult(entries: entries.sorted {
            let a = $0.isSelf, b = $1.isSelf
            if a != b { return a }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }, restricted: false)
    }

    private static func selfOnlyResult(now: TimeInterval, cpuCount: Double) -> ProcessListResult {
        var current: [pid_t: Snapshot] = [:]
        let selfPid = getpid()
        let meta = processStateMap()[selfPid]
        let entry = buildEntry(pid: selfPid,
                               name: selfProcessName(),
                               state: meta.map { stateString($0.state) } ?? LanguageManager.shared.localize("processes.state.unknown"),
                               ppid: meta?.ppid,
                               now: now, cpuCount: cpuCount, current: &current)
        lastSnapshots = current
        return ProcessListResult(entries: [entry], restricted: true)
    }

    private static func buildEntry(pid: pid_t, name: String, state: String, ppid: pid_t?,
                                   now: TimeInterval, cpuCount: Double,
                                   current: inout [pid_t: Snapshot]) -> ProcessEntry {
        let info = taskInfo(pid: pid)
        let user = info?.totalUser ?? 0
        let sys = info?.totalSystem ?? 0
        let memory = info?.residentSize ?? 0
        let virtual = info?.virtualSize ?? 0

        var cpu = 0.0
        if let prev = lastSnapshots[pid] {
            let dUser = user > prev.user ? user - prev.user : 0
            let dSys = sys > prev.sys ? sys - prev.sys : 0
            let dWall = now - prev.wall
            if dWall > 0 {
                let seconds = (Double(dUser) + Double(dSys)) / 1_000_000.0
                cpu = min(seconds / dWall * 100.0, 100.0 * cpuCount)
            }
        }
        current[pid] = Snapshot(user: user, sys: sys, wall: now)

        return ProcessEntry(pid: pid,
                            name: name.isEmpty ? "\(pid)" : name,
                            state: state,
                            cpuPercent: cpu,
                            memoryBytes: memory,
                            virtualBytes: virtual,
                            parentPid: ppid,
                            isSelf: pid == getpid())
    }

    private static func selfProcessName() -> String {
        let name = processName(getpid())
        if !name.isEmpty { return name }
        return Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? ""
    }

    @discardableResult
    static func terminate(pid: pid_t) -> String? {
        if kill(pid, SIGKILL) == 0 { return nil }
        return String(cString: strerror(errno))
    }

    // MARK: helpers

    private struct ProcessMeta {
        let state: CChar
        let ppid: pid_t
    }

    private static func processStateMap() -> [pid_t: ProcessMeta] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, u_int(mib.count), &procs, &size, nil, 0) == 0 else { return [:] }
        var map: [pid_t: ProcessMeta] = [:]
        for p in procs where p.kp_proc.p_pid > 0 {
            map[p.kp_proc.p_pid] = ProcessMeta(state: p.kp_proc.p_stat, ppid: p.kp_eproc.e_ppid)
        }
        return map
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let len = proc_name(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return "" }
        return String(cString: buffer)
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
}
