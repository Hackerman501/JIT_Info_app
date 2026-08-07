import Foundation
import SwiftUI
import UIKit
import Security
import Darwin
import os
import Network

// MARK: - Models

struct InfoRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct InfoSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [InfoRow]
}

// MARK: - JIT detection

private let CS_OPS_STATUS: UInt32 = 0
private let CS_DEBUGGED: UInt32 = 0x00000800

@_silgen_name("csops")
private func csops(_ pid: pid_t, _ ops: UInt32, _ useraddr: UnsafeMutableRawPointer?, _ usersize: Int) -> Int32

enum JITDetector {

    // MARK: sysctl helpers

    static func sysctlString(_ name: String) -> String {
        var size: size_t = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "n/a" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "n/a" }
        return String(cString: buf)
    }

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var v: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return v
    }

    static func sysctlInt32(_ name: String) -> Int32? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return v
    }

    // MARK: entitlements

    static func entitlementValue(_ key: String) -> Any? {
#if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        defer { CFRelease(task) }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
#else
        return nil
#endif
    }

    static func entitlementBool(_ key: String) -> Bool {
        (entitlementValue(key) as? NSNumber)?.boolValue ?? false
    }

    // MARK: debugger / code-sign state

    static func csDebugged() -> Bool {
        var flags: UInt32 = 0
        guard csops(getpid(), CS_OPS_STATUS, &flags, MemoryLayout<UInt32>.size) == 0 else { return false }
        return (flags & CS_DEBUGGED) != 0
    }

    static func tracedSysctl() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    static func kernJITEntitled() -> String {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.jit_entitled", &v, &size, nil, 0) == 0 { return String(v) }
        return "n/a"
    }

    // MARK: jailbreak hints

    static func jailbrokenHints() -> [String] {
        var hits: [String] = []
        let paths = [
            "/var/jb",
            "/usr/libexec/sftp-server",
            "/bin/bash",
            "/bin/zsh",
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app"
        ]
        for p in paths where FileManager.default.fileExists(atPath: p) { hits.append(p) }
        if access("/var/mobile", R_OK) == 0 { hits.append("/var/mobile readable") }
        if access("/Applications", R_OK) == 0 { hits.append("/Applications readable") }
        return hits
    }

    // MARK: result

    struct JITResult {
        let enabled: Bool
        let points: [InfoRow]
        let summary: [String]
    }

    static func detectJIT() -> JITResult {
        var points: [InfoRow] = []
        var summary: [String] = []

        let debugged = csDebugged()
        points.append(InfoRow(label: "csops CS_DEBUGGED", value: debugged ? "YES" : "NO"))
        if debugged { summary.append("Debugger attached (CS_DEBUGGED set)") }

        let traced = tracedSysctl()
        points.append(InfoRow(label: "sysctl KERN_PROC P_TRACED", value: traced ? "YES" : "NO"))

        let allowJIT = entitlementBool("com.apple.security.cs.allow-jit")
        points.append(InfoRow(label: "Entitlement allow-jit", value: allowJIT ? "YES" : "NO"))
        if allowJIT { summary.append("com.apple.security.cs.allow-jit entitlement") }

        let dynSign = entitlementBool("dynamic-codesigning")
        points.append(InfoRow(label: "Entitlement dynamic-codesigning", value: dynSign ? "YES" : "NO"))
        if dynSign { summary.append("dynamic-codesigning entitlement") }

        points.append(InfoRow(label: "kern.jit_entitled", value: kernJITEntitled()))

        let jb = jailbrokenHints()
        points.append(InfoRow(label: "Jailbreak hints", value: jb.isEmpty ? "none" : jb.joined(separator: ", ")))
        if !jb.isEmpty { summary.append("Jailbroken / rootful environment") }

        let probe = jit_probe()
        let probeText: String
        switch probe {
        case 0:
            probeText = "RW\u{2192}RX transition granted"
            summary.append("Runtime probe succeeded")
        case -2: probeText = "mmap() failed"
        case -3: probeText = "mprotect(PROT_EXEC) rejected"
        case -4: probeText = "probe setup failed"
        default: probeText = "trapped (signal \(probe))"
        }
        points.append(InfoRow(label: "Runtime RW\u{2192}RX probe", value: probeText))

        let enabled = debugged || traced || allowJIT || dynSign || !jb.isEmpty || probe == 0
        return JITResult(enabled: enabled,
                         points: points,
                         summary: summary.isEmpty ? ["No JIT source detected"] : summary)
    }

    // MARK: marketing name

    static func marketingName() -> String? {
        deviceMap[sysctlString("hw.machine")]
    }

    private static let deviceMap: [String: String] = [
        // iPhone
        "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus", "iPhone8,4": "iPhone SE (1st)",
        "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7", "iPhone9,2": "iPhone 7 Plus", "iPhone9,4": "iPhone 7 Plus",
        "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone16,3": "iPhone 16", "iPhone16,4": "iPhone 16 Plus", "iPhone16,5": "iPhone 16e",
        "iPhone17,1": "iPhone 17 Pro", "iPhone17,2": "iPhone 17 Pro Max", "iPhone17,3": "iPhone 17", "iPhone17,4": "iPhone 17 Air",
        // iPad
        "iPad6,3": "iPad Pro 9.7-inch", "iPad6,4": "iPad Pro 9.7-inch",
        "iPad6,7": "iPad Pro 12.9-inch (1st)", "iPad6,8": "iPad Pro 12.9-inch (1st)",
        "iPad6,11": "iPad (5th)", "iPad6,12": "iPad (5th)",
        "iPad7,1": "iPad Pro 12.9-inch (2nd)", "iPad7,2": "iPad Pro 12.9-inch (2nd)",
        "iPad7,3": "iPad Pro 10.5-inch", "iPad7,4": "iPad Pro 10.5-inch",
        "iPad7,5": "iPad (6th)", "iPad7,6": "iPad (6th)",
        "iPad8,1": "iPad Pro 11-inch (1st)", "iPad8,2": "iPad Pro 11-inch (1st)",
        "iPad8,3": "iPad Pro 11-inch (1st)", "iPad8,4": "iPad Pro 11-inch (1st)",
        "iPad8,5": "iPad Pro 12.9-inch (3rd)", "iPad8,6": "iPad Pro 12.9-inch (3rd)",
        "iPad8,7": "iPad Pro 12.9-inch (3rd)", "iPad8,8": "iPad Pro 12.9-inch (3rd)",
        "iPad8,9": "iPad Pro 11-inch (2nd)", "iPad8,10": "iPad Pro 11-inch (2nd)",
        "iPad8,11": "iPad Pro 12.9-inch (4th)", "iPad8,12": "iPad Pro 12.9-inch (4th)",
        "iPad11,1": "iPad mini (5th)", "iPad11,2": "iPad mini (5th)",
        "iPad11,3": "iPad Air (3rd)", "iPad11,4": "iPad Air (3rd)",
        "iPad11,6": "iPad (8th)", "iPad11,7": "iPad (8th)",
        "iPad13,1": "iPad Air (4th)", "iPad13,2": "iPad Air (4th)",
        "iPad13,4": "iPad Pro 11-inch (3rd)", "iPad13,5": "iPad Pro 11-inch (3rd)",
        "iPad13,6": "iPad Pro 11-inch (3rd)", "iPad13,7": "iPad Pro 11-inch (3rd)",
        "iPad13,8": "iPad Pro 12.9-inch (5th)", "iPad13,9": "iPad Pro 12.9-inch (5th)",
        "iPad13,10": "iPad Pro 12.9-inch (5th)", "iPad13,11": "iPad Pro 12.9-inch (5th)",
        "iPad13,16": "iPad mini (6th)", "iPad13,17": "iPad mini (6th)",
        "iPad13,18": "iPad (9th)", "iPad13,19": "iPad (9th)",
        "iPad14,1": "iPad (10th)", "iPad14,2": "iPad (10th)",
        "iPad14,5": "iPad Air (5th)", "iPad14,6": "iPad Air (5th)",
        "iPad14,8": "iPad Pro 11-inch (4th)", "iPad14,9": "iPad Pro 11-inch (4th)",
        "iPad14,10": "iPad Pro 11-inch (4th)", "iPad14,11": "iPad Pro 12.9-inch (6th)",
        "iPad15,3": "iPad Air 11-inch (M2)", "iPad15,4": "iPad Air 11-inch (M2)",
        "iPad15,8": "iPad Air 13-inch (M2)", "iPad15,9": "iPad Air 13-inch (M2)",
        "iPad16,3": "iPad Pro 11-inch (M4)", "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)", "iPad16,7": "iPad Pro 13-inch (M4)",
        "iPad16,1": "iPad mini (7th)", "iPad16,2": "iPad mini (7th)",
        // iPod
        "iPod9,1": "iPod touch (7th)"
    ]
}

