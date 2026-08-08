import SwiftUI
import UIKit
import Charts

struct ContentView: View {
    @StateObject private var model = DiagnosticsModel()
    @EnvironmentObject private var l10n: LanguageManager
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @State private var infoRow: InfoRow?
    @State private var shareItem: ShareItem?
    @State private var selectedTab: AppTab = .status

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                StatusTab(model: model, infoRow: $infoRow)
                    .tabItem {
                        Label(l10n.localize("tab.status"), systemImage: "checkmark.circle")
                    }
                    .tag(AppTab.status)

                DetailsTab(model: model, infoRow: $infoRow)
                    .tabItem {
                        Label(l10n.localize("tab.details"), systemImage: "list.bullet")
                    }
                    .tag(AppTab.details)

                ProcessesTab(model: model)
                    .tabItem {
                        Label(l10n.localize("tab.processes"), systemImage: "terminal")
                    }
                    .tag(AppTab.processes)

                NetworkTab(model: model)
                    .tabItem {
                        Label(l10n.localize("tab.network"), systemImage: "network")
                    }
                    .tag(AppTab.network)

                SettingsTab(model: model, appearance: $appearance)
                    .tabItem {
                        Label(l10n.localize("tab.settings"), systemImage: "gearshape")
                    }
                    .tag(AppTab.settings)
            }
            .navigationTitle(l10n.localize("app.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            shareItem = ShareItem(text: model.reportText())
                        } label: {
                            Label(l10n.localize("report.format.markdown"), systemImage: "doc.text")
                        }
                        Button {
                            shareItem = ShareItem(text: model.reportJSON())
                        } label: {
                            Label(l10n.localize("report.format.json"), systemImage: "curlybraces")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(l10n.localize("report.shareAccessibility"))
                }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task {
            model.start()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(model.refreshInterval * 1_000_000_000))
                model.refreshAll()
            }
        }
        .onDisappear {
            Task { @MainActor in
                model.stop()
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.text])
        }
        .alert(item: $infoRow) { row in
            Alert(
                title: Text(row.label),
                message: Text(FlagInfo.explanation(for: row.label) ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

// MARK: - Tabs

enum AppTab: Int, CaseIterable, Identifiable {
    case status
    case details
    case processes
    case network
    case settings

    var id: Int { rawValue }
}

struct StatusTab: View {
    @ObservedObject var model: DiagnosticsModel
    @Binding var infoRow: InfoRow?
    @EnvironmentObject private var l10n: LanguageManager

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(UIDevice.current.name)
                            .font(.title3.bold())
                            .lineLimit(1)
                        Spacer()
                        Text("iOS \(UIDevice.current.systemVersion)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text(JITDetector.marketingName() ?? JITDetector.sysctlString("hw.machine"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(l10n.localize("settings.mode"), selection: $model.mode) {
                    ForEach(AppMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(l10n.localize("status.title")) {
                HStack(alignment: .top, spacing: 10) {
                    StatusCard(title: "JIT",
                               enabled: model.jitEnabled,
                               details: model.jitReasons)
                    StatusCard(title: l10n.localize("status.card.extendedMemory"),
                               enabled: model.extendedMemory,
                               details: model.memoryReasons)
                }
                HStack {
                    Spacer()
                    Text("\(l10n.localize("status.updated")) \(model.lastUpdated.formatted(.dateTime.hour().minute().second()))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Section(l10n.localize("status.battery")) {
                BatteryRow()
                if let warning = batteryWarning() {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(warning)
                            .font(.footnote)
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }

            if !model.recommendations.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(model.recommendations, id: \.self) { r in
                            Text(r)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } label: {
                        Text(l10n.localize("recommendation.title"))
                            .font(.callout)
                            .foregroundColor(.primary)
                    }
                }
            }

            Section {
                DisclosureGroup {
                    LiveSection(model: model)
                } label: {
                    Text(l10n.localize("status.live"))
                        .font(.callout)
                        .foregroundColor(.primary)
                }
            }

            if !model.visibleJITPoints.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(model.visibleJITPoints) { row in InfoRowView(row: row, onInfo: { infoRow = row }) }
                    } label: {
                        Text(l10n.localize("status.jitChecks"))
                            .font(.callout)
                            .foregroundColor(.primary)
                    }
                }
            }

            if !model.visibleMemoryPoints.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(model.visibleMemoryPoints) { row in InfoRowView(row: row, onInfo: { infoRow = row }) }
                    } label: {
                        Text(l10n.localize("status.memoryChecks"))
                            .font(.callout)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .refreshable {
            model.refreshAll()
        }
    }
}

struct DetailsTab: View {
    @ObservedObject var model: DiagnosticsModel
    @Binding var infoRow: InfoRow?
    @EnvironmentObject private var l10n: LanguageManager
    @State private var exportText: ExportText?
    @State private var confirmClear = false

    var body: some View {
        List {
            if model.mode != .normal {
                DisclosureGroup {
                    if model.jitLog.isEmpty {
                        Text(l10n.localize("history.empty"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(model.jitLog) { entry in
                            HStack(alignment: .top) {
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(entry.jitOn ? l10n.localize("status.on") : l10n.localize("status.off"))
                                    .font(.callout.bold())
                                    .foregroundColor(entry.jitOn ? .green : .red)
                                Spacer(minLength: 8)
                                Text(entry.reason)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        HStack {
                            Spacer()
                            Menu {
                                Button(role: .destructive) {
                                    confirmClear = true
                                } label: {
                                    Label(l10n.localize("history.clear"), systemImage: "trash")
                                }
                                Button {
                                    exportText = ExportText(model.historyCSV())
                                } label: {
                                    Label(l10n.localize("history.export.csv"), systemImage: "tablecells")
                                }
                                Button {
                                    exportText = ExportText(model.historyJSON())
                                } label: {
                                    Label(l10n.localize("history.export.json"), systemImage: "curlybraces")
                                }
                            } label: {
                                Label(l10n.localize("history.export"), systemImage: "square.and.arrow.up")
                            }
                        }
                        .padding(.top, 4)
                    }
                } label: {
                    Text(l10n.localize("history.title"))
                        .font(.callout)
                        .foregroundColor(.primary)
                }
                .confirmationDialog(l10n.localize("history.clearConfirm"), isPresented: $confirmClear, titleVisibility: .visible) {
                    Button(l10n.localize("history.clear"), role: .destructive) {
                        model.clearHistory()
                    }
                    Button(l10n.localize("common.cancel"), role: .cancel) {}
                }
            }

            CompatSection()

            ForEach(model.visibleSections) { section in
                CollapsibleSection(section: section) { row in
                    infoRow = row
                }
            }
        }
        .refreshable {
            model.refreshAll()
        }
        .sheet(item: $exportText) { item in
            ActivityView(items: [item.text])
        }
    }
}

private struct ExportText: Identifiable {
    let id = UUID()
    let text: String

    init(_ text: String) {
        self.text = text
    }
}

struct ProcessesTab: View {
    @ObservedObject var model: DiagnosticsModel
    @EnvironmentObject private var l10n: LanguageManager
    @State private var pendingTerminate: ProcessEntry?

    var body: some View {
        List {
            Section {
                Text(l10n.localize("processes.count", Int32(model.processes.count)))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if model.processListRestricted {
                    Text(l10n.localize("processes.restricted"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            ForEach(model.processes) { entry in
                ProcessRow(entry: entry, onTerminate: {
                    pendingTerminate = entry
                })
            }
        }
        .refreshable {
            model.refreshAll()
        }
        .confirmationDialog(
            Text(l10n.localize("processes.terminate")),
            isPresented: Binding(
                get: { pendingTerminate != nil },
                set: { if !$0 { pendingTerminate = nil } }
            ),
            presenting: pendingTerminate
        ) { entry in
            Button(l10n.localize("processes.terminate"), role: .destructive) {
                terminate(entry)
            }
            Button("OK", role: .cancel) {}
        } message: { entry in
            Text(l10n.localize("processes.terminateConfirm", entry.name, entry.pid))
        }
        .alert(item: $terminateError) { error in
            Alert(title: Text(l10n.localize("processes.terminateFailed")),
                  message: Text(error.message),
                  dismissButton: .default(Text("OK")))
        }
    }

    @State private var terminateError: TerminateError?

    private func terminate(_ entry: ProcessEntry) {
        if let message = ProcessManager.terminate(pid: entry.pid) {
            terminateError = TerminateError(message: message)
        } else {
            model.refreshAll()
        }
    }
}

struct TerminateError: Identifiable {
    let id = UUID()
    let message: String
}

struct ProcessRow: View {
    let entry: ProcessEntry
    let onTerminate: () -> Void
    @EnvironmentObject private var l10n: LanguageManager

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.callout.weight(entry.isSelf ? .bold : .regular))
                        .lineLimit(1)
                    if entry.isSelf {
                        Text(l10n.localize("processes.self"))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundColor(.accentColor)
                    }
                }
                Text("PID \(entry.pid) \u{2022} \(entry.state)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.cpuPercent, specifier: "%.1f") %")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text(MemoryDetector.bytes(Int64(clamping: entry.memoryBytes)))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            if !entry.isSelf {
                Button(action: onTerminate) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct NetworkTab: View {
    @ObservedObject var model: DiagnosticsModel
    @EnvironmentObject private var l10n: LanguageManager

    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f
    }()

    private func bytes(_ value: UInt64) -> String {
        Self.formatter.string(fromByteCount: Int64(clamping: value))
    }

    private func rate(_ value: Double) -> String {
        "\(Self.formatter.string(fromByteCount: Int64(value))) /s"
    }

    var body: some View {
        List {
            Section(l10n.localize("network.header")) {
                HStack(spacing: 10) {
                    TrafficCard(title: l10n.localize("network.download"),
                                icon: "arrow.down.circle.fill",
                                color: .blue,
                                value: rate(model.networkReceivedRate))
                    TrafficCard(title: l10n.localize("network.upload"),
                                icon: "arrow.up.circle.fill",
                                color: .green,
                                value: rate(model.networkSentRate))
                }
            }

            if let traffic = model.networkTraffic {
                Section(l10n.localize("network.total")) {
                    InfoRowView(row: InfoRow(label: l10n.localize("network.received"),
                                             value: bytes(traffic.received)), onInfo: {})
                    InfoRowView(row: InfoRow(label: l10n.localize("network.sent"),
                                             value: bytes(traffic.sent)), onInfo: {})
                }

                if !traffic.interfaces.isEmpty {
                    Section(l10n.localize("network.interfaces")) {
                        ForEach(traffic.interfaces) { iface in
                            HStack(spacing: 8) {
                                Text(iface.name)
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: 90, alignment: .leading)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\u{2193} \(bytes(iface.received))")
                                        .font(.caption.monospacedDigit())
                                    Text("\u{2191} \(bytes(iface.sent))")
                                        .font(.caption.monospacedDigit())
                                }
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text(l10n.localize("network.noData"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
        }
        .refreshable {
            model.refreshAll()
        }
    }
}

struct TrafficCard: View {
    let title: String
    let icon: String
    let color: Color
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

struct SettingsTab: View {
    @ObservedObject var model: DiagnosticsModel
    @Binding var appearance: AppAppearance
    @EnvironmentObject private var l10n: LanguageManager

    var body: some View {
        List {
            Section {
                HStack {
                    Text(l10n.localize("settings.language"))
                    Spacer()
                    Picker(selection: Binding(get: { l10n.language }, set: { l10n.setLanguage($0) })) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.title).tag(lang)
                        }
                    } label: {
                        Text(l10n.localize("settings.language"))
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                HStack {
                    Text(l10n.localize("settings.appearance"))
                    Spacer()
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { a in
                            Text(a.title).tag(a)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                HStack {
                    Text(l10n.localize("settings.updateInterval"))
                    Spacer()
                    Picker("Update interval", selection: $model.refreshInterval) {
                        Text("1 s").tag(1.0)
                        Text("2 s").tag(2.0)
                        Text("5 s").tag(5.0)
                        Text("10 s").tag(10.0)
                        Text("30 s").tag(30.0)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            } header: {
                Text(l10n.localize("settings.title"))
            }
        }
    }
}

struct StatusCard: View {
    let title: String
    let enabled: Bool
    let details: [String]
    @EnvironmentObject private var l10n: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(enabled ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Text(enabled ? l10n.localize("status.on") : l10n.localize("status.off"))
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundColor(enabled ? .green : .red)
            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(details, id: \.self) { d in
                        Text("\u{2022} \(d)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private func batteryWarning() -> String? {
    let device = UIDevice.current
    let level = device.batteryLevel
    guard level >= 0 else { return nil }
    if level < 0.2 && device.batteryState != .charging {
        return LanguageManager.shared.localize("status.battery.low")
    }
    return nil
}

struct BatteryRow: View {
    @EnvironmentObject private var l10n: LanguageManager

    var body: some View {
        let device = UIDevice.current
        let level = device.batteryLevel
        HStack {
            Image(systemName: batteryIcon(level: level, state: device.batteryState))
                .font(.title2)
                .foregroundColor(batteryColor(level: level))
            VStack(alignment: .leading, spacing: 2) {
                Text(level >= 0 ? "\(Int(level * 100)) %" : "n/a")
                    .font(.callout.weight(.semibold))
                Text(batteryStateText(device.batteryState))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private func batteryIcon(level: Float, state: UIDevice.BatteryState) -> String {
        if state == .charging { return "bolt.fill" }
        let pct = level >= 0 ? level * 100 : 0
        switch pct {
        case ..<25: return "battery.25"
        case ..<50: return "battery.50"
        case ..<75: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryColor(level: Float) -> Color {
        level >= 0 && level < 0.2 ? .red : .primary
    }

    private func batteryStateText(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: return l10n.localize("status.battery.charging")
        case .full: return l10n.localize("status.battery.full")
        case .unplugged: return l10n.localize("status.battery.unplugged")
        default: return l10n.localize("status.battery.unknown")
        }
    }
}

struct InfoRowView: View {
    let row: InfoRow
    let onInfo: () -> Void
    @EnvironmentObject private var l10n: LanguageManager

    private var label: String { l10n.localize(row.label) }

    var body: some View {
        if row.collapsible {
            DisclosureGroup {
                Text(row.value)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                Text(label)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(alignment: .top) {
                Text(label)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 220, alignment: .leading)
                Spacer(minLength: 8)
                Text(row.value)
                    .multilineTextAlignment(.trailing)
                if FlagInfo.explanation(for: row.label) != nil {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .font(.footnote)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 6)
                }
            }
            .font(.callout)
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct LiveSection: View {
    @ObservedObject var model: DiagnosticsModel
    @EnvironmentObject private var l10n: LanguageManager

    private var latest: LivePoint? { model.livePoints.last }

    var body: some View {
        if #available(iOS 16.0, *) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    LiveChip(title: l10n.localize("live.cpu"),
                             value: String(format: "%.1f %%", latest?.cpu ?? 0),
                             color: .blue)
                    LiveChip(title: l10n.localize("live.memory"),
                             value: MemoryDetector.bytes(Int64((latest?.memoryMB ?? 0) * 1_048_576)),
                             color: .green)
                    LiveChip(title: l10n.localize("live.thermal"),
                             value: model.thermalStateText(),
                             color: thermalColor)
                }
                if model.livePoints.count > 1 {
                    Chart(model.livePoints) { point in
                        LineMark(x: .value("time", point.time),
                                 y: .value("cpu", point.cpu))
                            .foregroundStyle(.blue)
                            .interpolationMethod(.monotone)
                    }
                    .frame(height: 90)
                    .chartYScale(domain: 0.0...100.0)
                }
            }
        } else {
            Text(l10n.localize("live.requires16"))
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private var thermalColor: Color {
        switch model.thermalState {
        case .nominal: return .green
        case .fair: return .orange
        case .serious, .critical: return .red
        @unknown default: return .gray
        }
    }
}

struct LiveChip: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

struct CollapsibleSection: View {
    let section: InfoSection
    let onInfo: (InfoRow) -> Void
    @EnvironmentObject private var l10n: LanguageManager

    var body: some View {
        Section {
            DisclosureGroup {
                ForEach(section.rows) { row in
                    InfoRowView(row: row, onInfo: { onInfo(row) })
                }
                ForEach(section.groups) { group in
                    DisclosureGroup {
                        ForEach(group.rows) { row in
                            InfoRowView(row: row, onInfo: { onInfo(row) })
                        }
                    } label: {
                        Text(group.title)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
            } label: {
                Text(section.title)
                    .font(.callout)
                    .foregroundColor(.primary)
            }
        }
    }
}

struct CompatSection: View {
    @EnvironmentObject private var l10n: LanguageManager
    @State private var query = ""

    private var filtered: [CompatApp] {
        let all = CompatDatabase.apps
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Section {
            DisclosureGroup {
                TextField(l10n.localize("compat.search"), text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                ForEach(filtered) { app in
                    CompatRow(app: app)
                }
            } label: {
                Text(l10n.localize("compat.title"))
                    .font(.callout)
                    .foregroundColor(.primary)
            }
        }
    }
}

struct CompatRow: View {
    let app: CompatApp
    @EnvironmentObject private var l10n: LanguageManager

    private var symbol: String {
        switch app.jitNeed {
        case .yes: return "bolt.fill"
        case .no: return "checkmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private var symbolColor: Color {
        switch app.jitNeed {
        case .yes: return .orange
        case .no: return .green
        case .unknown: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(app.name)
                    .font(.callout.weight(.semibold))
                Text(app.category)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .foregroundColor(.accentColor)
                Spacer()
                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundColor(symbolColor)
            }
            HStack(spacing: 6) {
                Text(l10n.localize("compat.ios", app.iosRange))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if app.jitNeed == .yes {
                    Text(l10n.localize("compat.needsJit"))
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if app.jitNeed == .unknown {
                    Text(l10n.localize("compat.jitUnknown"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if let note = app.note {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = app.url, let link = URL(string: url) {
                Link(l10n.localize("compat.visit"), destination: link)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
