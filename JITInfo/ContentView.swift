import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = DiagnosticsModel()
    @State private var showShare = false

    var body: some View {
        NavigationView {
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
                    Picker("Modus", selection: $model.mode) {
                        ForEach(AppMode.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    HStack {
                        Text("Update interval")
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
                    Toggle("Notify on JIT change", isOn: $model.notifyOnChange)
                } header: {
                    Text("Settings")
                } footer: {
                    if model.notifyOnChange {
                        Text(model.notificationsGranted
                             ? "Benachrichtigungen aktiv \u{2013} du wirst bei jedem JIT-Wechsel informiert."
                             : "Bitte erlaube Benachrichtigungen in den iOS-Einstellungen.")
                    }
                }

                Section("Status") {
                    HStack(alignment: .top, spacing: 10) {
                        StatusCard(title: "JIT",
                                   enabled: model.jitEnabled,
                                   details: model.jitReasons)
                        StatusCard(title: "Extended Memory",
                                   enabled: model.extendedMemory,
                                   details: model.memoryReasons)
                    }
                    HStack {
                        Spacer()
                        Text("Updated \(model.lastUpdated, format: .dateTime.hour().minute().second())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if !model.recommendations.isEmpty {
                    Section("Empfehlung") {
                        ForEach(model.recommendations, id: \.self) { r in
                            Text(r)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !model.visibleJITPoints.isEmpty {
                    Section("JIT checks") {
                        ForEach(model.visibleJITPoints) { InfoRowView(row: $0) }
                    }
                }

                if !model.visibleMemoryPoints.isEmpty {
                    Section("Extended Memory checks") {
                        ForEach(model.visibleMemoryPoints) { InfoRowView(row: $0) }
                    }
                }

                if model.mode != .normal {
                    Section("JIT Verlauf") {
                        if model.jitLog.isEmpty {
                            Text("Noch keine Eintr\u{00E4}ge")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(model.jitLog) { entry in
                                HStack(alignment: .top) {
                                    Text(entry.date, format: .dateTime.hour().minute().second())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(entry.jitOn ? "ON" : "OFF")
                                        .font(.callout.bold())
                                        .foregroundColor(entry.jitOn ? .green : .red)
                                    Spacer(minLength: 8)
                                    Text(entry.reason)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    }
                }

                ForEach(model.visibleSections) { section in
                    Section(header: Text(section.title)) {
                        ForEach(section.rows) { InfoRowView(row: $0) }
                    }
                }
            }
            .navigationTitle("JIT Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Report teilen")
                }
            }
            .refreshable {
                model.refreshAll()
            }
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
            .sheet(isPresented: $showShare) {
                ActivityView(items: [model.reportText()])
            }
        }
    }
}

struct StatusCard: View {
    let title: String
    let enabled: Bool
    let details: [String]

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
            Text(enabled ? "ON" : "OFF")
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

struct InfoRowView: View {
    let row: InfoRow
    @State private var showInfo = false

    var body: some View {
        HStack(alignment: .top) {
            Text(row.label)
                .foregroundColor(.secondary)
                .frame(maxWidth: 220, alignment: .leading)
            Spacer(minLength: 8)
            Text(row.value)
                .multilineTextAlignment(.trailing)
            if FlagInfo.explanation(for: row.label) != nil {
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 6)
                .alert("\(row.label)", isPresented: $showInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(FlagInfo.explanation(for: row.label) ?? "")
                }
            }
        }
        .font(.callout)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
