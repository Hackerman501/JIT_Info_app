import AppIntents
import Foundation

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
        return .result(dialog: IntentDialog(text))
    }
}

@available(iOS 16.0, *)
struct StatusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetStatusIntent(),
                    phrases: ["\(.applicationName) Status"])
    }
}
