import Foundation
import CoreAudio
import AudioToolbox

/// Wraps an AudioObjectID returned from `AudioHardwareCreateProcessTap`.
/// Owns the tap's lifetime — `dispose()` calls `AudioHardwareDestroyProcessTap`.
///
/// The tap captures the output of one specific process and silences its
/// original output path (`CATapMutedWhenTapped`) so we don't get double audio.
final class ProcessTap {
    let tapID: AudioObjectID
    let processObjectID: AudioObjectID
    let bundleID: String

    private var disposed = false

    /// Create a tap for a single process.
    /// - Parameters:
    ///   - processObjectID: AudioObjectID from the HAL process list (NOT a pid_t).
    ///   - bundleID: bundle ID, used only for logging / naming.
    init(processObjectID: AudioObjectID, bundleID: String) throws {
        self.processObjectID = processObjectID
        self.bundleID = bundleID

        // Swift's NS_REFINED_FOR_SWIFT gives us [AudioObjectID] instead of [NSNumber].
        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.name = "SonicFlow.\(bundleID)"
        description.isPrivate = true
        // The property's `getter=isMuted` confuses Swift's case folding;
        // raw value 2 = CATapMutedWhenTapped (audio routes to tap, original
        // output is silenced for the duration of the tap read).
        description.muteBehavior = CATapMuteBehavior(rawValue: 2) ?? CATapMuteBehavior(rawValue: 0)!
        description.isExclusive = false
        description.isMixdown = true

        var tapID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw ProcessTapError.creationFailed(status: status, bundleID: bundleID)
        }
        guard tapID != kAudioObjectUnknown else {
            throw ProcessTapError.invalidTapID(bundleID: bundleID)
        }
        self.tapID = tapID
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        AudioHardwareDestroyProcessTap(tapID)
    }

    deinit { dispose() }
}

enum ProcessTapError: Error, CustomStringConvertible {
    case creationFailed(status: OSStatus, bundleID: String)
    case invalidTapID(bundleID: String)

    var description: String {
        switch self {
        case let .creationFailed(status, bundleID):
            return "AudioHardwareCreateProcessTap failed for \(bundleID): OSStatus \(status) (\(fourCC(status)))"
        case let .invalidTapID(bundleID):
            return "AudioHardwareCreateProcessTap returned kAudioObjectUnknown for \(bundleID)"
        }
    }

    private func fourCC(_ status: OSStatus) -> String {
        let bytes = withUnsafeBytes(of: status.bigEndian) { Array($0) }
        let chars = bytes.map { c -> Character in
            (32...126).contains(c) ? Character(UnicodeScalar(c)) : "?"
        }
        return String(chars)
    }
}
