import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = DiagnosticsModel()

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

                ForEach(model.visibleSections) { section in
                    Section(header: Text(section.title)) {
                        ForEach(section.rows) { InfoRowView(row: $0) }
                    }
                }
            }
            .navigationTitle("JIT Info")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                model.refreshAll()
            }
            .task {
                model.start()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    model.refreshAll()
                }
            }
            .onDisappear {
                Task { @MainActor in
                    model.stop()
                }
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

    var body: some View {
        HStack(alignment: .top) {
            Text(row.label)
                .foregroundColor(.secondary)
                .frame(maxWidth: 220, alignment: .leading)
            Spacer(minLength: 8)
            Text(row.value)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