// MARK: - Extended memory detection

enum MemoryDetector {

    static func bytes(_ v: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: v, countStyle: .memory)
    }

    static func rlimitValue(_ res: Int32) -> (cur: UInt64, max: UInt64) {
        var lim = rlimit()
        if getrlimit(res, &lim) != 0 { return (0, 0) }
        return (lim.rlim_cur, lim.rlim_max)
    }

    static func limitText(_ v: UInt64) -> String {
        if v == UInt64(Int64.max) { return "unlimited" }
        return bytes(Int64(v))
    }

    static func taskVM() -> (footprint: UInt64, resident: UInt64, virtual: UInt64)? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return (info.phys_footprint, info.resident_size, info.virtual_size)
    }

    static func vmStats() -> (free: UInt64, active: UInt64, inactive: UInt64, wired: UInt64, compressed: UInt64)? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        return (UInt64(stats.free_count) * page,
                UInt64(stats.active_count) * page,
                UInt64(stats.inactive_count) * page,
                UInt64(stats.wire_count) * page,
                UInt64(stats.compressor_page_count) * page)
    }

    struct MemoryResult {
        let extended: Bool
        let points: [InfoRow]
        let summary: [String]
    }

    static func detect() -> MemoryResult {
        var points: [InfoRow] = []
        var summary: [String] = []

        let incLimit = JITDetector.entitlementBool("com.apple.developer.kernel.increased-memory-limit")
        let incDebug = JITDetector.entitlementBool("com.apple.developer.kernel.increased-debugging-memory-limit")
        let extVA = JITDetector.entitlementBool("com.apple.developer.kernel.extended-virtual-addressing")

        points.append(InfoRow(label: "Entitlement increased-memory-limit", value: incLimit ? "YES" : "NO"))
        points.append(InfoRow(label: "Entitlement increased-debugging-memory-limit", value: incDebug ? "YES" : "NO"))
        points.append(InfoRow(label: "Entitlement extended-virtual-addressing", value: extVA ? "YES" : "NO"))
        if incLimit { summary.append("increased-memory-limit entitlement") }
        if incDebug { summary.append("increased-debugging-memory-limit entitlement") }
        if extVA { summary.append("extended-virtual-addressing entitlement") }

        let ram = Int64(ProcessInfo.processInfo.physicalMemory)
        let avail = Int64(os_proc_available_memory())
        let ratio = ram > 0 ? Double(avail) / Double(ram) : 0
        points.append(InfoRow(label: "os_proc_available_memory", value: bytes(avail)))
        points.append(InfoRow(label: "Share of physical RAM", value: String(format: "%.0f %%", ratio * 100)))

        let likely = ratio > 0.60
        points.append(InfoRow(label: "Likely extended (heuristic)", value: likely ? "YES" : "NO"))
        if likely { summary.append("os_proc_available_memory > 60 % of RAM") }

        let asLim = rlimitValue(RLIMIT_AS)
        let dataLim = rlimitValue(RLIMIT_DATA)
        points.append(InfoRow(label: "RLIMIT_AS cur/max", value: "\(limitText(asLim.cur)) / \(limitText(asLim.max))"))
        points.append(InfoRow(label: "RLIMIT_DATA cur/max", value: "\(limitText(dataLim.cur)) / \(limitText(dataLim.max))"))

        if let vm = taskVM() {
            points.append(InfoRow(label: "phys_footprint", value: bytes(Int64(vm.footprint))))
            points.append(InfoRow(label: "Resident size", value: bytes(Int64(vm.resident))))
            points.append(InfoRow(label: "Virtual size", value: bytes(Int64(vm.virtual))))
        }

        let extended = incLimit || incDebug || extVA || likely
        return MemoryResult(extended: extended,
                            points: points,
                            summary: summary.isEmpty ? ["No extended-memory source detected"] : summary)
    }
}

