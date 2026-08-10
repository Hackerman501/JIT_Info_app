import WidgetKit
import SwiftUI

// MARK: - Shared status store

struct JITStatusEntry: TimelineEntry {
    let date: Date
    let jitOn: Bool
    let memoryExtended: Bool
    let reasons: [String]
    let lastUpdated: Date?
}

enum JITStatusStore {
    static let suiteName = "group.com.jitinfo.debugger"

    static func read() -> JITStatusEntry {
        let defaults = UserDefaults(suiteName: suiteName)
        let jitOn = defaults?.bool(forKey: "jitEnabled") ?? false
        let memoryExtended = defaults?.bool(forKey: "extendedMemory") ?? false
        let reasons = defaults?.stringArray(forKey: "jitReasons") ?? []
        let timestamp = defaults?.double(forKey: "lastUpdated")
        return JITStatusEntry(date: Date(),
                              jitOn: jitOn,
                              memoryExtended: memoryExtended,
                              reasons: reasons,
                              lastUpdated: timestamp.map { Date(timeIntervalSince1970: $0) })
    }
}

// MARK: - Provider

struct JITStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> JITStatusEntry {
        JITStatusEntry(date: Date(), jitOn: true, memoryExtended: true, reasons: ["Developer mode on"], lastUpdated: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (JITStatusEntry) -> Void) {
        completion(JITStatusStore.read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JITStatusEntry>) -> Void) {
        let entry = JITStatusStore.read()
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

struct JITStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JITStatusEntry

    var body: some View {
        if #available(iOS 16.0, *) {
            modernBody
        } else {
            mainBody
        }
    }

    @ViewBuilder
    private var modernBody: some View {
        switch family {
        case .accessoryRectangular:
            accessoryRectangular
        case .accessoryCircular:
            accessoryCircular
        case .accessoryInline:
            accessoryInline
        default:
            mainBody
        }
    }

    private var mainBody: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 10) {
                statusPill(title: "JIT", on: entry.jitOn, reasons: entry.jitOn ? entry.reasons : [])
                statusPill(title: "RAM", on: entry.memoryExtended, reasons: [])
            }
            .padding(8)
        default:
            statusPill(title: "JIT", on: entry.jitOn, reasons: entry.reasons)
                .padding(8)
        }
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(entry.jitOn ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text("JIT")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            Text(entry.jitOn ? "ON" : "OFF")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundColor(entry.jitOn ? .green : .red)
            if let first = entry.reasons.first {
                Text(first)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var accessoryCircular: some View {
        ZStack {
            Circle()
                .stroke(entry.jitOn ? Color.green : Color.red, lineWidth: 3)
            VStack(spacing: 2) {
                Circle()
                    .fill(entry.jitOn ? Color.green : Color.red)
                    .frame(width: 4, height: 4)
                Text(entry.jitOn ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
            }
        }
        .padding(4)
    }

    private var accessoryInline: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.jitOn ? "checkmark.seal.fill" : "seal")
            Text("JIT \(entry.jitOn ? "ON" : "OFF")")
        }
    }

    private func statusPill(title: String, on: Bool, reasons: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(on ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Text(on ? "ON" : "OFF")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundColor(on ? .green : .red)
            if let first = reasons.first {
                Text(first)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Widget

struct JITStatusWidget: Widget {
    let kind = "JITStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JITStatusProvider()) { entry in
            ZStack {
                Color(.systemBackground)
                JITStatusWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("JIT Status")
        .description("Shows whether JIT and extended memory are active.")
        .supportedFamilies(families)
    }

    private var families: [WidgetFamily] {
        if #available(iOS 16.0, *) {
            return [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline]
        }
        return [.systemSmall, .systemMedium]
    }
}

@main
struct JITInfoWidgetBundle: WidgetBundle {
    var body: some Widget {
        JITStatusWidget()
    }
}
