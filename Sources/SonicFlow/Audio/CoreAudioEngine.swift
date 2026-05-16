import Foundation
import AppKit
import CoreAudio

/// Phase 3 engine: real process detection AND real per-app gain via CoreAudio
/// Process Taps + a private aggregate device.
///
/// Phase 1 (mock) → Phase 2 (detection) → Phase 3 (gain) all live behind the
/// same `AudioEngine` protocol so the UI is unchanged across phases.
@MainActor
final class CoreAudioEngine: AudioEngine {
    let state = AudioState()
    let gainController = AudioGainController()

    /// Phase 3 (per-app tap → ring buffer → playback) is on by default.
    /// Pass `--no-gain` to disable for debugging Phase 2 detection in isolation.
    private let gainEnabled = !CommandLine.arguments.contains("--no-gain")

    private var detector: AudioProcessDetector?
    private var systemVolumeListener: SystemVolumeListener?
    private var pulseTask: Task<Void, Never>?
    private var externalVolumePollTask: Task<Void, Never>?
    private var pulsePhase: Double = 0

    /// True while we're WRITING the system volume from a UI slider drag.
    /// Suppresses the listener echo so we don't fight the user's input.
    private var suppressSystemVolumeEcho = false

    /// HAL process-object-ID by bundle ID — needed to feed the gain controller.
    private var processIDByBundle: [String: AudioObjectID] = [:]

    /// Track which scriptable apps we've already probed so we don't fire
    /// the permission dialog repeatedly.
    private var probedBundles: Set<String> = []

    /// Wall-clock time of the most recent user-initiated volume write per
    /// bundle. While < 1.5s old, the external poll skips that app so its
    /// stale reads can't overwrite the user's drag.
    private var lastUserWriteTime: [String: Date] = [:]

    func start() async throws {
        let det = AudioProcessDetector { [weak self] processes in
            Task { @MainActor [weak self] in
                self?.merge(processes)
            }
        }
        self.detector = det
        det.start()

        // Sync master slider with macOS volume keys.
        let volListener = SystemVolumeListener { [weak self] sysVol in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only update if the values diverge meaningfully — prevents
                // feedback loops when our own slider write echoes back.
                if abs(self.state.masterVolume - sysVol) > 0.01 {
                    self.state.masterVolume = sysVol
                }
            }
        }
        self.systemVolumeListener = volListener
        volListener.start()