// MARK: - Device info

enum DeviceInfo {

    static func allSections(network: String) -> [InfoSection] {
        [
            systemSection(),
            cpuSection(),
            memorySection(),
            storageSection(),
            batterySection(),
            screenSection(),
            networkSection(network),
            localeSection(),
            appSection()
        ]
    }

    static func uptime() -> String {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, u_int(mib.count), &tv, &size, nil, 0) == 0 else { return "n/a" }
        let boot = Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
        let elapsed = Int(Date().timeIntervalSince(boot))
        let d = elapsed / 86400, h = (elapsed % 86400) / 3600, m = (elapsed % 3600) / 60
        return "\(d)d \(h)h \(m)m"
    }

    static func systemSection() -> InfoSection {
        var rows: [InfoRow] = [
            InfoRow(label: "Device name", value: UIDevice.current.name),
            InfoRow(label: "Product type", value: UIDevice.current.model),
            InfoRow(label: "Model identifier", value: JITDetector.sysctlString("hw.machine"))
        ]
        if let name = JITDetector.marketingName() {
            rows.append(InfoRow(label: "Marketing name", value: name))
        }
        rows.append(contentsOf: [
            InfoRow(label: "SoC / board", value: JITDetector.sysctlString("hw.model")),
            InfoRow(label: "iOS version", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"),
            InfoRow(label: "Kernel release", value: JITDetector.sysctlString("kern.osrelease")),
            InfoRow(label: "Kernel build", value: JITDetector.sysctlString("kern.osversion")),
            InfoRow(label: "Uptime", value: uptime()),
            InfoRow(label: "Jailbroken hints", value: JITDetector.jailbrokenHints().isEmpty ? "No" : "Yes")
        ])
        return InfoSection(title: "System", rows: rows)
    }

    static func cpuSection() -> InfoSection {
        var rows: [InfoRow] = []
        if let ncpu = JITDetector.sysctlInt32("hw.ncpu") {
            rows.append(InfoRow(label: "CPU count", value: "\(ncpu)"))
        }
        if let pcpu = JITDetector.sysctlInt32("hw.physicalcpu") {
            rows.append(InfoRow(label: "Physical cores", value: "\(pcpu)"))
        }
        if let freq = JITDetector.sysctlUInt64("hw.cpufrequency"), freq > 0 {
            rows.append(InfoRow(label: "CPU frequency", value: "\(freq / 1_000_000) MHz"))
        }
        let subtype = JITDetector.sysctlInt32("hw.cpusubtype")
        rows.append(InfoRow(label: "Architecture", value: subtype == 2 ? "arm64e" : "arm64"))
        if let mem = JITDetector.sysctlUInt64("hw.memsize") {
            rows.append(InfoRow(label: "Physical RAM", value: MemoryDetector.bytes(Int64(mem))))
        }
        return InfoSection(title: "CPU & RAM", rows: rows)
    }

    static func memorySection() -> InfoSection {
        var rows: [InfoRow] = []
        rows.append(InfoRow(label: "Physical RAM", value: MemoryDetector.bytes(Int64(ProcessInfo.processInfo.physicalMemory))))
        rows.append(InfoRow(label: "os_proc_available_memory", value: MemoryDetector.bytes(Int64(os_proc_available_memory()))))
        if let vs = MemoryDetector.vmStats() {
            rows.append(InfoRow(label: "Free pages", value: MemoryDetector.bytes(Int64(vs.free))))
            rows.append(InfoRow(label: "Active", value: MemoryDetector.bytes(Int64(vs.active))))
            rows.append(InfoRow(label: "Inactive", value: MemoryDetector.bytes(Int64(vs.inactive))))
            rows.append(InfoRow(label: "Wired", value: MemoryDetector.bytes(Int64(vs.wired))))
            rows.append(InfoRow(label: "Compressed", value: MemoryDetector.bytes(Int64(vs.compressed))))
        }
        if let vm = MemoryDetector.taskVM() {
            rows.append(InfoRow(label: "App phys_footprint", value: MemoryDetector.bytes(Int64(vm.footprint))))
            rows.append(InfoRow(label: "App resident", value: MemoryDetector.bytes(Int64(vm.resident))))
            rows.append(InfoRow(label: "App virtual", value: MemoryDetector.bytes(Int64(vm.virtual))))
        }
        let asLim = MemoryDetector.rlimitValue(RLIMIT_AS)
        rows.append(InfoRow(label: "RLIMIT_AS cur/max", value: "\(MemoryDetector.limitText(asLim.cur)) / \(MemoryDetector.limitText(asLim.max))"))
        return InfoSection(title: "Memory", rows: rows)
    }

    static func storageSection() -> InfoSection {
        var rows: [InfoRow] = []
        if let a = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            if let size = (a[.systemSize] as? NSNumber)?.uint64Value {
                rows.append(InfoRow(label: "Disk capacity", value: MemoryDetector.bytes(Int64(size))))
            }
            if let free = (a[.systemFreeSize] as? NSNumber)?.uint64Value {
                rows.append(InfoRow(label: "Disk free", value: MemoryDetector.bytes(Int64(free))))
            }
        }
        return InfoSection(title: "Storage", rows: rows.isEmpty ? [InfoRow(label: "Storage", value: "n/a")] : rows)
    }

    static func batterySection() -> InfoSection {
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        let stateText: String
        switch state {
        case .unplugged: stateText = "Unplugged"
        case .charging: stateText = "Charging"
        case .full: stateText = "Full"
        default: stateText = "Unknown"
        }
        let levelText = level < 0 ? "n/a" : "\(Int(level * 100)) %"
        return InfoSection(title: "Battery", rows: [
            InfoRow(label: "Level", value: levelText),
            InfoRow(label: "State", value: stateText)
        ])
    }

    static func screenSection() -> InfoSection {
        let screen = UIScreen.main
        return InfoSection(title: "Screen", rows: [
            InfoRow(label: "Bounds", value: "\(Int(screen.bounds.width)) x \(Int(screen.bounds.height))"),
            InfoRow(label: "Scale", value: String(format: "@%.0fx", screen.scale)),
            InfoRow(label: "Native", value: "\(Int(screen.nativeBounds.width)) x \(Int(screen.nativeBounds.height))"),
            InfoRow(label: "Max FPS", value: "\(screen.maximumFramesPerSecond)")
        ])
    }

    static func networkSection(_ status: String) -> InfoSection {
        InfoSection(title: "Network", rows: [InfoRow(label: "Status", value: status)])
    }

    static func localeSection() -> InfoSection {
        let l = Locale.current
        return InfoSection(title: "Locale", rows: [
            InfoRow(label: "Locale", value: l.identifier),
            InfoRow(label: "Region", value: l.regionCode ?? "n/a"),
            InfoRow(label: "Language", value: Locale.preferredLanguages.first ?? "n/a"),
            InfoRow(label: "24-hour", value: DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: l)?.contains("H") == true ? "YES" : "NO"),
            InfoRow(label: "Time zone", value: TimeZone.current.identifier)
        ])
    }

    static func appSection() -> InfoSection {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let name = info["CFBundleName"] as? String ?? bundle.bundleIdentifier ?? "?"
        var rows: [InfoRow] = [
            InfoRow(label: "Bundle name", value: name),
            InfoRow(label: "Bundle identifier", value: bundle.bundleIdentifier ?? "n/a"),
            InfoRow(label: "Version", value: "\(version) (\(build))"),
            InfoRow(label: "Process ID", value: "\(getpid())"),
            InfoRow(label: "Parent PID", value: "\(getppid())"),
            InfoRow(label: "Executable path", value: bundle.executablePath ?? "n/a")
        ]
        let requested: [(String, String)] = [
            ("com.apple.security.cs.allow-jit", "allow-jit"),
            ("com.apple.developer.kernel.increased-memory-limit", "increased-memory-limit"),
            ("com.apple.developer.kernel.increased-debugging-memory-limit", "increased-debugging-memory-limit"),
            ("com.apple.developer.kernel.extended-virtual-addressing", "extended-virtual-addressing")
        ]
        for (key, short) in requested {
            let present = JITDetector.entitlementBool(key)
            rows.append(InfoRow(label: "Entitlement \(short)", value: present ? "present" : "absent"))
        }
        return InfoSection(title: "App", rows: rows)
    }
}

