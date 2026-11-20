@preconcurrency import AVFoundation
@preconcurrency import Speech

/// The microphone, for dictation. Audio stays in memory: it's converted to the recogniser's
/// format and handed over buffer by buffer, never written to disk or logged.
///
/// Recording starts the moment fn goes down, before the recogniser's format is known, so the
/// first word isn't lost: buffers wait in a short queue until `setFormat` is called.
final class AudioCapture: @unchecked Sendable {
    /// 0…1, about 20 times a second, for the pill's level meter.
    var onLevel: (@Sendable (Float) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var sourceFormat: AVAudioFormat?
    private var pending: [AVAudioPCMBuffer] = []
    private var isRunning = false
    /// The microphone stopped; the stream ends once the waiting buffers are sent.
    private var inputEnded = false
    private var lastLevelAt = Date.distantPast

    /// The buffers for the recogniser, in its format, from the moment `start` was called.
    private(set) var stream: AsyncStream<AnalyzerInput>?

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noMicrophone }
        reset(source: format)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.receive(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        lock.withLock { isRunning = true }
    }

    #if DEBUG
    /// Tests: audio from a file instead of the microphone (`inject` the buffers).
    func startWithoutMicrophone(source: AVAudioFormat) {
        reset(source: source)
    }

    func inject(_ buffer: AVAudioPCMBuffer) {
        receive(buffer)
    }
    #endif

    private func reset(source: AVAudioFormat) {
        lock.withLock {
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .unbounded)
            self.stream = stream
            self.continuation = continuation
            pending = []
            converter = nil
            targetFormat = nil
            sourceFormat = source
            inputEnded = false
        }
    }

    /// The recogniser is ready: convert to its format, starting with what was already recorded.
    func setFormat(_ format: AVAudioFormat) {
        lock.withLock {
            guard let sourceFormat, continuation != nil else { return }
            targetFormat = format
            converter = AVAudioConverter(from: sourceFormat, to: format)
            for buffer in pending { convertAndSend(buffer) }
            pending = []
            if inputEnded {
                continuation?.finish()
                continuation = nil
            }
        }
    }

    /// Stops the microphone. The stream ends after everything recorded has been sent, even if
    /// the recogniser isn't ready yet (the first dictation after launch).
    func stop() {
        stopMicrophone()
        lock.withLock {
            inputEnded = true
            guard converter != nil else { return }  // `setFormat` sends the rest, then ends it
            continuation?.finish()
            continuation = nil
        }
    }

    /// Stops the microphone and drops everything (Esc, or a tap that wasn't a hold).
    func discard() {
        stopMicrophone()
        lock.withLock {
            inputEnded = true
            continuation?.finish()
            continuation = nil
            pending = []
        }
    }

    private func stopMicrophone() {
        let wasRunning = lock.withLock { () -> Bool in
            defer { isRunning = false }
            return isRunning
        }
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    enum CaptureError: Error {
        case noMicrophone
    }

    // MARK: Audio thread

    private func receive(_ buffer: AVAudioPCMBuffer) {
        reportLevel(buffer)
        lock.withLock {
            guard continuation != nil, !inputEnded else { return }
            if converter == nil {
                // At most ~10 s waits for the recogniser; it's normally ready in well under one.
                if pending.count < 500, let copy = buffer.copy() as? AVAudioPCMBuffer { pending.append(copy) }
                return
            }
            convertAndSend(buffer)
        }
    }

    /// Called with the lock held.
    private func convertAndSend(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        let supplied = SuppliedFlag()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied.value {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied.value = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return }
        continuation?.yield(AnalyzerInput(buffer: output))
    }

    private func reportLevel(_ buffer: AVAudioPCMBuffer) {
        guard let onLevel, let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let now = Date.now
        guard now.timeIntervalSince(lastLevelAt) >= 0.05 else { return }
        lastLevelAt = now
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        // Speech sits around -40…-10 dBFS; map that range onto 0…1.
        let decibels = 20 * log10(max(rms, 0.000_01))
        onLevel(min(max((decibels + 50) / 40, 0), 1))
    }
}

/// The converter asks for input synchronously, on this thread; this just carries one flag.
private final class SuppliedFlag: @unchecked Sendable {
    var value = false
}
