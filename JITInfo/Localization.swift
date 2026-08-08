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
    "processes.restricted": "iOS blocks the process list in the sandbox. Only this app is visible \u{2013} the full list requires a jailbreak.",
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

    "status.title": "Status",
    "status.updated": "Updated",
    "status.jitChecks": "JIT checks",
    "status.memoryChecks": "Extended Memory checks",
    "status.card.extendedMemory": "Extended Memory",
    "status.battery": "Battery",
    "status.battery.charging": "Charging",
    "status.battery.full": "Full",
    "status.battery.unplugged": "Not charging",
    "status.battery.unknown": "Unknown",
    "status.battery.low": "Battery below 20% \u{2013} JIT sessions may end abruptly when the device sleeps.",

    "recommendation.title": "JIT Recommendation",

    "history.title": "JIT History",
    "history.empty": "No entries yet",
    "history.export": "Export",
    "history.export.csv": "CSV",
    "history.export.json": "JSON",
    "history.clear": "Clear history",
    "history.clearConfirm": "Delete the entire history?",
    "common.cancel": "Cancel",

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
    "rec.jbGeneral": "Jailbroken: JIT is usually granted automatically (e.g. Dopamine's \u{201C}Allow JIT in Apps\u{201D}). If not, attach debugserver to the app.",
    "rec.v27": "iOS 27: JIT is only possible via StikDebug (3.1.6+, supports A13/A14/M1) with a per-app script \u{2013} only a few apps work (UTM, MeloNX, maciOS, Geode, Manic EMU, ARMSX2, DukeX).",
    "rec.v26": "iOS 26: Use StikDebug (updated for iOS 26) or SideStore 0.6.2 \u{2013} on-device JIT. Only a few apps work on iOS 26.6+.",
    "rec.v184": "iOS 18.4\u{2013}18.7: Use StikDebug or SideStore 0.6.2 \u{2013} on-device JIT enablers (pair once with a PC).",
    "rec.v18": "iOS 18.0\u{2013}18.3: Use StikJIT / StikDebug, SideStore or JITStreamer-EB \u{2013} on-device or network JIT enablers.",
    "rec.v174": "iOS 17.4\u{2013}17.9: Use StikJIT / StikDebug \u{2013} on-device JIT (pair once with a PC, needs LocalDevVPN).",
    "rec.v173": "iOS 17.0.1\u{2013}17.3: Use SideJITServer (PC/Mac) or AltJIT via pymobiledevice3 on macOS.",
    "rec.v170": "iOS 17.0: Install TrollStore (CoreTrust bug) and launch the app with JIT.",
    "rec.v16": "iOS 16.x: Install TrollStore and launch the app with JIT. Alternative: AltJIT via AltServer or SideStore.",
    "rec.v15": "iOS 15.x: Install TrollStore and launch the app with JIT. Alternative: AltJIT via AltServer.",
    "rec.tipGetTaskAllow": "Your sideloaded app must include the get-task-allow entitlement, otherwise JIT tools cannot attach.",
    "rec.xcode": "Universal: Launch the app from Xcode on a Mac (get-task-allow) and attach the debugger \u{2013} enables JIT without a jailbreak.",

    "notif.logChanged": "Status changed",
    "notif.logInitial": "Initial status",

    "section.system": "System",
    "section.cpuRam": "CPU & RAM",
    "section.memory": "Memory",
    "section.storage": "Storage",
    "section.battery": "Battery",
    "section.batteryPower": "Battery & Power",
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
    "expl.csopsFlags": "Raw flags from csops(CS_OPS_STATUS): the code-signing attributes of the process, decoded with official names in Dev mode.",

    "settings.mode": "Mode",
    "status.on": "ON",
    "status.off": "OFF",
    "status.live": "Live",
    "live.cpu": "CPU",
    "live.memory": "Memory",
    "live.thermal": "Thermal",
    "live.requires16": "Live charts require iOS 16+.",
    "section.power": "Power",
    "power.thermal": "Thermal state",
    "power.lowPower": "Low power mode",
    "power.appState": "App state",
    "power.thermal.nominal": "nominal",
    "power.thermal.fair": "fair",
    "power.thermal.serious": "serious",
    "power.thermal.critical": "critical",
    "power.state.active": "active",
    "power.state.inactive": "inactive",
    "power.state.background": "background",
    "network.status.unknown": "Unknown",
    "network.status.wifi": "Wi-Fi",
    "network.status.cellular": "Cellular",
    "network.status.ethernet": "Ethernet",
    "network.status.online": "Online",
    "network.status.requiresConnection": "Requires connection",
    "network.status.offline": "Offline",
    "compat.title": "Compatibility",
    "compat.search": "Search apps\u{2026}",
    "compat.ios": "iOS %@",
    "compat.needsJit": "needs JIT",
    "compat.jitUnknown": "JIT requirement unconfirmed",
    "compat.visit": "Visit website",
    "compat.category.emulator": "Emulator",
    "compat.category.tool": "Tool",
    "compat.note.utm": "QEMU-based virtual machines. JIT gives a big speed boost.",
    "compat.note.dolphin": "GameCube/Wii. iOS 26.6+ is not supported.",
    "compat.note.macios": "Runs macOS on Apple Silicon devices.",
    "compat.note.flycast": "Dreamcast. Use the iOS 26 fork on 26+.",
    "compat.note.dukex": "N64. On iOS 27 only on A13/A14/M1.",
    "compat.note.ppsspp": "PSP. Runs without JIT, but much faster with it.",
    "compat.note.sidestore": "SideStore 0.6.2 has built-in on-device JIT (iOS 16 and below or older non-TXM devices).",
    "compat.note.stikdebug": "Latest StikDebug works on iOS 17.4\u{2013}18.x and has a fix for iOS 26/27.",
    "compat.note.trollstore": "TrollStore 14.0b2\u{2013}16.6.1, 16.7RC, 17.0. Launch apps with JIT.",
    "rec.soc.checkra1n": "Your %@ chip is supported by checkra1n (A8\u{2013}A11) \u{2013} semi-tethered jailbreak as an alternative.",
    "rec.soc.stikFixApplies": "Your %@ chip is covered by the StikDebug 3.1.6 fix \u{2013} the on-device JIT script should work.",
    "rec.soc.stikFixNotApplies": "Your %@ chip is NOT covered by the StikDebug fix \u{2013} a per-app script (A15+/M2+) or a PC-based tool is needed.",
    "report.processes": "Processes",
    "report.processesRestricted": "Process list is restricted by iOS \u{2013} only this app is visible.",
    "report.format.markdown": "Markdown",
    "report.format.json": "JSON"
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
    "processes.restricted": "iOS blockiert die Prozessliste in der Sandbox. Nur diese App ist sichtbar \u{2013} die vollst\u{00E4}ndige Liste erfordert einen Jailbreak.",
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

    "status.title": "Status",
    "status.updated": "Aktualisiert",
    "status.jitChecks": "JIT-Checks",
    "status.memoryChecks": "Extended-Memory-Checks",
    "status.card.extendedMemory": "Erweiterter Speicher",
    "status.battery": "Akku",
    "status.battery.charging": "L\u{00E4}dt",
    "status.battery.full": "Voll",
    "status.battery.unplugged": "Nicht am Ladeger\u{00E4}t",
    "status.battery.unknown": "Unbekannt",
    "status.battery.low": "Akku unter 20 % \u{2013} JIT-Sitzungen k\u{00F6}nnen beim Schlafenlegen des Ger\u{00E4}ts abrupt enden.",

    "recommendation.title": "Empfehlung f\u{00FC}r JIT",

    "history.title": "JIT-Verlauf",
    "history.empty": "Noch keine Eintr\u{00E4}ge",
    "history.export": "Exportieren",
    "history.export.csv": "CSV",
    "history.export.json": "JSON",
    "history.clear": "Verlauf l\u{00F6}schen",
    "history.clearConfirm": "Gesamten Verlauf l\u{00F6}schen?",
    "common.cancel": "Abbrechen",

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
    "rec.jbGeneral": "Gejailbreakt: JIT wird meist automatisch erteilt (z. B. Dopamines \u{201E}Allow JIT in Apps\u{201C}). Falls nicht, debugserver an die App anh\u{00E4}ngen.",
    "rec.v27": "iOS 27: JIT ist nur \u{00FC}ber StikDebug (3.1.6+, unterst\u{00FC}tzt A13/A14/M1) mit einem App-Skript m\u{00F6}glich \u{2013} nur wenige Apps funktionieren (UTM, MeloNX, maciOS, Geode, Manic EMU, ARMSX2, DukeX).",
    "rec.v26": "iOS 26: StikDebug (f\u{00FC}r iOS 26 aktualisiert) oder SideStore 0.6.2 nutzen \u{2013} JIT direkt am Ger\u{00E4}t. Nur wenige Apps funktionieren auf iOS 26.6+.",
    "rec.v184": "iOS 18.4\u{2013}18.7: StikDebug oder SideStore 0.6.2 nutzen \u{2013} On-Device-JIT (einmal mit PC koppeln).",
    "rec.v18": "iOS 18.0\u{2013}18.3: StikJIT / StikDebug, SideStore oder JITStreamer-EB nutzen \u{2013} JIT direkt am Ger\u{00E4}t oder \u{00FC}ber Netzwerk.",
    "rec.v174": "iOS 17.4\u{2013}17.9: StikJIT / StikDebug nutzen \u{2013} On-Device-JIT (einmal mit PC koppeln, ben\u{00F6}tigt LocalDevVPN).",
    "rec.v173": "iOS 17.0.1\u{2013}17.3: SideJITServer (PC/Mac) oder AltJIT per pymobiledevice3 auf macOS verwenden.",
    "rec.v170": "iOS 17.0: TrollStore installieren (CoreTrust-Bug) und die App mit JIT starten.",
    "rec.v16": "iOS 16.x: TrollStore installieren und die App mit JIT starten. Alternative: AltJIT \u{00FC}ber AltServer oder SideStore.",
    "rec.v15": "iOS 15.x: TrollStore installieren und die App mit JIT starten. Alternative: AltJIT \u{00FC}ber AltServer.",
    "rec.tipGetTaskAllow": "Die sideloaded App muss die get-task-allow-Berechtigung enthalten, sonst k\u{00F6}nnen JIT-Tools nicht andocken.",
    "rec.xcode": "Universell: App am Mac aus Xcode starten (get-task-allow) und Debugger anh\u{00E4}ngen \u{2013} aktiviert JIT ohne Jailbreak.",

    "notif.logChanged": "Status gewechselt",
    "notif.logInitial": "Initialstatus",

    "section.system": "System",
    "section.cpuRam": "CPU & RAM",
    "section.memory": "Speicher",
    "section.storage": "Speicherplatz",
    "section.battery": "Akku",
    "section.batteryPower": "Akku & Energie",
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
    "expl.csopsFlags": "Roh-Flags aus csops(CS_OPS_STATUS): die Code-Signing-Attribute des Prozesses, im Dev-Modus als offizielle Namen decodiert.",

    "settings.mode": "Modus",
    "status.on": "AN",
    "status.off": "AUS",
    "status.live": "Live",
    "live.cpu": "CPU",
    "live.memory": "Speicher",
    "live.thermal": "Thermik",
    "live.requires16": "Live-Diagramme erfordern iOS 16+.",
    "section.power": "Energie",
    "power.thermal": "Thermischer Zustand",
    "power.lowPower": "Energiesparmodus",
    "power.appState": "App-Zustand",
    "power.thermal.nominal": "normal",
    "power.thermal.fair": "erh\u{00F6}ht",
    "power.thermal.serious": "kritisch",
    "power.thermal.critical": "dringend kritisch",
    "power.state.active": "aktiv",
    "power.state.inactive": "inaktiv",
    "power.state.background": "im Hintergrund",
    "network.status.unknown": "Unbekannt",
    "network.status.wifi": "WLAN",
    "network.status.cellular": "Mobilfunk",
    "network.status.ethernet": "Ethernet",
    "network.status.online": "Online",
    "network.status.requiresConnection": "Verbindung erforderlich",
    "network.status.offline": "Offline",
    "compat.title": "Kompatibilit\u{00E4}t",
    "compat.search": "Apps suchen\u{2026}",
    "compat.ios": "iOS %@",
    "compat.needsJit": "braucht JIT",
    "compat.jitUnknown": "JIT-Bedarf unbesta\u{00E4}tigt",
    "compat.visit": "Website besuchen",
    "compat.category.emulator": "Emulator",
    "compat.category.tool": "Werkzeug",
    "compat.note.utm": "QEMU-basierte virtuelle Maschinen. JIT bringt gro\u{00DF}en Geschwindigkeitsschub.",
    "compat.note.dolphin": "GameCube/Wii. iOS 26.6+ wird nicht unterst\u{00FC}tzt.",
    "compat.note.macios": "F\u{00FC}hrt macOS auf Apple-Silicon-Ger\u{00E4}ten aus.",
    "compat.note.flycast": "Dreamcast. Auf 26+ den iOS-26-Fork verwenden.",
    "compat.note.dukex": "N64. Auf iOS 27 nur auf A13/A14/M1.",
    "compat.note.ppsspp": "PSP. L\u{00E4}uft ohne JIT, aber deutlich schneller damit.",
    "compat.note.sidestore": "SideStore 0.6.2 hat eingebautes On-Device-JIT (iOS 16 und darunter oder \u{00E4}ltere Nicht-TXM-Ger\u{00E4}te).",
    "compat.note.stikdebug": "Aktuelles StikDebug funktioniert auf iOS 17.4\u{2013}18.x und hat einen Fix f\u{00FC}r iOS 26/27.",
    "compat.note.trollstore": "TrollStore 14.0b2\u{2013}16.6.1, 16.7RC, 17.0. Apps mit JIT starten.",
    "rec.soc.checkra1n": "Dein %@-Chip wird von checkra1n (A8\u{2013}A11) unterst\u{00FC}tzt \u{2013} Semi-Tethered-Jailbreak als Alternative.",
    "rec.soc.stikFixApplies": "Dein %@-Chip wird vom StikDebug-3.1.6-Fix abgedeckt \u{2013} das On-Device-JIT-Skript sollte funktionieren.",
    "rec.soc.stikFixNotApplies": "Dein %@-Chip wird vom StikDebug-Fix NICHT abgedeckt \u{2013} ein App-Skript (A15+/M2+) oder ein PC-Tool ist n\u{00F6}tig.",
    "report.processes": "Prozesse",
    "report.processesRestricted": "Die Prozessliste wird von iOS eingeschr\u{00E4}nkt \u{2013} nur diese App ist sichtbar.",
    "report.format.markdown": "Markdown",
    "report.format.json": "JSON",

    "Device name": "Ger\u{00E4}tename",
    "Product type": "Produkttyp",
    "Model identifier": "Modellkennung",
    "Marketing name": "Marketingname",
    "SoC / board": "SoC / Board",
    "iOS version": "iOS-Version",
    "Kernel release": "Kernel-Release",
    "Kernel build": "Kernel-Build",
    "Uptime": "Laufzeit",
    "Jailbroken hints": "Jailbreak-Hinweise",
    "Jailbreak hints": "Jailbreak-Hinweise",
    "CPU count": "CPU-Anzahl",
    "Physical cores": "Physische Kerne",
    "CPU frequency": "CPU-Takt",
    "Architecture": "Architektur",
    "Physical RAM": "Physischer RAM",
    "Free pages": "Freie Seiten",
    "Active": "Aktiv",
    "Inactive": "Inaktiv",
    "Wired": "Wired",
    "Compressed": "Komprimiert",
    "App phys_footprint": "App phys_footprint",
    "App resident": "App resident",
    "App virtual": "App virtual",
    "RLIMIT_AS cur/max": "RLIMIT_AS aktuell/max",
    "RLIMIT_DATA cur/max": "RLIMIT_DATA aktuell/max",
    "Disk capacity": "Speicherkapazit\u{00E4}t",
    "Disk free": "Speicher frei",
    "Storage": "Speicher",
    "Level": "Ladestand",
    "State": "Zustand",
    "Bounds": "Abmessungen",
    "Scale": "Skalierung",
    "Native": "Nativ",
    "Max FPS": "Max. FPS",
    "Frame duration (min)": "Bilddauer (min)",
    "Brightness": "Helligkeit",
    "True Tone": "True Tone",
    "Status": "Status",
    "Locale": "Region",
    "Region": "Region",
    "Language": "Sprache",
    "24-hour": "24-Stunden",
    "Time zone": "Zeitzone",
    "Bundle name": "Bundle-Name",
    "Bundle identifier": "Bundle-ID",
    "Version": "Version",
    "Process ID": "Prozess-ID",
    "Parent PID": "\u{00DC}bergeordnete PID",
    "Executable path": "Pfad der ausf\u{00FC}hrbaren Datei",
    "Entitlement allow-jit": "Berechtigung allow-jit",
    "Entitlement increased-memory-limit": "Berechtigung increased-memory-limit",
    "Entitlement increased-debugging-memory-limit": "Berechtigung increased-debugging-memory-limit",
    "Entitlement extended-virtual-addressing": "Berechtigung extended-virtual-addressing",
    "Entitlement dynamic-codesigning": "Berechtigung dynamic-codesigning",
    "Memory limit (est.)": "Speicherlimit (gesch\u{00E4}tzt)",
    "Share of physical RAM": "Anteil am physischen RAM",
    "Extended memory verdict": "Extended-Memory-Urteil",
    "phys_footprint": "phys_footprint",
    "Resident size": "Residente Gr\u{00F6}\u{00DF}e",
    "Virtual size": "Virtuelle Gr\u{00F6}\u{00DF}e",
    "Entitlements": "Entitlements"
]
