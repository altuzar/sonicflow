import Foundation

/// Abstract audio engine: detects audio-producing apps + applies per-app gain.
///
/// Phase 1 uses `MockAudioEngine`. Phase 2 will detect real processes via
/// `AudioObjectGetPropertyData(kAudioHardwarePropertyProcessObjectList)`.
/// Phase 3 will route audio through `AudioHardwareCreateProcessTap` and
/// apply gain per process.
@MainActor
protocol AudioEngine: AnyObject {
    var state: AudioState { get }

    func start() async throws
    func stop()

    func applyGain(_ value: Float, to appId: String)
    func setMuted(_ muted: Bool, for appId: String)

    /// Re-evaluate the effective gain for every app and push to the realtime
    /// gain table. Called by the UI after master volume / ducking changes.
    func resyncAllGains()
}

extension AudioEngine {
    func resyncAllGains() {
        for app in state.apps {
            applyGain(app.volume, to: app.id)
        }
    }
}
