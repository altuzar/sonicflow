import Foundation
import AppKit

/// Phase 1 stand-in: simulates a handful of audio-producing apps with
/// realistic level-meter behavior so the UI feels alive while we build it.
@MainActor
final class MockAudioEngine: AudioEngine {
    let state = AudioState()

    private var meterTask: Task<Void, Never>?
    private var phase: Double = 0

    func start() async throws {
        seedFakeApps()
        startMeterLoop()
    }

    func stop() {
        meterTask?.cancel()
        meterTask = nil
    }

    func applyGain(_ value: Float, to appId: String) {
        state.setVolume(value, for: appId)
    }

    func setMuted(_ muted: Bool, for appId: String) {
        state.setMuted(muted, for: appId)
    }

    // MARK: - Fake data

    private func seedFakeApps() {
        let fixtures: [(id: String, name: String, category: AppCategory)] = [
            ("com.spotify.client",          "Spotify",    .media),
            ("com.google.Chrome",           "Chrome",     .browser),
            ("us.zoom.xos",                 "Zoom",       .communication),
            ("com.microsoft.teams2",        "Teams",      .communication),
            ("com.apple.Music",             "Music",      .media),
            ("com.colliderli.iina",         "IINA",       .media)
        ]

        for f in fixtures {
            let icon = NSWorkspace.shared.icon(forFile: appPath(for: f.id) ?? "/System/Applications/Music.app")
            icon.size = NSSize(width: 32, height: 32)
            let app = AudioApp(
                id: f.id,
                displayName: f.name,
                category: f.category,
                pid: nil,
                icon: icon,
                volume: 0.75,
                isMuted: false,
                isActive: f.id == "com.spotify.client" || f.id == "com.google.Chrome",
                levelMeter: 0,
                supportsVolumeControl: AppleScriptVolume.canControl(bundleID: f.id)
            )
            state.upsert(app)
        }
    }

    private func appPath(for bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
    }

    // MARK: - Meter simulation

    private func startMeterLoop() {
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                self?.tickMeters()
            }
        }
    }

    private func tickMeters() {
        phase += 0.18
        for i in state.apps.indices {
            guard state.apps[i].isActive else {
                state.apps[i].levelMeter = max(0, state.apps[i].levelMeter - 0.08)
                continue
            }
            // Pseudo-random per-app oscillation that looks like real audio.
            let seed = Double(state.apps[i].id.hashValue & 0xff) / 255.0
            let raw = abs(sin(phase + seed * .pi * 2))
            let jitter = Double.random(in: -0.08...0.08)
            let level = Float(min(1.0, max(0.0, raw * 0.85 + jitter)))
            state.apps[i].levelMeter = level * state.effectiveVolume(for: state.apps[i])
        }
    }

    // MARK: - Demo helpers (toggle activity from UI for testing)

    func toggleActivity(for appId: String) {
        guard let idx = state.apps.firstIndex(where: { $0.id == appId }) else { return }
        state.apps[idx].isActive.toggle()
    }
}