// MARK: - Network monitor

enum NetworkStatus {
    static func start(_ update: @escaping (String) -> Void) -> NWPathMonitor {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            var text = "Unknown"
            if path.status == .satisfied {
                if path.usesInterfaceType(.wifi) { text = "Wi-Fi" }
                else if path.usesInterfaceType(.cellular) { text = "Cellular" }
                else if path.usesInterfaceType(.wiredEthernet) { text = "Ethernet" }
                else { text = "Online" }
            } else if path.status == .requiresConnection {
                text = "Requires connection"
            } else {
                text = "Offline"
            }
            update(text)
        }
        monitor.start(queue: DispatchQueue(label: "network.monitor"))
        return monitor
    }
}

// MARK: - View model

@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published var jitEnabled = false
    @Published var jitPoints: [InfoRow] = []
    @Published var jitReasons: [String] = []
    @Published var extendedMemory = false
    @Published var memoryPoints: [InfoRow] = []
    @Published var memoryReasons: [String] = []
    @Published var sections: [InfoSection] = []
    @Published var network = "Checking\u{2026}"
    @Published var lastUpdated = Date()

    private var monitor: NWPathMonitor?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NetworkStatus.start { [weak self] status in
            Task { @MainActor in
                self?.network = status
            }
        }
        refreshAll()
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    func refreshAll() {
        let jit = JITDetector.detectJIT()
        jitEnabled = jit.enabled
        jitPoints = jit.points
        jitReasons = jit.summary

        let mem = MemoryDetector.detect()
        extendedMemory = mem.extended
        memoryPoints = mem.points
        memoryReasons = mem.summary

        sections = DeviceInfo.allSections(network: network)
        lastUpdated = Date()
    }
}
