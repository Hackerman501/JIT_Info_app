import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Attributes (must match the app target)

struct JITLiveAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var jitOn: Bool
        var extendedMemory: Bool
        var reason: String?
        var updatedAt: Date
    }

    var deviceName: String
}

// MARK: - Lock screen / banner

struct JITLiveLockScreenView: View {
    let context: ActivityViewContext<JITLiveAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.fill")
                    .font(.callout)
                Text("JIT Info")
                    .font(.headline)
                Spacer()
                if #available(iOS 16.2, *) {
                    if context.isStale {
                        Text("Stale")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                statusItem(title: "JIT",
                           on: context.state.jitOn,
                           color: context.state.jitOn ? .green : .red)
                statusItem(title: "Extended Memory",
                           on: context.state.extendedMemory,
                           color: context.state.extendedMemory ? .green : .red)
            }
            if let reason = context.state.reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(context.attributes.deviceName)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusItem(title: String, on: Bool, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(on ? "ON" : "OFF")
                .font(.caption.weight(.heavy))
                .foregroundColor(color)
        }
    }
}

// MARK: - Activity widget

struct JITLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JITLiveAttributes.self) { context in
            JITLiveLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "externaldrive.fill")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.jitOn ? "JIT ON" : "JIT OFF")
                        .font(.callout.weight(.heavy))
                        .foregroundColor(context.state.jitOn ? .green : .red)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        statusItem(title: "JIT",
                                   on: context.state.jitOn,
                                   color: context.state.jitOn ? .green : .red)
                        statusItem(title: "RAM",
                                   on: context.state.extendedMemory,
                                   color: context.state.extendedMemory ? .green : .red)
                    }
                }
            } compactLeading: {
                Image(systemName: "externaldrive.fill")
            } compactTrailing: {
                Image(systemName: context.state.jitOn ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(context.state.jitOn ? .green : .red)
            } minimal: {
                Image(systemName: context.state.jitOn ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(context.state.jitOn ? .green : .red)
            }
        }
    }

    private func statusItem(title: String, on: Bool, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text(on ? "ON" : "OFF")
                .font(.caption2.weight(.heavy))
                .foregroundColor(color)
        }
    }
}
