import Foundation
import SwiftUI

// MARK: - App language

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case german = "de"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return LanguageManager.shared.localize("settings.language.system")
        case .english: return "English"
        case .german: return "Deutsch"
        }
    }
}

// MARK: - Appearance

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return LanguageManager.shared.localize("settings.appearance.system")
        case .light: return LanguageManager.shared.localize("settings.appearance.light")
        case .dark: return LanguageManager.shared.localize("settings.appearance.dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Language manager

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    private enum Keys {
        static let language = "appLanguage"
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Keys.language)
        language = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
    }

    private var active: AppLanguage {
        language == .system ? systemLanguage : language
    }

    private var systemLanguage: AppLanguage {
        let code = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return code.hasPrefix("de") ? .german : .english
    }

    var locale: Locale {
        Locale(identifier: active.rawValue)
    }

    func localize(_ key: String) -> String {
        guard let value = strings[active]?[key], !value.isEmpty else { return key }
        return value
    }

    func localize(_ key: String, _ args: CVarArg...) -> String {
        String(format: localize(key), locale: locale, arguments: args)
    }

    private let strings: [AppLanguage: [String: String]] = [
        .english: enStrings,
        .german: deStrings
    ]
}

// MARK: - Translations

private let enStrings: [String: String] = [
    "mode.normal": "Normal",
    "mode.expert": "Expert",
    "mode.dev": "Dev",

    "app.title": "iOS Info App",

    "tab.status": "Status",
    "tab.details": "Details",
    "tab.processes": "Processes",
    "tab.network": "Network",
    "tab.settings": "Settings",

    "processes.count": "%d processes",
    "processes.self": "this app",
    "processes.terminate": "Terminate",
    "processes.terminateConfirm": "Terminate \"%@\" (PID %d)?",
    "processes.terminateFailed": "Could not terminate process.",
    "processes.cpu": "CPU",
    "processes.memory": "RAM",
    "processes.state.running": "running",
    "processes.state.sleeping": "sleeping",
    "processes.state.stopped": "stopped",
    "processes.state.zombie": "zombie",
    "processes.state.uninterruptible": "uninterruptible",
    "processes.state.idle": "idle",
    "processes.state.unknown": "unknown",

    "network.header": "Network",
    "network.received": "Received",
    "network.sent": "Sent",
    "network.download": "Down",
    "network.upload": "Up",
    "network.rate": "Rate",
    "network.total": "Total",
    "network.interfaces": "Interfaces",
    "network.noData": "No traffic data available.",

    "settings.title": "Settings",
    "settings.language": "Language",
    "settings.language.system": "System",
    "settings.appearance": "Appearance",
    "settings.appearance.system": "System",
    "settings.appearance.light": "Light",
    "settings.appearance.dark": "Dark",
    "settings.updateInterval": "Update interval",
    "settings.notify": "Notify on JIT change",
    "settings.notificationsActive": "Notifications active \u{2013} you will be notified on every JIT change.",
    "settings.notificationsDenied": "Please allow notifications in iOS Settings.",

    "status.title": "Status",
    "status.updated": "Updated",
    "status.jitChecks": "JIT checks",
    "status.memoryChecks": "Extended Memory checks",

    "recommendation.title": "Recommendation",

    "history.title": "JIT History",
    "history.empty": "No entries yet",

    "report.shareAccessibility": "Share report",
    "report.title": "JIT Info Report \u{2014} %@",
    "report.on": "ON",
    "report.off": "OFF",
    "report.jitReason": "JIT reason: %@",
    "report.memoryReason": "Extended Memory reason: %@",
    "report.recommendation": "## Recommendation",
    "report.history": "## JIT History",

    "rec.jitActive": "JIT is active \u{2013} nothing else needed.",
    "rec.reason": "Reason: %@",
    "rec.ios184Jb1": "iOS 18.4+ with jailbreak: Enable JIT via a debugger tool, e.g. debugserver from Sileo/Cydia.",
    "rec.ios184Jb2": "Alternatively use an app with built-in JIT support (JITStreamer, iDownload).",
    "rec.ios184NoJb1": "iOS 18.4+: JIT is only possible via Xcode debugger or TrollStore 3.",
    "rec.ios184NoJb2": "Install TrollStore 3 (permanent JIT) or debug from a Mac with Xcode.",
    "rec.jb1": "Jailbreak detected: Enable JIT via jailbreak, e.g. through debugserver or a JIT-enable tweak.",
    "rec.noJb1": "Enable JIT via your sideloader: AltStore \u{201C}Enable JIT\u{201D}, SideStore, Sideloadly or JITStreamer.",
    "rec.noJb2": "Tip: With a PC/Mac companion tool you can toggle JIT even without a jailbreak.",

    "notif.jitOn": "JIT enabled",
    "notif.jitOff": "JIT disabled",
    "notif.jitChanged": "JIT status has changed",
    "notif.logChanged": "Status changed",
    "notif.logInitial": "Initial status",

    "section.system": "System",
    "section.cpuRam": "CPU & RAM",
    "section.memory": "Memory",
    "section.storage": "Storage",
    "section.battery": "Battery",
    "section.screen": "Screen",
    "section.network": "Network",
    "section.locale": "Locale",
    "section.app": "App",
    "section.kernel": "Kernel",
    "section.entitlements": "Entitlements",

    "expl.csopsDebugged": "CS_DEBUGGED is set when the process is or has been debugged \u{2013} the kernel then allows JIT via the debugger.",
    "expl.ptraced": "P_TRACED indicates an active ptrace debugger \u{2013} this allows JIT in the kernel.",
    "expl.allowJit": "The 'com.apple.security.cs.allow-jit' entitlement allows the process JIT mapping (memory RW\u{2192}RX).",
    "expl.dynamicCodesigning": "'dynamic-codesigning' allows code-signing states to be changed at runtime \u{2013} a prerequisite for JIT.",
    "expl.jitEntitled": "Kernel sysctl: '1' means the process is marked as JIT-entitled.",
    "expl.jailbreakHints": "Typical jailbreak/rootful paths. If they exist or system paths are writable, this points to a jailbreak.",
    "expl.increasedMemory": "'com.apple.developer.kernel.increased-memory-limit' raises the process memory limit.",
    "expl.increasedDebug": "'com.apple.developer.kernel.increased-debugging-memory-limit' additionally raises the memory limit for debug calls.",
    "expl.extendedVA": "'com.apple.developer.kernel.extended-virtual-addressing' allows extended virtual addressing (beyond 4 GB).",
    "expl.availableMemory": "Bytes still available until the dirty memory limit is hit. The limit itself \u{2248} this value + the current phys_footprint.",
    "expl.memoryLimit": "Estimated process memory limit = os_proc_available_memory() + phys_footprint. iOS default is roughly half the RAM.",
    "expl.ramShare": "Share of the estimated memory limit relative to the physical RAM. \u{2265} 70 % means a raised limit is active.",
    "expl.extendedVerdict": "YES only if the measured limit is \u{2265} 70 % of RAM. Entitlements alone do not prove a raised limit \u{2013} older devices ignore them.",
    "expl.rlimitAS": "Resource limit for the virtual address size. 'cur' = current, 'max' = hard limit, 'unlimited' = no limit.",
    "expl.rlimitData": "Resource limit for the heap / data segment of the process.",
    "expl.physFootprint": "Physical memory footprint of the process (the reliable value since iOS 13).",
    "expl.resident": "Portion of the process currently in RAM (not swapped out).",
    "expl.virtual": "Virtually reserved address space \u{2013} can be much larger than the RAM.",
    "expl.allowJitShort": "Allows JIT (RW\u{2192}RX) mapping for the process.",
    "expl.increasedMemoryShort": "Raises the process memory limit.",
    "expl.increasedDebugShort": "Raises the memory limit for debug calls.",
    "expl.extendedVAShort": "Allows extended virtual addressing.",
    "expl.getTaskAllow": "Allows debuggers (e.g. Xcode) to attach to this app \u{2013} prerequisite for JIT via debugger.",
    "expl.csopsFlags": "Raw flags from csops(CS_OPS_STATUS): the code-signing attributes of the process, decoded with official names in Dev mode."
]

