import Foundation
import SwiftUI
import UIKit
import Security
import Darwin
import os
import Network
import MachO
import UserNotifications

// MARK: - Modes

enum AppMode: Int, CaseIterable, Identifiable {
    case normal = 0
    case expert = 1
    case dev = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .normal: return LanguageManager.shared.localize("mode.normal")
        case .expert: return LanguageManager.shared.localize("mode.expert")
        case .dev: return LanguageManager.shared.localize("mode.dev")
        }
    }

    func includes(_ tier: AppMode) -> Bool {
        rawValue >= tier.rawValue
    }
}

// MARK: - Models

struct InfoRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var tier: AppMode = .normal
}

struct InfoSection: Identifiable {
    let id = UUID()
    let titleKey: String
    let rows: [InfoRow]

    var title: String { LanguageManager.shared.localize(titleKey) }
}

struct JITLogEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let jitOn: Bool
    let reason: String
}

// MARK: - JIT detection

private let CS_OPS_STATUS: UInt32 = 0
private let CS_OPS_ENTITLEMENTS_BLOB: UInt32 = 7
private let CS_DEBUGGED: UInt32 = 0x10000000

private let CS_FLAG_NAMES: [(value: UInt32, name: String)] = [
    (0x00000001, "CS_VALID"),
    (0x00000002, "CS_ADHOC"),
    (0x00000004, "CS_GET_TASK_ALLOW"),
    (0x00000008, "CS_INSTALLER"),
    (0x00000010, "CS_FORCED_LV"),
    (0x00000020, "CS_INVALID_ALLOWED"),
    (0x00000100, "CS_HARD"),
    (0x00000200, "CS_KILL"),
    (0x00000400, "CS_CHECK_EXPIRATION"),
    (0x00000800, "CS_RESTRICT"),
    (0x00001000, "CS_ENFORCEMENT"),
    (0x00002000, "CS_REQUIRE_LV"),
    (0x00004000, "CS_ENTITLEMENTS_VALIDATED"),
    (0x00008000, "CS_NVRAM_UNRESTRICTED"),
    (0x00010000, "CS_RUNTIME"),
    (0x00020000, "CS_LINKER_SIGNED"),
    (0x01000000, "CS_KILLED"),
    (0x02000000, "CS_DYLD_PLATFORM"),
    (0x04000000, "CS_PLATFORM_BINARY"),
    (0x08000000, "CS_PLATFORM_PATH"),
    (0x10000000, "CS_DEBUGGED"),
    (0x20000000, "CS_SIGNED"),
    (0x40000000, "CS_DEV_CODE"),
    (0x80000000, "CS_DATAVAULT_CONTROLLER")
]

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
        allEntitlements()[key]
    }

    static func allEntitlements() -> [String: Any] {
        if let fromBinary = entitlementsFromSection() { return fromBinary }
        return entitlementsFromCsops()
    }

    private static func entitlementsFromSection() -> [String: Any]? {
        guard let header = executableHeader() else { return nil }
        guard let section = getsectbynamefromheader_64(header, "__TEXT", "__entitlements"),
              section.pointee.size > 0 else { return nil }
        let data = Data(bytes: UnsafeRawPointer(header).advanced(by: Int(section.pointee.offset)),
                        count: Int(section.pointee.size))
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else { return nil }
        return dict
    }

    private static func entitlementsFromCsops() -> [String: Any] {
        var header = CSBlobHeader()
        let headerSize = MemoryLayout<CSBlobHeader>.size
        let rc = withUnsafeMutablePointer(to: &header) { p in
            p.withMemoryRebound(to: CChar.self, capacity: headerSize) {
                csops(getpid(), CS_OPS_ENTITLEMENTS_BLOB, $0, headerSize)
            }
        }
        if rc == 0 { return [:] }
        guard errno == ERANGE else { return [:] }
        let bufferLen = Int(header.length.bigEndian)
        guard bufferLen > 8, bufferLen < 1_048_576 else { return [:] }
        var buffer = [CChar](repeating: 0, count: bufferLen)
        guard csops(getpid(), CS_OPS_ENTITLEMENTS_BLOB, &buffer, bufferLen) == 0 else { return [:] }
        let bytes = buffer.dropFirst(8).map { UInt8(bitPattern: $0) }
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(bytes), options: [], format: nil),
              let dict = plist as? [String: Any] else { return [:] }
        return dict
    }

    private struct CSBlobHeader {
        var magic: UInt32 = 0
        var length: UInt32 = 0
    }

    private static func executableHeader() -> UnsafePointer<mach_header_64>? {
        for i in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(i),
                  header.pointee.magic == MH_MAGIC_64,
                  header.pointee.filetype == MH_EXECUTE else { continue }
            return UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        }
        return nil
    }

    static func entitlementBool(_ key: String) -> Bool {
        (entitlementValue(key) as? NSNumber)?.boolValue ?? false
    }

    // MARK: debugger / code-sign state

    static func csFlags() -> UInt32? {
        var flags: UInt32 = 0
        guard csops(getpid(), CS_OPS_STATUS, &flags, MemoryLayout<UInt32>.size) == 0 else { return nil }
        return flags
    }

    static func csFlagNames(_ flags: UInt32) -> String {
        let set = CS_FLAG_NAMES.filter { flags & $0.value != 0 }.map { $0.name }
        return set.isEmpty ? "none" : set.joined(separator: ", ")
    }

    static func csDebugged() -> Bool {
        guard let flags = csFlags() else { return false }
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
        points.append(InfoRow(label: "csops CS_DEBUGGED", value: debugged ? "YES" : "NO", tier: .expert))
        if debugged { summary.append("Debugger attached (CS_DEBUGGED set)") }

        let traced = tracedSysctl()
        points.append(InfoRow(label: "sysctl KERN_PROC P_TRACED", value: traced ? "YES" : "NO", tier: .expert))
        if traced { summary.append("Debugger attached (P_TRACED set)") }

        let allowJIT = entitlementBool("com.apple.security.cs.allow-jit")
        points.append(InfoRow(label: "Entitlement allow-jit", value: allowJIT ? "YES" : "NO", tier: .expert))
        if allowJIT { summary.append("com.apple.security.cs.allow-jit entitlement") }

        let dynSign = entitlementBool("dynamic-codesigning")
        points.append(InfoRow(label: "Entitlement dynamic-codesigning", value: dynSign ? "YES" : "NO", tier: .expert))
        if dynSign { summary.append("dynamic-codesigning entitlement") }

        let kernJIT = kernJITEntitled()
        points.append(InfoRow(label: "kern.jit_entitled", value: kernJIT, tier: .expert))
        if kernJIT == "1" { summary.append("kern.jit_entitled = 1") }

        let jb = jailbrokenHints()
        points.append(InfoRow(label: "Jailbreak hints", value: jb.isEmpty ? "none" : jb.joined(separator: ", "), tier: .expert))
        if !jb.isEmpty { summary.append("Jailbroken / rootful environment") }

        let enabled = debugged || traced || allowJIT || dynSign || kernJIT == "1" || !jb.isEmpty
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

// MARK: - Flag explanations

enum FlagInfo {
    static func explanation(for label: String) -> String? {
        let l10n = LanguageManager.shared
        switch label {
        case "csops CS_DEBUGGED":
            return l10n.localize("expl.csopsDebugged")
        case "sysctl KERN_PROC P_TRACED":
            return l10n.localize("expl.ptraced")
        case "Entitlement allow-jit":
            return l10n.localize("expl.allowJit")
        case "Entitlement dynamic-codesigning":
            return l10n.localize("expl.dynamicCodesigning")
        case "kern.jit_entitled":
            return l10n.localize("expl.jitEntitled")
        case "Jailbreak hints":
            return l10n.localize("expl.jailbreakHints")
        case "Entitlement increased-memory-limit":
            return l10n.localize("expl.increasedMemory")
        case "Entitlement increased-debugging-memory-limit":
            return l10n.localize("expl.increasedDebug")
        case "Entitlement extended-virtual-addressing":
            return l10n.localize("expl.extendedVA")
        case "os_proc_available_memory":
            return l10n.localize("expl.availableMemory")
        case "Share of physical RAM":
            return l10n.localize("expl.ramShare")
        case "Likely extended (heuristic)":
            return l10n.localize("expl.heuristic")
        case "RLIMIT_AS cur/max":
            return l10n.localize("expl.rlimitAS")
        case "RLIMIT_DATA cur/max":
            return l10n.localize("expl.rlimitData")
        case "phys_footprint":
            return l10n.localize("expl.physFootprint")
        case "Resident size":
            return l10n.localize("expl.resident")
        case "Virtual size":
            return l10n.localize("expl.virtual")
        case "com.apple.security.cs.allow-jit":
            return l10n.localize("expl.allowJitShort")
        case "com.apple.developer.kernel.increased-memory-limit":
            return l10n.localize("expl.increasedMemoryShort")
        case "com.apple.developer.kernel.increased-debugging-memory-limit":
            return l10n.localize("expl.increasedDebugShort")
        case "com.apple.developer.kernel.extended-virtual-addressing":
            return l10n.localize("expl.extendedVAShort")
        case "get-task-allow":
            return l10n.localize("expl.getTaskAllow")
        case let l where l.hasPrefix("csops flags"):
            return l10n.localize("expl.csopsFlags")
        default:
            return nil
        }
    }
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

        points.append(InfoRow(label: "Entitlement increased-memory-limit", value: incLimit ? "YES" : "NO", tier: .expert))
        points.append(InfoRow(label: "Entitlement increased-debugging-memory-limit", value: incDebug ? "YES" : "NO", tier: .expert))
        points.append(InfoRow(label: "Entitlement extended-virtual-addressing", value: extVA ? "YES" : "NO", tier: .expert))
        if incLimit { summary.append("increased-memory-limit entitlement") }
        if incDebug { summary.append("increased-debugging-memory-limit entitlement") }
        if extVA { summary.append("extended-virtual-addressing entitlement") }

        let ram = Int64(ProcessInfo.processInfo.physicalMemory)
        let avail = Int64(os_proc_available_memory())
        let ratio = ram > 0 ? Double(avail) / Double(ram) : 0
        points.append(InfoRow(label: "os_proc_available_memory", value: bytes(avail), tier: .expert))
        points.append(InfoRow(label: "Share of physical RAM", value: String(format: "%.0f %%", ratio * 100), tier: .expert))

        let likely = ratio > 0.60
        points.append(InfoRow(label: "Likely extended (heuristic)", value: likely ? "YES" : "NO", tier: .expert))
        if likely { summary.append("os_proc_available_memory > 60 % of RAM (heuristic)") }

        let asLim = rlimitValue(RLIMIT_AS)
        let dataLim = rlimitValue(RLIMIT_DATA)
        points.append(InfoRow(label: "RLIMIT_AS cur/max", value: "\(limitText(asLim.cur)) / \(limitText(asLim.max))", tier: .dev))
        points.append(InfoRow(label: "RLIMIT_DATA cur/max", value: "\(limitText(dataLim.cur)) / \(limitText(dataLim.max))", tier: .dev))

        if let vm = taskVM() {
            points.append(InfoRow(label: "phys_footprint", value: bytes(Int64(vm.footprint)), tier: .dev))
            points.append(InfoRow(label: "Resident size", value: bytes(Int64(vm.resident)), tier: .dev))
            points.append(InfoRow(label: "Virtual size", value: bytes(Int64(vm.virtual)), tier: .dev))
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
            appSection(),
            kernelSection(),
            entitlementsSection()
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
            InfoRow(label: "Model identifier", value: JITDetector.sysctlString("hw.machine"), tier: .expert)
        ]
        if let name = JITDetector.marketingName() {
            rows.append(InfoRow(label: "Marketing name", value: name))
        }
        rows.append(contentsOf: [
            InfoRow(label: "SoC / board", value: JITDetector.sysctlString("hw.model"), tier: .dev),
            InfoRow(label: "iOS version", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"),
            InfoRow(label: "Kernel release", value: JITDetector.sysctlString("kern.osrelease"), tier: .expert),
            InfoRow(label: "Kernel build", value: JITDetector.sysctlString("kern.osversion"), tier: .dev),
            InfoRow(label: "Uptime", value: uptime(), tier: .expert),
            InfoRow(label: "Jailbroken hints", value: JITDetector.jailbrokenHints().isEmpty ? "No" : "Yes", tier: .expert)
        ])
        return InfoSection(titleKey: "section.system", rows: rows)
    }

    static func cpuSection() -> InfoSection {
        var rows: [InfoRow] = []
        if let ncpu = JITDetector.sysctlInt32("hw.ncpu") {
            rows.append(InfoRow(label: "CPU count", value: "\(ncpu)", tier: .expert))
        }
        if let pcpu = JITDetector.sysctlInt32("hw.physicalcpu") {
            rows.append(InfoRow(label: "Physical cores", value: "\(pcpu)", tier: .expert))
        }
        if let freq = JITDetector.sysctlUInt64("hw.cpufrequency"), freq > 0 {
            rows.append(InfoRow(label: "CPU frequency", value: "\(freq / 1_000_000) MHz", tier: .dev))
        }
        let subtype = JITDetector.sysctlInt32("hw.cpusubtype")
        rows.append(InfoRow(label: "Architecture", value: subtype == 2 ? "arm64e" : "arm64", tier: .dev))
        if let mem = JITDetector.sysctlUInt64("hw.memsize") {
            rows.append(InfoRow(label: "Physical RAM", value: MemoryDetector.bytes(Int64(mem)), tier: .expert))
        }
        return InfoSection(titleKey: "section.cpuRam", rows: rows)
    }

    static func memorySection() -> InfoSection {
        var rows: [InfoRow] = []
        rows.append(InfoRow(label: "Physical RAM", value: MemoryDetector.bytes(Int64(ProcessInfo.processInfo.physicalMemory)), tier: .expert))
        rows.append(InfoRow(label: "os_proc_available_memory", value: MemoryDetector.bytes(Int64(os_proc_available_memory())), tier: .expert))
        if let vs = MemoryDetector.vmStats() {
            rows.append(InfoRow(label: "Free pages", value: MemoryDetector.bytes(Int64(vs.free)), tier: .expert))
            rows.append(InfoRow(label: "Active", value: MemoryDetector.bytes(Int64(vs.active)), tier: .expert))
            rows.append(InfoRow(label: "Inactive", value: MemoryDetector.bytes(Int64(vs.inactive)), tier: .expert))
            rows.append(InfoRow(label: "Wired", value: MemoryDetector.bytes(Int64(vs.wired)), tier: .expert))
            rows.append(InfoRow(label: "Compressed", value: MemoryDetector.bytes(Int64(vs.compressed)), tier: .expert))
        }
        if let vm = MemoryDetector.taskVM() {
            rows.append(InfoRow(label: "App phys_footprint", value: MemoryDetector.bytes(Int64(vm.footprint)), tier: .dev))
            rows.append(InfoRow(label: "App resident", value: MemoryDetector.bytes(Int64(vm.resident)), tier: .dev))
            rows.append(InfoRow(label: "App virtual", value: MemoryDetector.bytes(Int64(vm.virtual)), tier: .dev))
        }
        let asLim = MemoryDetector.rlimitValue(RLIMIT_AS)
        rows.append(InfoRow(label: "RLIMIT_AS cur/max", value: "\(MemoryDetector.limitText(asLim.cur)) / \(MemoryDetector.limitText(asLim.max))", tier: .dev))
        return InfoSection(titleKey: "section.memory", rows: rows)
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
        return InfoSection(titleKey: "section.storage", rows: rows.isEmpty ? [InfoRow(label: "Storage", value: "n/a")] : rows)
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
        return InfoSection(titleKey: "section.battery", rows: [
            InfoRow(label: "Level", value: levelText, tier: .expert),
            InfoRow(label: "State", value: stateText, tier: .expert)
        ])
    }

    static func screenSection() -> InfoSection {
        let screen = UIScreen.main
        return InfoSection(titleKey: "section.screen", rows: [
            InfoRow(label: "Bounds", value: "\(Int(screen.bounds.width)) x \(Int(screen.bounds.height))", tier: .expert),
            InfoRow(label: "Scale", value: String(format: "@%.0fx", screen.scale), tier: .expert),
            InfoRow(label: "Native", value: "\(Int(screen.nativeBounds.width)) x \(Int(screen.nativeBounds.height))", tier: .expert),
            InfoRow(label: "Max FPS", value: "\(screen.maximumFramesPerSecond)", tier: .expert)
        ])
    }

    static func networkSection(_ status: String) -> InfoSection {
        InfoSection(titleKey: "section.network", rows: [InfoRow(label: "Status", value: status, tier: .expert)])
    }

    static func localeSection() -> InfoSection {
        let l = Locale.current
        return InfoSection(titleKey: "section.locale", rows: [
            InfoRow(label: "Locale", value: l.identifier, tier: .expert),
            InfoRow(label: "Region", value: l.regionCode ?? "n/a", tier: .expert),
            InfoRow(label: "Language", value: Locale.preferredLanguages.first ?? "n/a", tier: .expert),
            InfoRow(label: "24-hour", value: DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: l)?.contains("H") == true ? "YES" : "NO", tier: .expert),
            InfoRow(label: "Time zone", value: TimeZone.current.identifier, tier: .expert)
        ])
    }

    static func appSection() -> InfoSection {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let name = info["CFBundleName"] as? String ?? bundle.bundleIdentifier ?? "?"
        var rows: [InfoRow] = [
            InfoRow(label: "Bundle name", value: name, tier: .dev),
            InfoRow(label: "Bundle identifier", value: bundle.bundleIdentifier ?? "n/a", tier: .dev),
            InfoRow(label: "Version", value: "\(version) (\(build))", tier: .expert),
            InfoRow(label: "Process ID", value: "\(getpid())", tier: .dev),
            InfoRow(label: "Parent PID", value: "\(getppid())", tier: .dev),
            InfoRow(label: "Executable path", value: bundle.executablePath ?? "n/a", tier: .dev)
        ]
        let requested: [(String, String)] = [
            ("com.apple.security.cs.allow-jit", "allow-jit"),
            ("com.apple.developer.kernel.increased-memory-limit", "increased-memory-limit"),
            ("com.apple.developer.kernel.increased-debugging-memory-limit", "increased-debugging-memory-limit"),
            ("com.apple.developer.kernel.extended-virtual-addressing", "extended-virtual-addressing")
        ]
        for (key, short) in requested {
            let present = JITDetector.entitlementBool(key)
            rows.append(InfoRow(label: "Entitlement \(short)", value: present ? "present" : "absent", tier: .dev))
        }
        return InfoSection(titleKey: "section.app", rows: rows)
    }

    static func kernelSection() -> InfoSection {
        var rows: [InfoRow] = [
            InfoRow(label: "kern.iossupportversion", value: JITDetector.sysctlString("kern.iossupportversion"), tier: .dev),
            InfoRow(label: "kern.osproductversion", value: JITDetector.sysctlString("kern.osproductversion"), tier: .dev),
            InfoRow(label: "kern.osvariant_status", value: JITDetector.sysctlString("kern.osvariant_status"), tier: .dev),
            InfoRow(label: "kern.securebootstate", value: JITDetector.sysctlString("kern.securebootstate"), tier: .dev),
            InfoRow(label: "kern.tfp.policy", value: JITDetector.sysctlString("kern.tfp.policy"), tier: .dev),
            InfoRow(label: "hw.cputype", value: JITDetector.sysctlString("hw.cputype"), tier: .dev),
            InfoRow(label: "hw.cpusubtype", value: JITDetector.sysctlString("hw.cpusubtype"), tier: .dev),
            InfoRow(label: "hw.pagesize", value: JITDetector.sysctlString("hw.pagesize"), tier: .dev),
            InfoRow(label: "hw.l2cachesize", value: JITDetector.sysctlString("hw.l2cachesize"), tier: .dev)
        ]
        if let flags = JITDetector.csFlags() {
            rows.append(InfoRow(label: "csops flags (0x\(String(flags, radix: 16)))",
                                value: JITDetector.csFlagNames(flags), tier: .dev))
        }
        return InfoSection(titleKey: "section.kernel", rows: rows)
    }

    static func entitlementsSection() -> InfoSection {
        let all = JITDetector.allEntitlements()
        let keys = all.keys.sorted()
        var rows: [InfoRow] = []
        if keys.isEmpty {
            rows.append(InfoRow(label: "Entitlements", value: "none readable", tier: .dev))
        } else {
            for key in keys {
                let value = all[key].map { "\($0)" } ?? "?"
                rows.append(InfoRow(label: key, value: value, tier: .dev))
            }
        }
        return InfoSection(titleKey: "section.entitlements", rows: rows)
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
    @Published var mode: AppMode = .normal {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) }
    }
    @Published var refreshInterval: TimeInterval = 2.0 {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: Keys.refresh) }
    }
    @Published var notifyOnChange = false {
        didSet {
            UserDefaults.standard.set(notifyOnChange, forKey: Keys.notify)
            if notifyOnChange { requestNotificationAuthorization() }
        }
    }
    @Published var notificationsGranted = false
    @Published var jitEnabled = false
    @Published var jitPoints: [InfoRow] = []
    @Published var jitReasons: [String] = []
    @Published var extendedMemory = false
    @Published var memoryPoints: [InfoRow] = []
    @Published var memoryReasons: [String] = []
    @Published var sections: [InfoSection] = []
    @Published var network = "Checking\u{2026}"
    @Published var lastUpdated = Date()
    @Published var jitLog: [JITLogEntry] = []

    private var monitor: NWPathMonitor?
    private var lastJIT: Bool?
    private let haptic = UINotificationFeedbackGenerator()

    private enum Keys {
        static let mode = "appMode"
        static let refresh = "refreshInterval"
        static let notify = "notifyOnChange"
        static let log = "jitLog"
    }

    var visibleJITPoints: [InfoRow] {
        jitPoints.filter { mode.includes($0.tier) }
    }

    var visibleMemoryPoints: [InfoRow] {
        memoryPoints.filter { mode.includes($0.tier) }
    }

    var visibleSections: [InfoSection] {
        sections.compactMap { section in
            let rows = section.rows.filter { mode.includes($0.tier) }
            return rows.isEmpty ? nil : InfoSection(titleKey: section.titleKey, rows: rows)
        }
    }

    var recommendations: [String] {
        computeRecommendations()
    }

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        if let m = AppMode(rawValue: UserDefaults.standard.integer(forKey: Keys.mode)) { mode = m }
        let r = UserDefaults.standard.double(forKey: Keys.refresh)
        if r > 0 { refreshInterval = r }
        notifyOnChange = UserDefaults.standard.bool(forKey: Keys.notify)
        loadLog()
        lastJIT = jitLog.first?.jitOn
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

        let l10n = LanguageManager.shared
        if let last = lastJIT, jit.enabled != last {
            appendLog(entry: JITLogEntry(id: UUID(), date: Date(), jitOn: jit.enabled,
                                         reason: jit.summary.first ?? l10n.localize("notif.logChanged")))
            haptic.notificationOccurred(jit.enabled ? .success : .error)
            if notifyOnChange && notificationsGranted {
                let content = UNMutableNotificationContent()
                content.title = l10n.localize(jit.enabled ? "notif.jitOn" : "notif.jitOff")
                content.body = jit.summary.first ?? l10n.localize("notif.jitChanged")
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        } else if lastJIT == nil {
            appendLog(entry: JITLogEntry(id: UUID(), date: Date(), jitOn: jit.enabled,
                                         reason: jit.summary.first ?? l10n.localize("notif.logInitial")))
        }
        lastJIT = jit.enabled

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

    func reportText() -> String {
        let l10n = LanguageManager.shared
        var lines: [String] = []
        let now = Date().formatted(Date.FormatStyle(date: .long, time: .standard, locale: l10n.locale))
        lines.append(l10n.localize("report.title", now))
        lines.append("")
        lines.append("JIT: \(jitEnabled ? l10n.localize("report.on") : l10n.localize("report.off"))")
        lines.append("Extended Memory: \(extendedMemory ? l10n.localize("report.on") : l10n.localize("report.off"))")
        if !jitReasons.isEmpty { lines.append(l10n.localize("report.jitReason", jitReasons.joined(separator: ", "))) }
        if !memoryReasons.isEmpty { lines.append(l10n.localize("report.memoryReason", memoryReasons.joined(separator: ", "))) }
        if !recommendations.isEmpty {
            lines.append("")
            lines.append(l10n.localize("report.recommendation"))
            lines.append(contentsOf: recommendations)
        }
        lines.append("")
        for section in sections {
            let visible = section.rows.filter { mode.includes($0.tier) }
            guard !visible.isEmpty else { continue }
            lines.append("## \(section.title)")
            for row in visible {
                lines.append("\(row.label): \(row.value)")
            }
            lines.append("")
        }
        if !jitLog.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "dd.MM. HH:mm:ss"
            lines.append(l10n.localize("report.history"))
            for entry in jitLog {
                lines.append("\(f.string(from: entry.date)) \u{2013} JIT \(entry.jitOn ? l10n.localize("report.on") : l10n.localize("report.off")) \u{2013} \(entry.reason)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func computeRecommendations() -> [String] {
        let l10n = LanguageManager.shared
        if jitEnabled {
            var lines = [l10n.localize("rec.jitActive")]
            if let first = jitReasons.first { lines.append(l10n.localize("rec.reason", first)) }
            return lines
        }
        let jailbroken = !JITDetector.jailbrokenHints().isEmpty
        let parts = UIDevice.current.systemVersion.split(separator: ".")
        let major = parts.first.flatMap { Int($0) } ?? 0
        let minor = parts.dropFirst().first.flatMap { Int($0) } ?? 0
        if major > 18 || (major == 18 && minor >= 4) {
            if jailbroken {
                return [l10n.localize("rec.ios184Jb1"),
                        l10n.localize("rec.ios184Jb2")]
            }
            return [l10n.localize("rec.ios184NoJb1"),
                    l10n.localize("rec.ios184NoJb2")]
        }
        if jailbroken {
            return [l10n.localize("rec.jb1")]
        }
        return [l10n.localize("rec.noJb1"),
                l10n.localize("rec.noJb2")]
    }

    private func appendLog(entry: JITLogEntry) {
        jitLog.insert(entry, at: 0)
        if jitLog.count > 100 { jitLog = Array(jitLog.prefix(100)) }
        if let data = try? JSONEncoder().encode(jitLog) {
            UserDefaults.standard.set(data, forKey: Keys.log)
        }
    }

    private func loadLog() {
        guard let data = UserDefaults.standard.data(forKey: Keys.log),
              let entries = try? JSONDecoder().decode([JITLogEntry].self, from: data) else { return }
        jitLog = entries
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.notificationsGranted = granted
            }
        }
    }
}
