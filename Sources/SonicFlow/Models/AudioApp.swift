import Foundation
import AppKit

/// Category drives ducking behavior. Communication apps duck everything else
/// when they go active.
enum AppCategory: String, Codable, Sendable {
    case communication
    case media
    case browser
    case game
    case other
}

/// One audio-producing application as known to SonicFlow.
/// Identified by bundle ID; PIDs are unstable (apps relaunch).
///
/// Not Sendable because `NSImage` isn't. The whole graph is owned by the
/// main actor (`AudioState`), so cross-actor passing isn't a concern.
struct AudioApp: Identifiable, Equatable {
    let id: String              // bundle identifier
    var displayName: String
    var category: AppCategory
    var pid: pid_t?             // current pid, if running
    var icon: NSImage?
    var volume: Float           // 0.0 ... 1.0, user-set
    var isMuted: Bool
    var isActive: Bool          // currently producing audio
    var levelMeter: Float       // 0.0 ... 1.0, instantaneous output level

    /// True if SonicFlow can actually control this app's volume right now.
    /// False means the slider/mute should be disabled with an explanatory
    /// indicator (Phase 3 routing is the proper fix; until then we're honest
    /// about which apps we can drive).
    var supportsVolumeControl: Bool

    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.id == rhs.id &&
        lhs.volume == rhs.volume &&
        lhs.isMuted == rhs.isMuted &&
        lhs.isActive == rhs.isActive &&
        lhs.levelMeter == rhs.levelMeter &&
        lhs.pid == rhs.pid &&
        lhs.supportsVolumeControl == rhs.supportsVolumeControl
    }
}
