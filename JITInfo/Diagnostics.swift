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
    var id: String { label }
    let label: String
    let value: String
    var tier: AppMode = .normal
    var collapsible: Bool = false
}

struct InfoSection: Identifiable {
    var id: String { titleKey }
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

struct LivePoint: Identifiable {
    let id = UUID()
    let time: Date
    let cpu: Double
    let memoryMB: Double
    let availableMB: Double
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
    // MARK: SoC detection

    static func socName() -> String {
        socMap[sysctlString("hw.machine")] ?? "unknown"
    }

    static func socFamily() -> String {
        let n = socName()
        if n == "unknown" { return "unknown" }
        if let space = n.firstIndex(of: " ") { return String(n[..<space]) }
        return n
    }

    static func isCheckra1nCompatible() -> Bool {
        ["A8", "A9", "A10", "A11"].contains(socFamily())
    }

    static func isStikDebugTXMCompatible() -> Bool {
        ["A13", "A14", "M1"].contains(socFamily())
    }

    private static let socMap: [String: String] = [
        "iPhone6,1": "A7", "iPhone6,2": "A7",
        "iPhone7,1": "A8", "iPhone7,2": "A8",
        "iPhone8,1": "A9", "iPhone8,2": "A9", "iPhone8,4": "A9",
        "iPhone9,1": "A10", "iPhone9,2": "A10", "iPhone9,3": "A10", "iPhone9,4": "A10",
        "iPhone10,1": "A11", "iPhone10,2": "A11", "iPhone10,3": "A11",
        "iPhone10,4": "A11", "iPhone10,5": "A11", "iPhone10,6": "A11",
        "iPhone11,2": "A12", "iPhone11,4": "A12", "iPhone11,6": "A12", "iPhone11,8": "A12",
        "iPhone12,1": "A13", "iPhone12,3": "A13", "iPhone12,5": "A13", "iPhone12,8": "A13",
        "iPhone13,1": "A14", "iPhone13,2": "A14", "iPhone13,3": "A14", "iPhone13,4": "A14",
        "iPhone14,2": "A15", "iPhone14,3": "A15", "iPhone14,4": "A15", "iPhone14,5": "A15",
        "iPhone14,7": "A15", "iPhone14,8": "A15",
        "iPhone15,2": "A16", "iPhone15,3": "A16", "iPhone15,4": "A16", "iPhone15,5": "A16",
        "iPhone16,1": "A17 Pro", "iPhone16,2": "A17 Pro",
        "iPhone16,3": "A18", "iPhone16,4": "A18", "iPhone16,5": "A18",
        "iPhone17,1": "A19 Pro", "iPhone17,2": "A19 Pro", "iPhone17,3": "A19", "iPhone17,4": "A19",
        "iPad5,1": "A8", "iPad5,2": "A8", "iPad5,3": "A8X", "iPad5,4": "A8X",
        "iPad6,3": "A9X", "iPad6,4": "A9X", "iPad6,7": "A9X", "iPad6,8": "A9X",
        "iPad6,11": "A9", "iPad6,12": "A9",
        "iPad7,1": "A10X", "iPad7,2": "A10X", "iPad7,3": "A10X", "iPad7,4": "A10X",
        "iPad7,5": "A10", "iPad7,6": "A10",
        "iPad8,1": "A12X", "iPad8,2": "A12X", "iPad8,3": "A12X", "iPad8,4": "A12X",
        "iPad8,5": "A12X", "iPad8,6": "A12X", "iPad8,7": "A12X", "iPad8,8": "A12X",
        "iPad8,9": "A12Z", "iPad8,10": "A12Z", "iPad8,11": "A12Z", "iPad8,12": "A12Z",
        "iPad11,1": "A12", "iPad11,2": "A12", "iPad11,3": "A12", "iPad11,4": "A12",
        "iPad11,6": "A12", "iPad11,7": "A12",
        "iPad13,1": "A14", "iPad13,2": "A14",
        "iPad13,4": "M1", "iPad13,5": "M1", "iPad13,6": "M1", "iPad13,7": "M1",
        "iPad13,8": "M1", "iPad13,9": "M1", "iPad13,10": "M1", "iPad13,11": "M1",
        "iPad13,16": "A15", "iPad13,17": "A15",
        "iPad13,18": "A13", "iPad13,19": "A13",
        "iPad14,1": "A14", "iPad14,2": "A14",
        "iPad14,5": "M1", "iPad14,6": "M1",
        "iPad14,8": "M2", "iPad14,9": "M2", "iPad14,10": "M2", "iPad14,11": "M2",
        "iPad15,3": "M2", "iPad15,4": "M2", "iPad15,8": "M2", "iPad15,9": "M2",
        "iPad16,1": "A17 Pro", "iPad16,2": "A17 Pro",
        "iPad16,3": "M4", "iPad16,4": "M4", "iPad16,6": "M4", "iPad16,7": "M4",
        "iPod9,1": "A10"
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
        case "Memory limit (est.)":
            return l10n.localize("expl.memoryLimit")
        case "Share of physical RAM":
            return l10n.localize("expl.ramShare")
        case "Extended memory verdict":
            return l10n.localize("expl.extendedVerdict")
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
        let entitled = incLimit || incDebug || extVA

        points.append(InfoRow(label: "Entitlement increased-memory-limit", value: incLimit ? "YES" : "NO", tier: .expert))
        points.append(InfoRow(label: "Entitlement increased-debugging-memory-limit", value: incDebug ? "YES" : "NO", tier: .expert))
        points.append(InfoRow(label: "Entitlement extended-virtual-addressing", value: extVA ? "YES" : "NO", tier: .expert))

        let ram = Int64(ProcessInfo.processInfo.physicalMemory)
        let avail = Int64(os_proc_available_memory())
        let vm = taskVM()
        let footprint = Int64(vm?.footprint ?? 0)
        // os_proc_available_memory() reports the bytes REMAINING until the dirty memory
        // limit is hit, so the actual limit ≈ remaining + current footprint.
        let limit = avail + footprint
        let ratio = ram > 0 ? Double(limit) / Double(ram) : 0

        points.append(InfoRow(label: "os_proc_available_memory", value: bytes(avail), tier: .expert))
        points.append(InfoRow(label: "Memory limit (est.)", value: "\(bytes(limit)) of \(bytes(ram))", tier: .expert))
        points.append(InfoRow(label: "Share of physical RAM", value: String(format: "%.0f %%", ratio * 100), tier: .expert))

        // Verdict is based on the measured limit, not on entitlement presence alone:
        // the default iOS limit is ~50 % of RAM, so a limit clearly above that means
        // the entitlement was actually granted by the kernel.
        let extended = ratio >= 0.70
        points.append(InfoRow(label: "Extended memory verdict", value: extended ? "YES" : "NO", tier: .expert))

        if extended {
            summary.append("Memory limit raised (~\(Int(ratio * 100)) % of RAM, measured)")
        } else if entitled {
            summary.append("Entitlement present, but limit not raised")
        } else {
            summary.append("Default memory limit (~\(Int(ratio * 100)) % of RAM)")
        }

        let asLim = rlimitValue(RLIMIT_AS)
        let dataLim = rlimitValue(RLIMIT_DATA)
        points.append(InfoRow(label: "RLIMIT_AS cur/max", value: "\(limitText(asLim.cur)) / \(limitText(asLim.max))", tier: .dev))
        points.append(InfoRow(label: "RLIMIT_DATA cur/max", value: "\(limitText(dataLim.cur)) / \(limitText(dataLim.max))", tier: .dev))

        if let vm = vm {
            points.append(InfoRow(label: "phys_footprint", value: bytes(Int64(vm.footprint)), tier: .dev))
            points.append(InfoRow(label: "Resident size", value: bytes(Int64(vm.resident)), tier: .dev))
            points.append(InfoRow(label: "Virtual size", value: bytes(Int64(vm.virtual)), tier: .dev))
        }

        return MemoryResult(extended: extended, points: points, summary: summary)
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
            powerSection(),
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

    static func powerSection() -> InfoSection {
        let info = ProcessInfo.processInfo
        let l10n = LanguageManager.shared
        let thermal: String
        switch info.thermalState {
        case .nominal: thermal = l10n.localize("power.thermal.nominal")
        case .fair: thermal = l10n.localize("power.thermal.fair")
        case .serious: thermal = l10n.localize("power.thermal.serious")
        case .critical: thermal = l10n.localize("power.thermal.critical")
        @unknown default: thermal = "n/a"
        }
        return InfoSection(titleKey: "section.power", rows: [
            InfoRow(label: "power.thermal", value: thermal, tier: .expert),
            InfoRow(label: "power.lowPower", value: info.isLowPowerModeEnabled ? "YES" : "NO", tier: .expert),
            InfoRow(label: "power.appState", value: appStateText(), tier: .expert)
        ])
    }

    private static func appStateText() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return LanguageManager.shared.localize("power.state.active")
        case .inactive: return LanguageManager.shared.localize("power.state.inactive")
        case .background: return LanguageManager.shared.localize("power.state.background")
        @unknown default: return "n/a"
        }
    }

