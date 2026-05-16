import Foundation
import CoreAudio

/// Listens to the system's default-output-device volume scalar and pushes
/// updates to a callback. Lets the master slider follow the macOS volume
/// keys (F11/F12 / Touch Bar / Control Center).
///
/// Tracks two things together:
///  1. The default output DEVICE may change (headphones plug/unplug).
///  2. The CURRENT default device's volume may change.
/// We re-attach the volume listener whenever the device changes.
final class SystemVolumeListener: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sonicflow.volume-listener", qos: .userInitiated)
    private let onChange: @Sendable (Float) -> Void

    private var defaultDeviceListener: ListenerHandle?
    private var volumeListener: ListenerHandle?
    private var currentDevice: AudioObjectID?

    init(onChange: @escaping @Sendable (Float) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            attachDefaultDeviceListener()
            rebindVolumeListener()
            emitCurrentVolume()
        }
    }

    func stop() {
        queue.async { [self] in
            defaultDeviceListener?.dispose()
            defaultDeviceListener = nil
            volumeListener?.dispose()
            volumeListener = nil
            currentDevice = nil
        }
    }

    // MARK: - Private (queue-isolated)

    private func attachDefaultDeviceListener() {
        defaultDeviceListener = CAObject.addListener(
            on: AudioObjectID(kAudioObjectSystemObject),
            selector: .defaultOutputDevice,
            queue: queue,
            handler: { [self] in
                rebindVolumeListener()
                emitCurrentVolume()
            }
        )
    }

    private func rebindVolumeListener() {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard let device: AudioObjectID = CAObject.read(sys, .defaultOutputDevice) else { return }
        guard device != currentDevice else { return }
        currentDevice = device

        volumeListener?.dispose()
        // VirtualMainVolume lives on the output scope, not global —
        // CAObject.addListener uses global, so we install directly.
        let volumeSelector: AudioObjectPropertySelector = CAFourCC.make("volm")
        var address = AudioObjectPropertyAddress(
            mSelector: volumeSelector,
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeOutput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let block: AudioObjectPropertyListenerBlock = { [self] _, _ in emitCurrentVolume() }
        let status = AudioObjectAddPropertyListenerBlock(device, &address, queue, block)
        guard status == noErr else {
            FileHandle.standardError.write(Data("[SystemVolumeListener] failed to attach: \(status)\n".utf8))
            return
        }
        volumeListener = ListenerHandle(object: device, address: address, queue: queue, block: block)
    }

    private func emitCurrentVolume() {
        guard let device = currentDevice else { return }
        let volumeSelector: AudioObjectPropertySelector = CAFourCC.make("volm")
        var addr = AudioObjectPropertyAddress(
            mSelector: volumeSelector,
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeOutput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        guard status == noErr else { return }
        let v = max(0, min(1, value))
        onChange(v)
    }
}
