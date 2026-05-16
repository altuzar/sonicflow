import CoreAudio
import Foundation

// MARK: - FourCC helpers

/// FourCC constants from the CoreAudio "AudioObject Process" API surface
/// added in macOS 14.0 / 14.2 / 14.4. We define the codes ourselves so the
/// build doesn't depend on whichever Swift overlay version is in the SDK.
enum CAFourCC {
    static func make(_ s: String) -> UInt32 {
        precondition(s.count == 4, "FourCC must be exactly 4 ASCII chars")
        var result: UInt32 = 0
        for byte in s.utf8 { result = (result << 8) | UInt32(byte) }
        return result
    }
}

extension AudioObjectPropertySelector {
    // System-wide selectors.
    static let defaultOutputDevice: AudioObjectPropertySelector =
        CAFourCC.make("dOut")
    static let deviceUID: AudioObjectPropertySelector =
        CAFourCC.make("uid ")
    static let streamPhysicalFormat: AudioObjectPropertySelector =
        CAFourCC.make("pft ")

    // Tap-specific selectors (from AudioHardware.h).
    static let tapUID: AudioObjectPropertySelector =
        CAFourCC.make("tuid")
    static let tapDescription: AudioObjectPropertySelector =
        CAFourCC.make("tdsc")
    static let tapFormat: AudioObjectPropertySelector =
        CAFourCC.make("tfmt")

    // kAudioHardwarePropertyProcessObjectList — array of AudioObjectID, one per process
    // known to the audio HAL (whether running output or not).
    static let processObjectList: AudioObjectPropertySelector =
        CAFourCC.make("prs#")

    // kAudioHardwarePropertyTranslatePIDToProcessObject — translate a pid_t
    // (UInt32, in qualifier) into the corresponding AudioObjectID.
    static let translatePIDToProcessObject: AudioObjectPropertySelector =
        CAFourCC.make("id2p")

    // Per-process properties (AudioObjectID = process object).
    // FourCCs verified against MacOSX15.sdk/.../CoreAudio/AudioHardware.h.
    static let processPID:               AudioObjectPropertySelector = CAFourCC.make("ppid")
    static let processBundleID:          AudioObjectPropertySelector = CAFourCC.make("pbid")
    static let processDevices:           AudioObjectPropertySelector = CAFourCC.make("pdv#")
    static let processIsRunning:         AudioObjectPropertySelector = CAFourCC.make("pir?")
    static let processIsRunningInput:    AudioObjectPropertySelector = CAFourCC.make("piri")
    static let processIsRunningOutput:   AudioObjectPropertySelector = CAFourCC.make("piro")
}

// MARK: - Property address helpers

extension AudioObjectPropertyAddress {
    /// Standard global/main address with the given selector.
    static func global(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

// MARK: - Typed read helpers

enum CAObject {
    /// Read a single value of type T from a property. Returns nil on error.
    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress.global(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }

        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, value)
        guard status == noErr else { return nil }
        return value.pointee
    }

    /// Read a CFString-typed property as a Swift String.
    static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress.global(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cfStr: CFString? = nil

        let status = withUnsafeMutablePointer(to: &cfStr) { ptr in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let cfStr else { return nil }
        return cfStr as String
    }

    /// Read a variable-length array of UInt32-sized elements (e.g. AudioObjectID[]).
    static func readArray<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, of: T.Type = T.self) -> [T] {
        var address = AudioObjectPropertyAddress.global(selector)
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<T>.size
        let buffer = UnsafeMutableBufferPointer<T>.allocate(capacity: count)
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!) == noErr else {
            return []
        }
        return Array(buffer.prefix(Int(size) / MemoryLayout<T>.size))
    }

    /// Add a property listener. Returns a handle that unregisters on `dispose`.
    static func addListener(
        on object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        queue: DispatchQueue,
        handler: @escaping () -> Void
    ) -> ListenerHandle? {
        var address = AudioObjectPropertyAddress.global(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }

        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
        guard status == noErr else { return nil }

        return ListenerHandle(object: object, address: address, queue: queue, block: block)
    }
}

/// RAII-style handle that removes its listener on dispose.
final class ListenerHandle {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock
    private var disposed = false

    init(object: AudioObjectID, address: AudioObjectPropertyAddress, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) {
        self.object = object
        self.address = address
        self.queue = queue
        self.block = block
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }

    deinit { dispose() }
}