    static func screenSection() -> InfoSection {
        let screen = UIScreen.main
        var rows: [InfoRow] = [
            InfoRow(label: "Bounds", value: "\(Int(screen.bounds.width)) x \(Int(screen.bounds.height))", tier: .expert),
            InfoRow(label: "Scale", value: String(format: "@%.0fx", screen.scale), tier: .expert),
            InfoRow(label: "Native", value: "\(Int(screen.nativeBounds.width)) x \(Int(screen.nativeBounds.height))", tier: .expert),
            InfoRow(label: "Max FPS", value: "\(screen.maximumFramesPerSecond)", tier: .expert)
        ]
        if screen.maximumFramesPerSecond > 0 {
            rows.append(InfoRow(label: "Frame duration (min)",
                                value: String(format: "%.2f ms", 1000.0 / Double(screen.maximumFramesPerSecond)),
                                tier: .dev))
        }
        rows.append(InfoRow(label: "Brightness", value: "\(Int(screen.brightness * 100)) %", tier: .dev))
        rows.append(InfoRow(label: "True Tone", value: trueToneState(), tier: .dev))
        return InfoSection(titleKey: "section.screen", rows: rows)
    }

    private static func trueToneState() -> String {
        let screen = UIScreen.main
        let sel = Selector(("_trueToneEnabled"))
        guard screen.responds(to: sel) else { return "n/a" }
        guard let result = screen.perform(sel) else { return "n/a" }
        if let value = result.takeUnretainedValue() as? NSNumber {
            return value.boolValue ? "YES" : "NO"
        }
        return "n/a"
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
                guard let raw = all[key] else { continue }
                let values = key == "keychain-access-groups" ? raw as? [Any] : nil
                let collapsible = (values?.count ?? 0) > 0
                let value = collapsible
                    ? values!.map { "\($0)" }.joined(separator: "\n")
                    : "\(raw)"
                rows.append(InfoRow(label: key, value: value, tier: .dev, collapsible: collapsible))
            }
        }
        return InfoSection(titleKey: "section.entitlements", rows: rows)
    }
}

