import Foundation
import CoreAudio
import AppKit

/// One audio process as reported by the HAL.
struct AudioProcess: Equatable, Sendable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    /// True when the process currently has any audio stream active.
    let isRunning: Bool
    /// True when the process currently has an output stream active in the HAL.
    let isRunningOutput: Bool
    /// True when the process currently has an input stream active in the HAL.
    let isRunningInput: Bool
}

/// Detects audio-producing processes via the CoreAudio HAL "process object"
/// API (macOS 14.2+). Pure observation — no audio is captured, no purple dot.
///
/// Updates are pushed via the init-supplied callback whenever:
///  - the system process list changes (app launches/quits)
///  - any tracked process's output-running flag flips
///
/// Thread model: all mutable state lives on `queue` (a private serial queue).
/// The callback fires on the main queue. Hence `@unchecked Sendable`.
final class AudioProcessDetector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sonicflow.audio-detector", qos: .userInitiated)
    private let onChange: @Sendable ([AudioProcess]) -> Void

    /// Listener on the system object for process-list mutations.
    private var systemListener: ListenerHandle?
    /// Per-process listeners keyed by AudioObjectID.
    private var perProcessListeners: [AudioObjectID: ListenerHandle] = [:]

    private var lastSnapshot: [AudioProcess] = []

    init(onChange: @escaping @Sendable ([AudioProcess]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            installSystemListener()
            refresh()
            startPoll()
        }
    }

    /// HAL property listeners sometimes miss state transitions (Music going
    /// from paused → playing can take 30+ seconds before piro flips). A
    /// low-frequency poll closes that gap without the cost of full polling.
    private var pollTimer: DispatchSourceTimer?
    private func startPoll() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [self] in refresh() }
        timer.resume()
        pollTimer = timer
    }

    func stop() {
        queue.async { [self] in
            pollTimer?.cancel()
            pollTimer = nil
            systemListener?.dispose()
            systemListener = nil
            for (_, h) in perProcessListeners { h.dispose() }
            perProcessListeners.removeAll()
        }
    }

    // MARK: - Internal (all called on `queue`)

    private func installSystemListener() {
        systemListener = CAObject.addListener(
            on: AudioObjectID(kAudioObjectSystemObject),
            selector: .processObjectList,
            queue: queue
        ) { [self] in
            refresh()
        }
    }

    /// Pull the current process list, attach listeners for any new ones,
    /// drop listeners for any that disappeared, and emit a fresh snapshot.
    private func refresh() {
        dispatchPrecondition(condition: .onQueue(queue))

        let processIDs: [AudioObjectID] = CAObject.readArray(
            AudioObjectID(kAudioObjectSystemObject),
            .processObjectList
        )

        let known = Set(perProcessListeners.keys)
        let current = Set(processIDs)

        // New processes: subscribe to their isRunningOutput flag.
        for id in current.subtracting(known) {
            if let h = CAObject.addListener(
                on: id,
                selector: .processIsRunningOutput,
                queue: queue,
                handler: { [self] in refresh() }
            ) {
                perProcessListeners[id] = h
            }
        }

        // Departed processes: drop listeners.
        for id in known.subtracting(current) {
            perProcessListeners[id]?.dispose()
            perProcessListeners.removeValue(forKey: id)
        }

        // Build the snapshot.
        var processes: [AudioProcess] = []
        processes.reserveCapacity(processIDs.count)
        for id in processIDs {
            let pid: pid_t = (CAObject.read(id, .processPID) as Int32?) ?? -1
            let bundleID: String? = CAObject.readString(id, .processBundleID)
            let isRunning: UInt32 = CAObject.read(id, .processIsRunning) ?? 0
            let runningOut: UInt32 = CAObject.read(id, .processIsRunningOutput) ?? 0
            let runningIn:  UInt32 = CAObject.read(id, .processIsRunningInput) ?? 0
            processes.append(AudioProcess(
                objectID: id,
                pid: pid,
                bundleID: bundleID,
                isRunning: isRunning != 0,
                isRunningOutput: runningOut != 0,
                isRunningInput: runningIn != 0
            ))
        }

        // De-dupe: occasionally the HAL lists the same bundle twice (helper
        // procs inheriting the parent's bundle ID). Keep the active one.
        let deduped = Self.dedupe(processes)

        guard deduped != lastSnapshot else { return }
        lastSnapshot = deduped

        let payload = deduped
        let cb = onChange
        DispatchQueue.main.async {
            cb(payload)
        }
    }

    /// Collapse helper processes into their parent app, merging activity
    /// flags. Many apps (Chrome, Slack, Discord, Electron, …) put audio
    /// in a sub-process whose bundle is e.g. `com.google.Chrome.helper
    /// .AudioService`. We map that to `com.google.Chrome`, take the OR
    /// of all activity flags, and KEEP the helper's `objectID` / `pid`
    /// when it's the one producing output — that's the process the tap
    /// needs to target.
    private static func dedupe(_ processes: [AudioProcess]) -> [AudioProcess] {
        var byBundle: [String: AudioProcess] = [:]
        for p in processes {
            guard let raw = p.bundleID, !raw.isEmpty else { continue }
            guard !systemBundlesToHide.contains(where: { raw.hasPrefix($0) }) else { continue }

            // Strip helper suffix so multiple sub-processes collapse onto
            // the user-facing parent. Bundle IDs we never recognise (no
            // helper suffix) pass through unchanged.
            let parent = parentBundle(of: raw)

            if let existing = byBundle[parent] {
                // Prefer the entry currently producing output, then any
                // running entry, so the merged record points at the audio
                // sub-process for tap creation.
                let pickNew = (!existing.isRunningOutput && p.isRunningOutput)
                           || (!existing.isRunning && p.isRunning && !existing.isRunningOutput)
                let base = pickNew ? p : existing
                byBundle[parent] = AudioProcess(
                    objectID: base.objectID,
                    pid: base.pid,
                    bundleID: parent,
                    isRunning:       existing.isRunning       || p.isRunning,
                    isRunningOutput: existing.isRunningOutput || p.isRunningOutput,
                    isRunningInput:  existing.isRunningInput  || p.isRunningInput
                )
            } else {
                byBundle[parent] = AudioProcess(
                    objectID: p.objectID,
                    pid: p.pid,
                    bundleID: parent,
                    isRunning: p.isRunning,
                    isRunningOutput: p.isRunningOutput,
                    isRunningInput: p.isRunningInput
                )
            }
        }
        return Array(byBundle.values)
    }

    /// Strip helper / renderer / gpu suffixes so sub-processes resolve to
    /// the user-visible parent bundle. Case-insensitive matching covers
    /// Apple's `.helper`, Chromium's `Helper (GPU)` etc.
    ///
    /// Examples:
    ///   com.google.Chrome.helper.AudioService → com.google.Chrome
    ///   com.google.Chrome.helper.GPU          → com.google.Chrome
    ///   com.tinyspeck.slackmacgap.helper      → com.tinyspeck.slackmacgap
    ///   org.mozilla.firefox.GeckoMediaPlugin  → org.mozilla.firefox
    ///   com.hnc.Discord.helper.Renderer       → com.hnc.Discord
    ///   us.zoom.xos                           → us.zoom.xos          (unchanged)
    private static func parentBundle(of bundleID: String) -> String {
        // Markers indicating the start of a helper-suffix. Order matters —
        // longest first so we don't strip too aggressively.
        let suffixMarkers = [
            ".helper",
            ".Helper",
            ".gpu",
            ".GPU",
            ".renderer",
            ".Renderer",
            ".GeckoMediaPlugin",
            ".plugin-container",
            ".AudioService",
            ".webcontent",
            ".WebContent"
        ]
        for marker in suffixMarkers {
            if let range = bundleID.range(of: marker) {
                return String(bundleID[..<range.lowerBound])
            }
        }
        return bundleID
    }

    /// Bundle ID prefixes of system processes the user can't meaningfully
    /// volume-control. We hide them from snapshots entirely.
    private static let systemBundlesToHide: [String] = [
        "com.apple.audiomxd",
        "com.apple.coreaudiod",
        "com.apple.mediaremoted",
        "com.apple.assistantd",
        "com.apple.SiriNCService",
        "com.apple.CoreSpeech",
        "com.apple.accessibility",
        "com.apple.universalaccessd",
        "com.apple.controlcenter",
        "com.apple.WebKit.GPU",
        "com.apple.cmio",
        "com.apple.PowerChime",
        "com.apple.loginwindow",
        "com.apple.AirPlayXPCHelper",
        "com.apple.TelephonyUtilities",
        "com.apple.avconferenced",
        "com.logi.cp-dev-mgr",
        "com.logitech",
        "systemsoundserverd",
        "com.sonicflow.app" // we don't need to control ourselves
    ]
}
