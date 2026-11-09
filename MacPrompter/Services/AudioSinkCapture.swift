import AVFoundation
import Synchronization

/// AVAudioEngine taps deliver ~100 ms blocks whatever size is requested
/// (measured 102 ms on the maintainer's Mac, 27 October 2026). A sink node
/// runs at the device's I/O size, typically ~10 ms. The real-time callback
/// only copies samples into a preallocated ring; a worker thread builds
/// buffers and feeds the analyzer, so the audio thread never allocates or
/// blocks.
final class AudioSinkCapture: @unchecked Sendable {
    /// Mono Float32 at the device rate: the first input channel.
    let format: AVAudioFormat
    private let capacity: Int
    private let samples: UnsafeMutablePointer<Float>
    private let written = Atomic<Int>(0)
    private let consumed = Atomic<Int>(0)
    private let droppedFrames = Atomic<Int>(0)
    private let running = Atomic<Bool>(true)
    private let wake = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let deliver: @Sendable (AVAudioPCMBuffer) -> Void

    var dropped: Int { droppedFrames.load(ordering: .relaxed) }

    init?(sampleRate: Double, seconds: Double = 2, deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        guard sampleRate > 0, let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return nil }
        self.format = format
        capacity = max(1024, Int(sampleRate * seconds))
        samples = .allocate(capacity: capacity)
        samples.initialize(repeating: 0, count: capacity)
        self.deliver = deliver
        let worker = Thread { [self] in run() }
        worker.qualityOfService = .userInteractive
        worker.name = "macprompter.audio-capture"
        worker.start()
    }

    deinit { samples.deallocate() }

    /// Real-time thread: copy and signal only. If the worker stalls for the
    /// whole ring, new audio is dropped rather than overwriting unread audio.
    func write(_ source: UnsafePointer<Float>, frames: Int) {
        let end = written.load(ordering: .relaxed)
        guard frames > 0, end - consumed.load(ordering: .acquiring) + frames <= capacity else {
            droppedFrames.add(frames, ordering: .relaxed); return
        }
        var index = end % capacity, copied = 0
        while copied < frames {
            let count = min(frames - copied, capacity - index)
            (samples + index).update(from: source + copied, count: count)
            copied += count; index = 0
        }
        written.store(end + frames, ordering: .releasing)
        wake.signal()
    }

    /// Ends the worker and waits briefly, so the converter's frame count is
    /// final before a new input continues the timeline.
    func stop() {
        guard running.exchange(false, ordering: .acquiringAndReleasing) else { return }
        wake.signal()
        _ = finished.wait(timeout: .now() + 0.5)
    }

    private func run() {
        while running.load(ordering: .relaxed) {
            wake.wait()
            drain()
        }
        finished.signal()
    }

    private func drain() {
        let start = consumed.load(ordering: .relaxed), end = written.load(ordering: .acquiring)
        guard end > start, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(end - start)),
              let target = buffer.floatChannelData?[0] else { return }
        var index = start % capacity, copied = 0
        while copied < end - start {
            let count = min(end - start - copied, capacity - index)
            (target + copied).update(from: samples + index, count: count)
            copied += count; index = 0
        }
        buffer.frameLength = AVAudioFrameCount(end - start)
        consumed.store(end, ordering: .releasing)
        deliver(buffer)
    }

    /// Created outside MainActor isolation: Core Audio calls it on its
    /// real-time thread.
    nonisolated static func receiver(for capture: AudioSinkCapture) -> AVAudioSinkNodeReceiverBlock {
        { _, frameCount, list in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            if let data = buffers.first?.mData { capture.write(data.assumingMemoryBound(to: Float.self), frames: Int(frameCount)) }
            return noErr
        }
    }
}
