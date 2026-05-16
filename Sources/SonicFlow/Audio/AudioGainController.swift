import Foundation
import CoreAudio
import AppKit

/// **Phase 3: per-app gain.**
///
/// Two IOProcs cooperate via a lock-free ring buffer:
///   • `AggregateOutputDevice` (capture half) — private aggregate with taps.
///     IOProc reads per-app tap audio, applies gain, mixes to stereo,
///     writes to ring buffer.
///   • `PlaybackDevice` (playback half) — IOProc on user's real default
///     output. Reads from ring buffer, mixes into the device's output
///     buffer (added to whatever non-tapped apps wrote).
///
/// We do NOT change the user's system default output. Apps continue to
/// target their normal output. Tapped apps' direct path is silenced via
/// `CATapMutedWhenTapped`; we route their audio back through our gain
/// pipeline. Non-tapped apps go straight through unchanged.
@MainActor
final class AudioGainController {
    enum InstallState: Equatable {
        case idle
        case running(tapCount: Int)
        case failed(reason: String)
    }

    private(set) var state: InstallState = .idle

    /// Bundle ID -> gain slot, valid while `state == .running`.
    private var slotByBundle: [String: GainSlot] = [:]
    private var taps: [ProcessTap] = []
    private var captureDevice: AggregateOutputDevice?
    private var playbackDevice: PlaybackDevice?
    private var ringBuffer: FloatRingBuffer?
    private var lastActiveBundles: Set<String> = []
    private var statsTask: Task<Void, Never>?

    // Kept for source-compat with the signal handler; no longer used since
    // we don't switch system default output. Leaving in for safety.
    nonisolated(unsafe) static var crashCleanupSavedDefault: AudioObjectID?

    func apply(active: [AudioApp], processIDByBundle: [String: AudioObjectID]) {
        let bundles = Set(active.map(\.id))
        guard bundles != lastActiveBundles else { return }
        log("active set changed: [\(bundles.sorted().joined(separator: ", "))]")
        lastActiveBundles = bundles

        teardown()

        guard !active.isEmpty else {
            state = .idle
            return
        }

        do {
            try installTaps(for: active, processIDByBundle: processIDByBundle)
            state = .running(tapCount: taps.count)
            log("Phase 3 active: \(taps.count) tap(s) + ring buffer + playback IOProc")
            startStatsReporter()
        } catch {
            state = .failed(reason: String(describing: error))
            log("Phase 3 install failed: \(error)")
            teardown()
        }
    }

    func setGain(forBundle bundleID: String, effective: Float) {
        slotByBundle[bundleID]?.setGain(effective)
    }

    func shutdown() {
        teardown()
        statsTask?.cancel()
        statsTask = nil
        state = .idle
    }

    // MARK: - Private

    private func installTaps(for active: [AudioApp], processIDByBundle: [String: AudioObjectID]) throws {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard let outputDeviceID: AudioObjectID = CAObject.read(sys, .defaultOutputDevice),
              let outputUID = CAObject.readString(outputDeviceID, .deviceUID) else {
            throw AggregateError.noDefaultOutputDevice
        }
        log("default output device: \(outputDeviceID) UID=\(outputUID)")

        var newTaps: [ProcessTap] = []
        var bundleOrder: [String] = []
        for app in active {
            guard let pobjID = processIDByBundle[app.id] else { continue }
            do {
                let tap = try ProcessTap(processObjectID: pobjID, bundleID: app.id)
                newTaps.append(tap)
                bundleOrder.append(app.id)
                log("created tap for \(app.id) → tapID=\(tap.tapID)")
            } catch {
                log("Tap creation failed for \(app.id): \(error). Skipping.")
            }
        }
        guard !newTaps.isEmpty else {
            throw AggregateError.creationFailed(status: kAudioHardwareUnsupportedOperationError)
        }

        // Ring buffer: ~85ms of audio @ 48kHz stereo gives plenty of slack.
        let ring = FloatRingBuffer(requestedCapacity: 8192)

        let capture = try AggregateOutputDevice(
            outputDeviceUID: outputUID,
            taps: newTaps,
            ringBuffer: ring
        )
        try capture.start()
        log("capture device started: aggID=\(capture.aggregateID)")

        let playback = PlaybackDevice(deviceID: outputDeviceID, ringBuffer: ring)
        try playback.start()
        log("playback device started on deviceID=\(outputDeviceID)")

        self.taps = newTaps
        self.captureDevice = capture
        self.playbackDevice = playback
        self.ringBuffer = ring
        self.slotByBundle = Dictionary(uniqueKeysWithValues: zip(bundleOrder, capture.gainSlots))
    }

    private func teardown() {
        playbackDevice?.stop()
        playbackDevice = nil
        captureDevice?.stop()
        captureDevice = nil
        ringBuffer?.reset()
        ringBuffer = nil
        taps.forEach { $0.dispose() }
        taps.removeAll()
        slotByBundle.removeAll()
    }

    /// Stats reporter — opt-in via --debug.
    private func startStatsReporter() {
        guard CommandLine.arguments.contains("--debug")
           || CommandLine.arguments.contains("--test-gain-cycle") else { return }
        statsTask?.cancel()
        let cap = captureDevice
        let pb = playbackDevice
        let ring = ringBuffer
        let logFn = self.log
        var lastIn: UInt64 = 0
        var lastOut: UInt64 = 0
        var lastUnder: UInt64 = 0
        statsTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let cap, let pb, let ring, let self else { return }
                let inDelta = cap.framesReceived &- lastIn
                let outDelta = pb.samplesFromRing &- lastOut
                let underDelta = pb.underrunSamples &- lastUnder
                lastIn = cap.framesReceived
                lastOut = pb.samplesFromRing
                lastUnder = pb.underrunSamples
                let gainSummary = self.slotByBundle
                    .map { "\($0.key.suffix(20))=\(String(format: "%.2f", $0.value.gain))" }
                    .joined(separator: ", ")
                logFn("stats: tap=\(inDelta) ring=\(ring.fillLevel) playback=\(outDelta) underrun=\(underDelta) /2s | \(gainSummary)")
            }
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[GainController] \(message)\n".utf8))
    }
}
