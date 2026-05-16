import AppKit
import SwiftUI
import CoreAudio
import Darwin

/// Bridges the AppKit-only paths SwiftUI doesn't cover.
/// - Hosts the optional `--preview` floating window for visual QA
/// - Tomorrow: global hotkeys, dock icon toggling, login items.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var engine: (any AudioEngine)?
    private var previewWindow: NSWindow?
    private var debugDetector: AudioProcessDetector?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.installCrashCleanup()

        MainActor.assumeIsolated {
            // --debug: dump live detector snapshots to stderr, no UI.
            if CommandLine.arguments.contains("--debug") {
                startDebugDetector()
                return
            }

            // --preview: spin up a mock engine in a regular window so designers
            // can see a populated panel without clicking the menu bar icon
            // (useful when a menu bar manager is hiding it).
            // --preview-live: same but with the real CoreAudio engine.
            let isPreview = CommandLine.arguments.contains("--preview")
                         || CommandLine.arguments.contains("--preview-live")

            if isPreview, engine == nil {
                let liveMode = CommandLine.arguments.contains("--preview-live")
                let e: any AudioEngine = liveMode ? CoreAudioEngine() : MockAudioEngine()
                self.engine = e
                Task { @MainActor in
                    try? await e.start()
                    self.openPreviewIfRequested()
                }
            }
        }
    }

    /// Install signal handlers so SIGTERM/SIGINT/SIGHUP restore the user's
    /// default output before exit. `kill -9` (SIGKILL) can't be caught — that
    /// edge case is handled by the "skip our own aggregate" guard on next launch.
    private static func installCrashCleanup() {
        let handler: @convention(c) (Int32) -> Void = { sig in
            if let saved = AudioGainController.crashCleanupSavedDefault {
                var addr = AudioObjectPropertyAddress(
                    mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var id = saved
                _ = AudioObjectSetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &addr, 0, nil,
                    UInt32(MemoryLayout<AudioObjectID>.size),
                    &id
                )
            }
            _exit(sig)
        }
        signal(SIGTERM, handler)
        signal(SIGINT,  handler)
        signal(SIGHUP,  handler)
        signal(SIGQUIT, handler)
    }

    private func startDebugDetector() {
        let detector = AudioProcessDetector { snapshot in
            let ts = Date().formatted(.iso8601.time(includingFractionalSeconds: true))
            var lines = ["[\(ts)] HAL snapshot: \(snapshot.count) processes (R=isRunning O=output I=input)"]
            for p in snapshot.sorted(by: { ($0.bundleID ?? "") < ($1.bundleID ?? "") }) {
                let r = p.isRunning ? "R" : "·"
                let o = p.isRunningOutput ? "O" : "·"
                let i = p.isRunningInput ? "I" : "·"
                lines.append("  [\(r)\(o)\(i)] pid=\(p.pid) bundle=\(p.bundleID ?? "<none>")")
            }
            lines.append("")
            FileHandle.standardError.write(Data(lines.joined(separator: "\n").utf8))
        }
        detector.start()
        self.debugDetector = detector
    }

    @MainActor
    func openPreviewIfRequested() {
        let isPreview = CommandLine.arguments.contains("--preview")
                     || CommandLine.arguments.contains("--preview-live")
        guard isPreview, previewWindow == nil, let engine else { return }

        let host = NSHostingController(
            rootView: ControlCenterView(engine: engine)
                .padding(16)
                .frame(width: 380)
        )
        host.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Movable by background bubbles drag events past SwiftUI gestures —
        // user gets the window when they meant to drag the slider. Drag from
        // the visible title-bar traffic-light area instead.
        window.isMovableByWindowBackground = false
        window.title = "SonicFlow"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.center()
        window.makeKeyAndOrderFront(nil)

        previewWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
