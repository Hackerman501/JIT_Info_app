import AppIntents
import Foundation
import UIKit

// MARK: - Status

@available(iOS 16.0, *)
struct GetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get JIT Status"
    static var description = IntentDescription("Returns the current JIT and Extended Memory status of this device.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let jit = JITDetector.detectJIT()
        let mem = MemoryDetector.detect()
        var text = "JIT: \(jit.enabled ? "ON" : "OFF") \u{2013} Extended Memory: \(mem.extended ? "ON" : "OFF")"
        if let reason = jit.summary.first {
            text += "\n\(reason)"
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - Uptime

@available(iOS 16.0, *)
struct GetUptimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Uptime"
    static var description = IntentDescription("Returns how long the device has been running.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: IntentDialog(stringLiteral: "Uptime: \(DeviceInfo.uptime())"))
    }
}

// MARK: - Device info

@available(iOS 16.0, *)
struct GetDeviceInfoIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Device Info"
    static var description = IntentDescription("Returns the device model, iOS version and SoC.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = UIDevice.current.name
        let model = JITDetector.marketingName() ?? JITDetector.sysctlString("hw.machine")
        let ios = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        let soc = JITDetector.socName()
        let text = "\(name) \u{2013} \(model) \u{2013} \(ios) \u{2013} SoC \(soc)"
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - Memory

@available(iOS 16.0, *)
struct GetMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Memory Status"
    static var description = IntentDescription("Returns the Extended Memory status and available memory.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let mem = MemoryDetector.detect()
        let available = MemoryDetector.bytes(Int64(os_proc_available_memory()))
        var text = "Extended Memory: \(mem.extended ? "ON" : "OFF") \u{2013} Available: \(available)"
        if let reason = mem.summary.first {
            text += "\n\(reason)"
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - Battery

@available(iOS 16.0, *)
struct GetBatteryIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Battery Level"
    static var description = IntentDescription("Returns the current battery level and state.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let levelText = level < 0 ? "n/a" : "\(Int(level * 100)) %"
        let state = batteryStateText()
        return .result(dialog: IntentDialog(stringLiteral: "Battery: \(levelText) \u{2013} \(state)"))
    }

    private func batteryStateText() -> String {
        switch UIDevice.current.batteryState {
        case .unplugged: return "not charging"
        case .charging: return "charging"
        case .full: return "full"
        default: return "unknown"
        }
    }
}

// MARK: - Live Activity

@available(iOS 16.0, *)
struct StartLiveActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Live Activity"
    static var description = IntentDescription("Starts a Live Activity with the current JIT status.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            LiveActivityManager.startIfNeeded()
        }
        return .result(dialog: IntentDialog(stringLiteral: "Live Activity started."))
    }
}

@available(iOS 16.0, *)
struct StopLiveActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Live Activity"
    static var description = IntentDescription("Stops the running Live Activity.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            LiveActivityManager.stop()
        }
        return .result(dialog: IntentDialog(stringLiteral: "Live Activity stopped."))
    }
}

// MARK: - Shortcuts provider

@available(iOS 16.0, *)
struct StatusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetStatusIntent(),
                    phrases: ["\(.applicationName) Status"])
        AppShortcut(intent: GetUptimeIntent(),
                    phrases: ["\(.applicationName) Uptime"])
        AppShortcut(intent: GetDeviceInfoIntent(),
                    phrases: ["\(.applicationName) Device Info"])
        AppShortcut(intent: GetMemoryIntent(),
                    phrases: ["\(.applicationName) Memory"])
        AppShortcut(intent: GetBatteryIntent(),
                    phrases: ["\(.applicationName) Battery"])
        AppShortcut(intent: StartLiveActivityIntent(),
                    phrases: ["Start \(.applicationName) Live Activity"])
        AppShortcut(intent: StopLiveActivityIntent(),
                    phrases: ["Stop \(.applicationName) Live Activity"])
    }
}