        startPulseLoop()
        startExternalVolumePoll()
    }

    /// Poll the actual current volume of scriptable apps every 500ms so the
    /// UI tracks volume changes made INSIDE those apps (e.g. user moved
    /// Music's own volume slider). Without this, our slider stays stale.
    private func startExternalVolumePoll() {
        externalVolumePollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }

                // Snapshot bundle IDs we'd want to query — must be on main.
                let scriptable = self.state.apps
                    .filter { AppleScriptVolume.canControl(bundleID: $0.id) }
                    .map(\.id)

                for bundleID in scriptable {
                    // Skip apps the user just touched — let our write settle
                    // before we trust an external read.
                    if let lastWrite = self.lastUserWriteTime[bundleID],
                       Date().timeIntervalSince(lastWrite) < 1.5 {
                        continue
                    }

                    let observed = await Task.detached(priority: .background) {
                        AppleScriptVolume.getVolume(for: bundleID)
                    }.value

                    guard let observed else { continue }
                    guard let app = self.state.apps.first(where: { $0.id == bundleID }) else { continue }

                    if abs(app.volume - observed) > 0.015 {
                        self.state.setVolume(observed, for: bundleID)
                    }
                }
            }
        }
    }

    func stop() {
        detector?.stop()
        detector = nil
        systemVolumeListener?.stop()
        systemVolumeListener = nil
        pulseTask?.cancel()
        pulseTask = nil
        externalVolumePollTask?.cancel()
        externalVolumePollTask = nil
        gainController.shutdown()
    }

    func applyGain(_ value: Float, to appId: String) {
        state.setVolume(value, for: appId)
        pushGain(for: appId)
        // Block external-volume poll for this bundle briefly so a stale read
        // can't undo the user's drag before our AppleScript write lands.
        lastUserWriteTime[appId] = Date()

        if AppleScriptVolume.canControl(bundleID: appId) {
            AppleScriptVolume.setVolume(value, for: appId)
        }
    }

    func setMuted(_ muted: Bool, for appId: String) {
        state.setMuted(muted, for: appId)
        pushGain(for: appId)
        lastUserWriteTime[appId] = Date()
        if AppleScriptVolume.canControl(bundleID: appId),
           let app = state.apps.first(where: { $0.id == appId }) {
            AppleScriptVolume.setMuted(muted, for: appId, restoreTo: app.volume)
        }
    }

    func resyncAllGains() {
        for app in state.apps { pushGain(for: app.id) }
        // Don't re-push AppleScript here — master volume is handled by
        // system volume, per-app volume is independent.
    }

    // MARK: - Reconciliation

    private func merge(_ processes: [AudioProcess]) {
        var byBundle: [String: AudioProcess] = [:]
        for p in processes {
            guard let b = p.bundleID, !b.isEmpty else { continue }
            byBundle[b] = p
        }

        // Drop apps that left the HAL.
        let toRemove = state.apps.map(\.id).filter { byBundle[$0] == nil }
        for id in toRemove {
            state.remove(id: id)
            processIDByBundle.removeValue(forKey: id)
        }

        // Upsert each known process.
        for (bundleID, p) in byBundle {
            let existing = state.apps.first { $0.id == bundleID }
            // The detector merges audio sub-processes into the parent bundle,
            // but `p.pid` still points at the audio-producing helper (which
            // is correct for tap creation). For DISPLAY purposes we want the
            // main app — find any running instance with the parent bundle ID
            // and a "regular" activation policy (i.e. has a dock entry).
            let parentApp = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.activationPolicy == .regular })
            let helperApp = NSRunningApplication(processIdentifier: p.pid)
            let running = parentApp ?? helperApp
            let category = AppCategorizer.category(for: bundleID)

            // Only output-running counts as "playing audio". Earlier we treated
            // any running stream (incl. mic input) as active for comm apps so
            // ducking would fire during calls — but that incorrectly fires for
            // idle Slack/Zoom that just have their mic stream registered.
            // Comm apps trigger ducking only when they're actually outputting
            // audio (someone's voice coming through).
            let active = p.isRunningOutput

            if existing == nil && !active {
                continue
            }

            processIDByBundle[bundleID] = p.objectID

            // Probe AppleScript permission once per scriptable app — this
            // also TRIGGERS macOS's permission prompt the first time, so the
            // user gets a clear "Allow / Don't Allow" dialog instead of
            // silent failure when they later move a slider.
            if existing == nil,
               AppleScriptVolume.canControl(bundleID: bundleID),
               !probedBundles.contains(bundleID) {
                probedBundles.insert(bundleID)
                Task.detached(priority: .background) {
                    _ = AppleScriptVolume.probe(bundleID: bundleID)
                }
            }

            // With Phase 3 enabled, every detected app gets per-app gain via
            // the tap pipeline. AppleScript is still preferred when available
            // (the in-app slider also updates) but Phase 3 covers everything.
            let supports = gainEnabled || AppleScriptVolume.canControl(bundleID: bundleID)

            let app = AudioApp(
                id: bundleID,
                displayName: existing?.displayName
                    ?? running?.localizedName
                    ?? Self.fallbackName(for: bundleID),
                category: category,
                pid: p.pid,
                icon: existing?.icon ?? running?.icon ?? Self.iconForBundle(bundleID),
                volume: existing?.volume ?? 1.0,
                isMuted: existing?.isMuted ?? false,
                isActive: active,
                levelMeter: existing?.levelMeter ?? 0,
                supportsVolumeControl: supports
            )
            state.upsert(app)
        }

        // Reconcile gain controller to the new active set — only if Phase 3
        // gain is opt-in. Without this, taps would silence the original output
        // and audibility would depend on our routing being correct.
        if gainEnabled {
            let activeApps = state.apps.filter { $0.isActive }
            gainController.apply(active: activeApps, processIDByBundle: processIDByBundle)
            for app in activeApps {
                pushGain(for: app.id)
            }
        }
    }

    /// Compute master * volume * ducking, push to the realtime gain table.
    private func pushGain(for bundleID: String) {
        guard let app = state.apps.first(where: { $0.id == bundleID }) else { return }
        let effective = state.effectiveVolume(for: app)
        gainController.setGain(forBundle: bundleID, effective: effective)
    }

    private static func fallbackName(for bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init)?.capitalized ?? bundleID
    }

    private static func iconForBundle(_ bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    // MARK: - Soft-pulse meter (until Phase 3 polish wires real RMS)

    /// Phase 3 step 1 doesn't yet sample the IOProc buffers for visual meters;
    /// we keep the soft pulse so the UI feels alive. The next polish step is
    /// to compute RMS in the IOProc and publish via a lock-free ring.
    private func startPulseLoop() {
        pulseTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.tickPulse()
            }
        }
    }

    private func tickPulse() {
        let hasActive = state.apps.contains(where: { $0.isActive })
        let hasMovingMeter = state.apps.contains(where: { $0.levelMeter > 0.001 })
        guard hasActive || hasMovingMeter else { return }

        pulsePhase += 0.4
        for i in state.apps.indices {
            if state.apps[i].isActive {
                let seed = Double(state.apps[i].id.hashValue & 0xff) / 255.0
                let raw = abs(sin(pulsePhase + seed * .pi * 2))
                state.apps[i].levelMeter = Float(raw * 0.5) * state.effectiveVolume(for: state.apps[i])
            } else if state.apps[i].levelMeter > 0.001 {
                state.apps[i].levelMeter = max(0, state.apps[i].levelMeter - 0.05)
            }
        }
    }
}
