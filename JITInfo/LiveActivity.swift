import ActivityKit
import Foundation
import UIKit

// MARK: - Attributes

struct JITLiveAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var jitOn: Bool
        var extendedMemory: Bool
        var reason: String?
        var updatedAt: Date
    }

    var deviceName: String
}

// MARK: - Manager

@MainActor
enum LiveActivityManager {

    private static var lastJitOn: Bool?
    private static var lastExtendedMemory: Bool?
    private static var lastReason: String?

    static var isActive: Bool {
        !Activity<JITLiveAttributes>.activities.isEmpty
    }

    static func update(jitOn: Bool, extendedMemory: Bool, reason: String?) {
        let changed = lastJitOn != jitOn || lastExtendedMemory != extendedMemory || lastReason != reason
        lastJitOn = jitOn
        lastExtendedMemory = extendedMemory
        lastReason = reason
        guard changed else { return }

        let state = JITLiveAttributes.ContentState(jitOn: jitOn,
                                                   extendedMemory: extendedMemory,
                                                   reason: reason,
                                                   updatedAt: Date())
        if let activity = Activity<JITLiveAttributes>.activities.first {
            Task {
                await activity.update(using: state)
            }
        } else {
            start(state: state)
        }
    }

    static func startIfNeeded() {
        guard Activity<JITLiveAttributes>.activities.isEmpty else { return }
        start(state: JITLiveAttributes.ContentState(jitOn: false,
                                                     extendedMemory: false,
                                                     reason: nil,
                                                     updatedAt: Date()))
    }

    private static func start(state: JITLiveAttributes.ContentState) {
        let attributes = JITLiveAttributes(deviceName: UIDevice.current.name)
        do {
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: state, staleDate: nil)
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } else {
                _ = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
            }
        } catch {
            // Live Activities can be disabled by the user or unavailable on the device.
        }
    }

    static func stop() {
        lastJitOn = nil
        lastExtendedMemory = nil
        lastReason = nil
        for activity in Activity<JITLiveAttributes>.activities {
            Task {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
