import SwiftUI

@main
struct SonicFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Engine selection:
    /// - default: live CoreAudio detection + gain (Phases 2 + 3)
    /// - `--mock`: 6-app fixture (handy for design / screenshots)
    @State private var engine: any AudioEngine = {
        if CommandLine.arguments.contains("--mock") {
            return MockAudioEngine()
        }
        return CoreAudioEngine()
    }()

    init() {
        // Engine must start before the menu bar opens — otherwise users with a
        // menu bar manager (Ice, Bartender) never trigger the .task hook and
        // detection/gain never come online.
        let e = engine
        Task { @MainActor in
            try? await e.start()
            if CommandLine.arguments.contains("--test-gain-cycle") {
                await Self.runGainCycleTest(engine: e)
            }
        }
    }

    /// Verification helper: every 3s, set the first detected app's volume to
    /// a different value (0.25, 1.0, 0.0, 1.0, 0.5) so logs show gain changes.
    /// Useful for asserting the IOProc is using updated values.
    @MainActor
    private static func runGainCycleTest(engine: any AudioEngine) async {
        let cycle: [(label: String, value: Float)] = [
            ("25%", 0.25), ("100%", 1.0), ("MUTE", 0.0), ("100%", 1.0), ("50%", 0.5)
        ]
        // Wait for at least one app to be detected.
        for _ in 0..<10 {
            if !engine.state.apps.isEmpty { break }
            try? await Task.sleep(for: .seconds(1))
        }
        guard let target = engine.state.apps.first(where: { $0.isActive }) else {
            FileHandle.standardError.write(Data("[GainCycle] no active app to test\n".utf8))
            return
        }
        FileHandle.standardError.write(Data("[GainCycle] cycling gain on \(target.id)\n".utf8))
        for (label, value) in cycle {
            try? await Task.sleep(for: .seconds(3))
            FileHandle.standardError.write(Data("[GainCycle] -> \(label) (\(value))\n".utf8))
            engine.applyGain(value, to: target.id)
        }
        FileHandle.standardError.write(Data("[GainCycle] done\n".utf8))
    }

    var body: some Scene {
        MenuBarExtra {
            ControlCenterView(engine: engine)
        } label: {
            MenuBarLabel(state: engine.state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The icon that lives in the menu bar. Always a waveform — single
/// consistent identity. We do not switch to a speaker glyph based on state
/// because users found it confusing.
struct MenuBarLabel: View {
    @Bindable var state: AudioState

    var body: some View {
        Image(systemName: "waveform")
            .symbolRenderingMode(.hierarchical)
            // Subtle visual cue when any app is producing output, without
            // changing the icon's silhouette.
            .foregroundStyle(state.apps.contains(where: { $0.isActive }) ? .primary : .secondary)
    }
}
