import Foundation
import AppKit

/// Audio process taps don't require TCC microphone permission, but reading
/// process bundle IDs / icons benefits from a couple of hooks. Phase 3 will
/// expand this with Audio capture entitlement checks if Apple tightens APIs.
@MainActor
final class PermissionsManager {
    enum Permission: String, CaseIterable {
        case accessibility   // for global hotkeys (AppKit-only path)

        var humanLabel: String {
            switch self {
            case .accessibility: return "Accessibility (for global hotkeys)"
            }
        }
    }

    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted()
        }
    }

    /// Prompts the user; returns immediately, system handles UI.
    func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            // Avoid the global-var Sendable warning by using the literal key.
            let opts: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }

    func openSystemSettings(for permission: Permission) {
        let url: URL? = {
            switch permission {
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
        }()
        if let url { NSWorkspace.shared.open(url) }
    }
}