private let deStrings: [String: String] = [
    "mode.normal": "Normal",
    "mode.expert": "Experte",
    "mode.dev": "Dev",

    "app.title": "iOS Info App",

    "tab.status": "Status",
    "tab.details": "Details",
    "tab.processes": "Prozesse",
    "tab.network": "Netzwerk",
    "tab.settings": "Einstellungen",

    "processes.count": "%d Prozesse",
    "processes.self": "diese App",
    "processes.terminate": "Beenden",
    "processes.terminateConfirm": "\u{201E}%@\u{201C} (PID %d) beenden?",
    "processes.terminateFailed": "Prozess konnte nicht beendet werden.",
    "processes.cpu": "CPU",
    "processes.memory": "RAM",
    "processes.state.running": "l\u{00E4}uft",
    "processes.state.sleeping": "schl\u{00E4}ft",
    "processes.state.stopped": "gestoppt",
    "processes.state.zombie": "Zombie",
    "processes.state.uninterruptible": "unterbrechungsfrei",
    "processes.state.idle": "im Leerlauf",
    "processes.state.unknown": "unbekannt",

    "network.header": "Netzwerk",
    "network.received": "Empfangen",
    "network.sent": "Gesendet",
    "network.download": "Down",
    "network.upload": "Up",
    "network.rate": "Rate",
    "network.total": "Gesamt",
    "network.interfaces": "Schnittstellen",
    "network.noData": "Keine Netzwerkdaten verf\u{00FC}gbar.",

    "settings.title": "Einstellungen",
    "settings.language": "Sprache",
    "settings.language.system": "System",
    "settings.appearance": "Darstellung",
    "settings.appearance.system": "System",
    "settings.appearance.light": "Hell",
    "settings.appearance.dark": "Dunkel",
    "settings.updateInterval": "Update-Intervall",
    "settings.notify": "Bei JIT-Wechsel benachrichtigen",
    "settings.notificationsActive": "Benachrichtigungen aktiv \u{2013} du wirst bei jedem JIT-Wechsel informiert.",
    "settings.notificationsDenied": "Bitte erlaube Benachrichtigungen in den iOS-Einstellungen.",

    "status.title": "Status",
    "status.updated": "Aktualisiert",
    "status.jitChecks": "JIT-Checks",
    "status.memoryChecks": "Extended-Memory-Checks",

    "recommendation.title": "Empfehlung",

    "history.title": "JIT-Verlauf",
    "history.empty": "Noch keine Eintr\u{00E4}ge",

    "report.shareAccessibility": "Report teilen",
    "report.title": "JIT Info Report \u{2013} %@",
    "report.on": "AN",
    "report.off": "AUS",
    "report.jitReason": "JIT-Grund: %@",
    "report.memoryReason": "Extended-Memory-Grund: %@",
    "report.recommendation": "## Empfehlung",
    "report.history": "## JIT-Verlauf",

    "rec.jitActive": "JIT ist aktiv \u{2013} nichts weiter n\u{00F6}tig.",
    "rec.reason": "Grund: %@",
    "rec.ios184Jb1": "iOS 18.4+ mit Jailbreak: JIT per Debugger-Tool aktivieren, z. B. debugserver aus Sileo/Cydia.",
    "rec.ios184Jb2": "Alternativ eine App mit eingebauter JIT-Unterst\u{00FC}tzung verwenden (JITStreamer, iDownload).",
    "rec.ios184NoJb1": "iOS 18.4+: JIT ist nur noch \u{00FC}ber Xcode-Debugger oder TrollStore 3 m\u{00F6}glich.",
    "rec.ios184NoJb2": "TrollStore 3 installieren (permanentes JIT) oder am Mac mit Xcode debuggen.",
    "rec.jb1": "Jailbreak erkannt: JIT per Jailbreak aktivieren, z. B. via debugserver oder einem JIT-Enable-Tweak.",
    "rec.noJb1": "JIT \u{00FC}ber den Sideloader aktivieren: AltStore \u{201E}Enable JIT\u{201C}, SideStore, Sideloadly oder JITStreamer.",
    "rec.noJb2": "Tipp: Mit einem PC/Mac-Begleitprogramm l\u{00E4}sst sich JIT auch ohne Jailbreak schalten.",

    "notif.jitOn": "JIT aktiviert",
    "notif.jitOff": "JIT deaktiviert",
    "notif.jitChanged": "JIT-Status hat sich ge\u{00E4}ndert",
    "notif.logChanged": "Status gewechselt",
    "notif.logInitial": "Initialstatus",

    "section.system": "System",
    "section.cpuRam": "CPU & RAM",
    "section.memory": "Speicher",
    "section.storage": "Speicherplatz",
    "section.battery": "Akku",
    "section.screen": "Display",
    "section.network": "Netzwerk",
    "section.locale": "Region",
    "section.app": "App",
    "section.kernel": "Kernel",
    "section.entitlements": "Entitlements",

    "expl.csopsDebugged": "CS_DEBUGGED ist gesetzt, wenn der Prozess gerade oder fr\u{00FC}her debuggt wurde \u{2013} der Kernel erlaubt dann JIT \u{00FC}ber den Debugger.",
    "expl.ptraced": "P_TRACED zeigt einen aktiven ptrace-Debugger an \u{2013} dadurch ist JIT im Kernel erlaubt.",
    "expl.allowJit": "Das Entitlement 'com.apple.security.cs.allow-jit' erlaubt dem Prozess JIT-Mapping (Speicher RW\u{2192}RX).",
    "expl.dynamicCodesigning": "'dynamic-codesigning' erlaubt zur Laufzeit ge\u{00E4}nderte Code-Signatur-Zust\u{00E4}nde \u{2013} Voraussetzung f\u{00FC}r JIT.",
    "expl.jitEntitled": "Kernel-Sysctl: '1' bedeutet, der Prozess ist als JIT-berechtigt markiert.",
    "expl.jailbreakHints": "Typische Jailbreak-/Rootful-Pfade. Existieren sie bzw. sind Systempfade beschreibbar, deutet das auf einen Jailbreak hin.",
    "expl.increasedMemory": "'com.apple.developer.kernel.increased-memory-limit' hebt das Speicherlimit des Prozesses an.",
    "expl.increasedDebug": "'com.apple.developer.kernel.increased-debugging-memory-limit' erh\u{00F6}ht das Speicherlimit zus\u{00E4}tzlich f\u{00FC}r Debug-Aufrufe.",
    "expl.extendedVA": "'com.apple.developer.kernel.extended-virtual-addressing' erlaubt erweiterte virtuelle Adressierung (\u{00FC}ber 4 GB hinaus).",
    "expl.availableMemory": "Noch verf\u{00FC}gbare Bytes, bis die Dirty-Memory-Grenze erreicht ist. Das Limit selbst \u{2248} dieser Wert + aktueller phys_footprint.",
    "expl.memoryLimit": "Gesch\u{00E4}tzte Speichergrenze des Prozesses = os_proc_available_memory() + phys_footprint. iOS-Standard ist etwa die H\u{00E4}lfte des RAMs.",
    "expl.ramShare": "Anteil der gesch\u{00E4}tzten Speichergrenze am physikalischen RAM. \u{2265} 70 % bedeutet ein angehobenes Limit.",
    "expl.extendedVerdict": "YES nur, wenn das gemessene Limit \u{2265} 70 % des RAMs betr\u{00E4}gt. Entitlements allein beweisen kein angehobenes Limit \u{2013} \u{00E4}ltere Ger\u{00E4}te ignorieren sie.",
    "expl.rlimitAS": "Resource-Limit f\u{00FC}r die virtuelle Adressgr\u{00F6}\u{00DF}e. 'cur' = aktuell, 'max' = hartes Limit, 'unlimited' = unbegrenzt.",
    "expl.rlimitData": "Resource-Limit f\u{00FC}r Heap bzw. Daten-Segment des Prozesses.",
    "expl.physFootprint": "Physischer Speicherfu\u{00DF}abdruck des Prozesses (seit iOS 13 der zuverl\u{00E4}ssige Wert).",
    "expl.resident": "Anteil des Prozesses, der gerade im RAM liegt (nicht ausgelagert).",
    "expl.virtual": "Virtuell reservierte Adressmenge \u{2013} kann deutlich gr\u{00F6}\u{00DF}er als der RAM sein.",
    "expl.allowJitShort": "Erlaubt JIT (RW\u{2192}RX)-Mapping f\u{00FC}r den Prozess.",
    "expl.increasedMemoryShort": "Hebt das Speicherlimit des Prozesses an.",
    "expl.increasedDebugShort": "Erh\u{00F6}ht das Speicherlimit f\u{00FC}r Debug-Aufrufe.",
    "expl.extendedVAShort": "Erlaubt erweiterte virtuelle Adressierung.",
    "expl.getTaskAllow": "Erlaubt Debuggern (z. B. Xcode), sich an diese App zu h\u{00E4}ngen \u{2013} Voraussetzung f\u{00FC}r JIT per Debugger.",
    "expl.csopsFlags": "Roh-Flags aus csops(CS_OPS_STATUS): die Code-Signing-Attribute des Prozesses, im Dev-Modus als offizielle Namen decodiert."
]
