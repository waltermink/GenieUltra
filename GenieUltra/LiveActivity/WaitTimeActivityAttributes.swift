import ActivityKit
import Foundation

/// Attributes for the Magic Kingdom wait-time Live Activity.
///
/// This file must be included in BOTH the main app target and the widget extension
/// target (Xcode → select file → File Inspector → Target Membership). The base
/// struct contains only types available in both contexts. The `AttractionSnapshot`
/// convenience init from `EntityLiveData` lives in LiveActivityManager.swift
/// (main app only) to avoid making EntityLiveData a cross-target dependency.
struct WaitTimeActivityAttributes: ActivityAttributes {
    /// Dynamic content updated on each poll.
    struct ContentState: Codable, Hashable {
        var snapshots: [AttractionSnapshot]
        var lastUpdated: Date
    }

    /// Static context set when the activity starts (does not change mid-session).
    var parkName: String
}

/// Lightweight, Codable snapshot of one attraction's live state.
/// Designed to be small enough to transfer efficiently in an ActivityContent update.
struct AttractionSnapshot: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var status: String      // "OPERATING" | "DOWN" | "CLOSED"
    var waitMinutes: Int?
    var llState: String?    // "AVAILABLE" | "FINISHED" | nil
    var llReturnStart: String?
    var paState: String?
    var paReturnStart: String?

    var isOperating: Bool { status == "OPERATING" }
    var llAvailable: Bool { llState == "AVAILABLE" }
    var paAvailable: Bool { paState == "AVAILABLE" }
}
