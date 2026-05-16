import AppKit

/// Trackpad haptics. NSHapticFeedbackManager only fires when the user is
/// actively touching the trackpad — safely no-op otherwise.
enum HapticFeedback {
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer
            .perform(.alignment, performanceTime: .now)
    }
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer
            .perform(.levelChange, performanceTime: .now)
    }
}
