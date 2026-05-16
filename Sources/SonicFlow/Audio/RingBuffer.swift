import Foundation

/// Wait-free single-producer single-consumer float ring buffer.
///
/// One thread writes (audio capture IOProc), one thread reads (audio
/// playback IOProc). On arm64/x86_64 with 8-byte aligned UInt64, the
/// load/store of head/tail is atomic at the CPU level — no locks needed.
///
/// Capacity is rounded up to a power of two so `index & (cap-1)` replaces
/// the modulo for cheap wraparound in the realtime path.
final class FloatRingBuffer: @unchecked Sendable {
    private let buffer: UnsafeMutableBufferPointer<Float>
    private let capacity: Int          // power of two
    private let mask: UInt64

    /// Writer's next free index (monotonically increasing). Single producer.
    private let headPtr: UnsafeMutablePointer<UInt64>
    /// Reader's next-to-read index (monotonically increasing). Single consumer.
    private let tailPtr: UnsafeMutablePointer<UInt64>

    /// `capacity` is rounded UP to the next power of two.
    init(requestedCapacity: Int) {
        var cap = 1
        while cap < max(2, requestedCapacity) { cap <<= 1 }
        self.capacity = cap
        self.mask = UInt64(cap - 1)
        self.buffer = .allocate(capacity: cap)
        self.buffer.initialize(repeating: 0)
        self.headPtr = .allocate(capacity: 1)
        self.tailPtr = .allocate(capacity: 1)
        self.headPtr.initialize(to: 0)
        self.tailPtr.initialize(to: 0)
    }

    deinit {
        buffer.deallocate()
        headPtr.deallocate()
        tailPtr.deallocate()
    }

    /// Total available capacity in samples.
    var totalCapacity: Int { capacity }

    /// Samples currently buffered.
    var fillLevel: Int {
        Int(headPtr.pointee &- tailPtr.pointee)
    }

    /// Reset to empty. Not realtime-safe — call from main only.
    func reset() {
        headPtr.pointee = 0
        tailPtr.pointee = 0
    }

    // MARK: - Producer side (IOProc, single thread)

    /// Write `count` samples from `src`. Drops samples if the buffer is full
    /// (overrun protection — better silence than corruption). Returns the
    /// number of samples actually written.
    @discardableResult
    func write(_ src: UnsafePointer<Float>, count: Int) -> Int {
        let head = headPtr.pointee
        let tail = tailPtr.pointee
        let free = capacity - Int(head &- tail)
        let n = min(count, free)
        if n <= 0 { return 0 }

        // Two-segment copy in case of wraparound.
        let writeStart = Int(head & mask)
        let firstChunk = min(n, capacity - writeStart)
        memcpy(
            buffer.baseAddress!.advanced(by: writeStart),
            src,
            firstChunk * MemoryLayout<Float>.size
        )
        if n > firstChunk {
            memcpy(
                buffer.baseAddress!,
                src.advanced(by: firstChunk),
                (n - firstChunk) * MemoryLayout<Float>.size
            )
        }

        // Publish: aligned 64-bit store is atomic on arm64/x86_64.
        headPtr.pointee = head &+ UInt64(n)
        return n
    }

    // MARK: - Consumer side (IOProc, single thread)

    /// Read up to `count` samples into `dst`. Returns actual count read.
    /// Underrun is silent (caller should zero its buffer first).
    @discardableResult
    func read(_ dst: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let head = headPtr.pointee
        let tail = tailPtr.pointee
        let available = Int(head &- tail)
        let n = min(count, available)
        if n <= 0 { return 0 }

        let readStart = Int(tail & mask)
        let firstChunk = min(n, capacity - readStart)
        memcpy(
            dst,
            buffer.baseAddress!.advanced(by: readStart),
            firstChunk * MemoryLayout<Float>.size
        )
        if n > firstChunk {
            memcpy(
                dst.advanced(by: firstChunk),
                buffer.baseAddress!,
                (n - firstChunk) * MemoryLayout<Float>.size
            )
        }

        tailPtr.pointee = tail &+ UInt64(n)
        return n
    }
}