// MARK: - Compatibility database

struct CompatApp: Identifiable {
    let id: String
    let name: String
    let categoryKey: String
    let minIOS: String
    let maxIOS: String?
    let needsJIT: Bool
    let noteKey: String?
    let url: String?

    var category: String { LanguageManager.shared.localize(categoryKey) }
    var note: String? { noteKey.map { LanguageManager.shared.localize($0) } }
    var iosRange: String {
        if let max = maxIOS, max == minIOS { return minIOS }
        if let max = maxIOS { return "\(minIOS)\u{2013}\(max)" }
        return "\(minIOS)+"
    }
}

enum CompatDatabase {
    static let apps: [CompatApp] = [
        CompatApp(id: "utm", name: "UTM",
                  categoryKey: "compat.category.emulator", minIOS: "14.0", maxIOS: nil,
                  needsJIT: true, noteKey: "compat.note.utm",
                  url: "https://getutm.app"),
        CompatApp(id: "dolphin", name: "DolphiniOS",
                  categoryKey: "compat.category.emulator", minIOS: "13.0", maxIOS: "26.6",
                  needsJIT: true, noteKey: "compat.note.dolphin", url: nil),
        CompatApp(id: "amethyst", name: "Amethyst",
                  categoryKey: "compat.category.emulator", minIOS: "14.0", maxIOS: nil,
                  needsJIT: true, noteKey: nil, url: nil),
        CompatApp(id: "melonx", name: "MeloNX",
                  categoryKey: "compat.category.emulator", minIOS: "17.0", maxIOS: nil,
                  needsJIT: true, noteKey: nil, url: nil),
        CompatApp(id: "maci", name: "maciOS",
                  categoryKey: "compat.category.emulator", minIOS: "17.0", maxIOS: nil,
                  needsJIT: true, noteKey: "compat.note.macios", url: nil),
        CompatApp(id: "geode", name: "Geode",
                  categoryKey: "compat.category.emulator", minIOS: "17.0", maxIOS: nil,
                  needsJIT: true, noteKey: nil, url: nil),
        CompatApp(id: "manic", name: "Manic EMU",
                  categoryKey: "compat.category.emulator", minIOS: "15.0", maxIOS: nil,
                  needsJIT: true, noteKey: nil, url: nil),
        CompatApp(id: "flycast", name: "Flycast",
                  categoryKey: "compat.category.emulator", minIOS: "15.0", maxIOS: nil,
                  needsJIT: true, noteKey: "compat.note.flycast", url: nil),
        CompatApp(id: "melocafe", name: "MeloCafe",
                  categoryKey: "compat.category.emulator", minIOS: "15.0", maxIOS: nil,
                  needsJIT: true, noteKey: nil, url: nil),
        CompatApp(id: "armsx2", name: "ARMSX2",
                  categoryKey: "compat.category.emulator", minIOS: "15.0", maxIOS: nil,
                  needsJIT: true, noteKey: nil, url: nil),
        CompatApp(id: "dukex", name: "DukeX",
                  categoryKey: "compat.category.emulator", minIOS: "14.0", maxIOS: "27",
                  needsJIT: true, noteKey: "compat.note.dukex", url: nil),
        CompatApp(id: "ppsspp", name: "PPSSPP",
                  categoryKey: "compat.category.emulator", minIOS: "11.0", maxIOS: nil,
                  needsJIT: false, noteKey: "compat.note.ppsspp", url: nil),
        CompatApp(id: "delta", name: "Delta",
                  categoryKey: "compat.category.emulator", minIOS: "12.0", maxIOS: nil,
                  needsJIT: false, noteKey: nil, url: nil),
        CompatApp(id: "provenance", name: "Provenance",
                  categoryKey: "compat.category.emulator", minIOS: "12.0", maxIOS: nil,
                  needsJIT: false, noteKey: nil, url: nil),
        CompatApp(id: "idos", name: "iDOS",
                  categoryKey: "compat.category.emulator", minIOS: "11.0", maxIOS: nil,
                  needsJIT: false, noteKey: nil, url: nil),
        CompatApp(id: "sidestore", name: "SideStore",
                  categoryKey: "compat.category.tool", minIOS: "16.0", maxIOS: nil,
                  needsJIT: false, noteKey: "compat.note.sidestore",
                  url: "https://sidestore.io"),
        CompatApp(id: "stikdebug", name: "StikDebug",
                  categoryKey: "compat.category.tool", minIOS: "17.4", maxIOS: nil,
                  needsJIT: false, noteKey: "compat.note.stikdebug", url: nil),
        CompatApp(id: "trollstore", name: "TrollStore",
                  categoryKey: "compat.category.tool", minIOS: "14.0", maxIOS: "17.0",
                  needsJIT: false, noteKey: "compat.note.trollstore", url: nil)
    ]
}

// MARK: - Network monitor

enum NetworkStatus {
    static func start(_ update: @escaping (String) -> Void) -> NWPathMonitor {
        let l10n = LanguageManager.shared
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            var text = l10n.localize("network.status.unknown")
            if path.status == .satisfied {
                if path.usesInterfaceType(.wifi) { text = l10n.localize("network.status.wifi") }
                else if path.usesInterfaceType(.cellular) { text = l10n.localize("network.status.cellular") }
                else if path.usesInterfaceType(.wiredEthernet) { text = l10n.localize("network.status.ethernet") }
                else { text = l10n.localize("network.status.online") }
            } else if path.status == .requiresConnection {
                text = l10n.localize("network.status.requiresConnection")
            } else {
                text = l10n.localize("network.status.offline")
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
    @Published var processes: [ProcessEntry] = []
    @Published var processListRestricted = false
    @Published var networkTraffic: NetworkTrafficSnapshot?
    @Published var networkReceivedRate: Double = 0
    @Published var networkSentRate: Double = 0
    @Published var livePoints: [LivePoint] = []
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var lowPowerMode = false

    private var monitor: NWPathMonitor?
    private var lastJIT: Bool?
    private let haptic = UINotificationFeedbackGenerator()
    private var lastNetworkSnapshot: NetworkTrafficSnapshot?

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

        let result = ProcessManager.list()
        processes = result.entries
        processListRestricted = result.restricted

        thermalState = ProcessInfo.processInfo.thermalState
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let vm = MemoryDetector.taskVM()
        let selfCPU = processes.first(where: { $0.isSelf })?.cpuPercent ?? 0
        livePoints.append(LivePoint(time: Date(),
                                    cpu: selfCPU,
                                    memoryMB: Double(vm?.footprint ?? 0) / 1_048_576.0,
                                    availableMB: Double(os_proc_available_memory()) / 1_048_576.0))
        if livePoints.count > 180 { livePoints = Array(livePoints.suffix(180)) }

        let net = NetworkTraffic.snapshot()
        if let net = net, let last = lastNetworkSnapshot, net.received >= last.received, net.sent >= last.sent {
            let elapsed = max(lastUpdated.distance(to: Date()), 0.001)
            networkReceivedRate = Double(net.received - last.received) / elapsed
            networkSentRate = Double(net.sent - last.sent) / elapsed
        } else {
            networkReceivedRate = 0
            networkSentRate = 0
        }
        lastNetworkSnapshot = net
        networkTraffic = net

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
        lines.append("SoC: \(JITDetector.socName())")
        lines.append("Thermal: \(thermalStateText())")
        lines.append("Low power mode: \(lowPowerMode ? l10n.localize("report.on") : l10n.localize("report.off"))")
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
        if processListRestricted {
            lines.append(l10n.localize("report.processesRestricted"))
        }
        if !processes.isEmpty {
            lines.append("## \(l10n.localize("report.processes"))")
            for p in processes {
                lines.append("\(p.name) (PID \(p.pid)) \u{2013} \(p.state) \u{2013} CPU \(String(format: "%.1f", p.cpuPercent)) % \u{2013} \(MemoryDetector.bytes(Int64(clamping: p.memoryBytes)))")
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

    func reportJSON() -> String {
        let l10n = LanguageManager.shared
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = f.string(from: Date())
        var sectionsDict: [String: [[String: String]]] = [:]
        for section in sections {
            let visible = section.rows.filter { mode.includes($0.tier) }
            guard !visible.isEmpty else { continue }
            sectionsDict[section.titleKey] = visible.map { ["label": $0.label, "value": $0.value] }
        }
        var processesArray: [[String: Any]] = []
        for p in processes {
            processesArray.append(["pid": p.pid, "name": p.name, "state": p.state,
                                   "cpu": p.cpuPercent, "memory": p.memoryBytes, "isSelf": p.isSelf])
        }
        let log = jitLog.map { ["date": f.string(from: $0.date), "jitOn": $0.jitOn, "reason": $0.reason] }
        let dict: [String: Any] = [
            "generated": dateString,
            "device": [
                "name": UIDevice.current.name,
                "model": UIDevice.current.model,
                "identifier": JITDetector.sysctlString("hw.machine"),
                "marketing": JITDetector.marketingName() ?? "",
                "soc": JITDetector.socName(),
                "ios": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
            ],
            "jit": ["enabled": jitEnabled, "reasons": jitReasons],
            "memory": ["extended": extendedMemory, "reasons": memoryReasons],
            "thermal": thermalStateText(),
            "lowPower": lowPowerMode,
            "processesRestricted": processListRestricted,
            "processes": processesArray,
            "recommendations": recommendations,
            "sections": sectionsDict,
            "history": log
        ]
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func thermalStateText() -> String {
        let l10n = LanguageManager.shared
        switch thermalState {
        case .nominal: return l10n.localize("power.thermal.nominal")
        case .fair: return l10n.localize("power.thermal.fair")
        case .serious: return l10n.localize("power.thermal.serious")
        case .critical: return l10n.localize("power.thermal.critical")
        @unknown default: return "n/a"
        }
    }

    func historyCSV() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines = ["date,jitOn,reason"]
        for entry in jitLog {
            let date = f.string(from: entry.date)
            let on = entry.jitOn ? "ON" : "OFF"
            let reason = entry.reason.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\"\(date)\",\"\(on)\",\"\(reason)\"")
        }
        return lines.joined(separator: "\n")
    }

    func historyJSON() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let items = jitLog.map { ["date": f.string(from: $0.date), "jitOn": $0.jitOn, "reason": $0.reason] }
        let data = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
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

        var lines: [String] = []
        if jailbroken {
            lines.append(l10n.localize("rec.jbGeneral"))
        }

        if major >= 27 {
            lines.append(l10n.localize("rec.v27"))
            if JITDetector.isStikDebugTXMCompatible() {
                lines.append(l10n.localize("rec.soc.stikFixApplies", JITDetector.socName()))
            } else {
                lines.append(l10n.localize("rec.soc.stikFixNotApplies", JITDetector.socName()))
            }
        } else if major == 26 {
            lines.append(l10n.localize("rec.v26"))
            if !JITDetector.isStikDebugTXMCompatible() {
                lines.append(l10n.localize("rec.soc.stikFixNotApplies", JITDetector.socName()))
            }
        } else if major == 18 {
            lines.append(l10n.localize(minor >= 4 ? "rec.v184" : "rec.v18"))
        } else if major == 17 {
            if minor == 0 {
                lines.append(l10n.localize("rec.v170"))
            } else if minor <= 3 {
                lines.append(l10n.localize("rec.v173"))
            } else {
                lines.append(l10n.localize("rec.v174"))
            }
        } else if major == 16 {
            lines.append(l10n.localize("rec.v16"))
            if JITDetector.isCheckra1nCompatible() {
                lines.append(l10n.localize("rec.soc.checkra1n", JITDetector.socName()))
            }
        } else if major == 15 {
            lines.append(l10n.localize("rec.v15"))
            if JITDetector.isCheckra1nCompatible() {
                lines.append(l10n.localize("rec.soc.checkra1n", JITDetector.socName()))
            }
        }

        lines.append(l10n.localize("rec.tipGetTaskAllow"))
        if !jailbroken {
            lines.append(l10n.localize("rec.xcode"))
        }
        return lines
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
