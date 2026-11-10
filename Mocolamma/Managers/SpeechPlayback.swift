import AVFAudio
import AudioToolbox
import Foundation
import Observation

@Observable @MainActor
final class SpeechPlayback {
    private(set) var hasAudio = false
    private(set) var isReceiving = true
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval?
    private(set) var bufferedDuration: TimeInterval = 0
    private(set) var volume: Float = 1
    private(set) var isMuted = false
    @ObservationIgnored private var lastAudibleVolume: Float = 1
    private(set) var playbackError: String?
    @ObservationIgnored private var pcm = SpeechPCMStream()
    @ObservationIgnored private let exportID = UUID()
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private var epoch = UUID()
    private var completedFrames = 0
    private var pausedFrame = 0
    @ObservationIgnored private var scheduledEnd: AVAudioFramePosition = 0
    @ObservationIgnored private var segments: [Segment] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var controlTask: Task<Void, Never>?
    @ObservationIgnored private var fadeParameter: AUParameter?
    @ObservationIgnored private var fadeScheduler: AUScheduleParameterBlock?
    @ObservationIgnored private var fadeGain: Float = 1
    private static let fadeDuration: TimeInterval = 0.008
    private static weak var activePlayback: SpeechPlayback?

    private struct Segment {
        let nodeStart: AVAudioFramePosition
        let pcmStart: Int
        let frames: Int
    }

    var currentTime: TimeInterval {
        let completedTime = Double(max(completedFrames, pausedFrame)) / SpeechPCMStream.sampleRate
        if isAtEnd { return bufferedDuration }
        if !isPlaying { return Double(pausedFrame) / SpeechPCMStream.sampleRate }
        guard let player, let render = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: render),
              let segment = segments.last(where: { $0.nodeStart <= time.sampleTime }) else {
            return completedTime
        }
        let offset = min(segment.frames, max(0, Int(time.sampleTime - segment.nodeStart)))
        return Double(segment.pcmStart + offset) / SpeechPCMStream.sampleRate
    }

    var isAtEnd: Bool {
        duration != nil && hasAudio && !isPlaying && pausedFrame >= pcm.data.count / 2
    }

    var audioExport: SpeechAudioExport? {
        guard hasAudio, !isReceiving else { return nil }
        return SpeechAudioExport(id: exportID, pcm: pcm.data)
    }

    func append(_ data: Data) throws {
        let rebuilding = engine == nil
        let start = pcm.data.count / 2
        let aligned = pcm.append(data)
        guard !aligned.isEmpty else { return }
        bufferedDuration = pcm.duration
        hasAudio = true
        guard engine != nil || isPlaying else { return }
        try prepareEngine()
        if rebuilding {
            try schedule(pcm.data.subdata(in: completedFrames * 2..<pcm.data.count), pcmStart: completedFrames)
        } else {
            try schedule(aligned, pcmStart: start)
        }
        if isPlaying { player?.play() }
    }

    func finish() throws {
        try pcm.finish()
        isReceiving = false
        duration = pcm.duration
        if completedFrames >= pcm.data.count / 2 {
            pauseImmediately(atFrame: completedFrames)
        }
    }

    func cancelReceiving() {
        isReceiving = false
        pause()
    }

    func pause() {
        cancelControlTransition()
        pauseImmediately()
        setFadeGain(1)
    }

    private func pauseImmediately(atFrame frame: Int? = nil) {
        // エンジン停止後はレンダー時刻を参照できないため、停止直前の位置を保存する。
        pausedFrame = frame ?? min(pcm.data.count / 2, Int(currentTime * SpeechPCMStream.sampleRate))
        player?.pause()
        engine?.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying {
            cancelControlTransition()
            controlTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await fadeOutput(to: 0)
                    pauseImmediately()
                    setFadeGain(1)
                    controlTask = nil
                } catch is CancellationError {
                } catch { handlePlaybackError(error) }
            }
        } else { play() }
    }

    func play() {
        guard hasAudio, !isPlaying else { return }
        cancelControlTransition()
        setFadeGain(0)
        do {
            let position = currentTime
            let restart = isAtEnd
            if Self.activePlayback !== self { Self.activePlayback?.pause() }
            Self.activePlayback = self
            isPlaying = true
            if engine == nil || segments.isEmpty || restart {
                try seek(to: restart ? 0 : position)
            }
            try prepareEngine()
            if let engine, !engine.isRunning { try engine.start() }
            player?.play()
            playbackError = nil
            controlTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await fadeOutput(to: 1)
                    controlTask = nil
                } catch is CancellationError {
                } catch { handlePlaybackError(error) }
            }
        } catch { handlePlaybackError(error) }
    }

    func skip(by seconds: TimeInterval) {
        seekFromControl(to: currentTime + seconds)
    }

    func setVolume(_ value: Float) {
        guard value.isFinite else { return }
        volume = min(1, max(0, value))
        if volume > 0 { lastAudibleVolume = volume }
        isMuted = false
        updateVolume()
    }

    func inheritVolume(from playback: SpeechPlayback) {
        volume = playback.volume
        isMuted = playback.isMuted
        lastAudibleVolume = playback.lastAudibleVolume
        updateVolume()
    }

    func toggleMute() {
        if isMuted || volume == 0 {
            isMuted = false
            if volume == 0 { volume = lastAudibleVolume }
        } else {
            isMuted = true
        }
        updateVolume()
    }

    var volumeSymbol: String {
        isMuted || volume == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }

    private func updateVolume() {
        player?.volume = isMuted ? 0 : volume
    }

    func seek(to seconds: TimeInterval) throws {
        guard !pcm.data.isEmpty, seconds.isFinite else { return }
        let resume = isPlaying
        epoch = UUID()
        player?.stop()
        segments = []
        scheduledEnd = 0
        let clampedTime = min(bufferedDuration, max(0, seconds))
        let frame = min(pcm.data.count / 2, Int(clampedTime * SpeechPCMStream.sampleRate))
        completedFrames = frame
        pausedFrame = frame
        if engine == nil && !resume { return }
        try prepareEngine()
        if frame < pcm.data.count / 2 {
            try schedule(pcm.data.subdata(in: frame * 2..<pcm.data.count), pcmStart: frame)
            if resume { player?.play() }
        } else if !isReceiving {
            pauseImmediately()
        }
    }

    func seekFromControl(to seconds: TimeInterval) {
        cancelControlTransition()
        guard isPlaying else {
            setFadeGain(1)
            do { try seek(to: seconds) }
            catch { handlePlaybackError(error) }
            return
        }
        controlTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await fadeOutput(to: 0)
                try seek(to: seconds)
                if isPlaying { try await fadeOutput(to: 1) }
                else { setFadeGain(1) }
                controlTask = nil
            } catch is CancellationError {
            } catch { handlePlaybackError(error) }
        }
    }

    private func cancelControlTransition() {
        controlTask?.cancel()
        controlTask = nil
    }

    private func setFadeGain(_ gain: Float) {
        fadeGain = gain
        engine?.mainMixerNode.outputVolume = gain
    }

    private func fadeOutput(to target: Float) async throws {
        try Task.checkCancellation()
        guard let engine, engine.isRunning else { setFadeGain(target); return }
        if let fadeParameter, let fadeScheduler {
            let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
            let frames = AUAudioFrameCount(max(1, sampleRate * Self.fadeDuration))
            // 音量補間はオーディオのレンダリング側で行い、停止前に反映を待つ。
            fadeScheduler(AUEventSampleTimeImmediate, frames, fadeParameter.address, target)
            try await Task.sleep(for: .milliseconds(20))
            try Task.checkCancellation()
            fadeGain = target
        } else {
            // ランプ非対応の出力では、短い段階的な音量変更へフォールバックする。
            let initial = fadeGain
            for step in 1...8 {
                try Task.checkCancellation()
                setFadeGain(initial + (target - initial) * Float(step) / 8)
                try await Task.sleep(for: .milliseconds(2))
            }
        }
    }

    private func configureFade(for mixer: AVAudioMixerNode) {
        let configure: (AUAudioUnit) -> Void = { [self] unit in
            fadeParameter = unit.parameterTree?.allParameters.first {
                $0.keyPath.hasPrefix("output.") && $0.unit == .linearGain &&
                    $0.flags.contains(.flag_CanRamp)
            }
            fadeScheduler = fadeParameter == nil ? nil : unit.scheduleParameterBlock
        }
        if #available(macOS 27, iOS 27, visionOS 27, *) {
            mixer.withAUAudioUnit { configure($0) }
        } else {
            configure(mixer.auAudioUnit)
        }
        mixer.outputVolume = fadeGain
    }

    func stop() {
        cancelControlTransition()
        epoch = UUID()
        isReceiving = false
        isPlaying = false
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        fadeParameter = nil
        fadeScheduler = nil
        segments = []
        scheduledEnd = 0
        completedFrames = 0
        pausedFrame = 0
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func prepareEngine() throws {
        if let engine {
            if isPlaying && !engine.isRunning { try engine.start() }
            return
        }
#if !os(macOS)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
#endif
        guard let format = AVAudioFormat(standardFormatWithSampleRate: SpeechPCMStream.sampleRate, channels: 1) else {
            throw SpeechError.invalidAudio
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        if isPlaying { try engine.start() }
        self.engine = engine
        self.player = player
        configureFade(for: engine.mainMixerNode)
        updateVolume()
        // 出力デバイスの変更時は古いグラフへの再生予約を破棄し、再生操作で作り直す。
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resetOutput() }
        })
#if !os(macOS)
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
        })
#endif
    }

    private func resetOutput() {
        let frame = Int(currentTime * SpeechPCMStream.sampleRate)
        pause()
        epoch = UUID()
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        fadeParameter = nil
        fadeScheduler = nil
        completedFrames = frame
        pausedFrame = frame
        segments = []
        scheduledEnd = 0
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func schedule(_ bytes: Data, pcmStart: Int) throws {
        guard let player, let format = AVAudioFormat(standardFormatWithSampleRate: SpeechPCMStream.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bytes.count / 2)),
              let channel = buffer.floatChannelData?[0] else { throw SpeechError.invalidAudio }
        let frames = bytes.count / 2
        buffer.frameLength = AVAudioFrameCount(frames)
        bytes.withUnsafeBytes { raw in
            for index in 0..<frames {
                let bits = UInt16(raw[index * 2]) | UInt16(raw[index * 2 + 1]) << 8
                channel[index] = Float(Int16(bitPattern: bits)) / 32768
            }
        }
        var start = scheduledEnd
        if player.isPlaying, let render = player.lastRenderTime, let time = player.playerTime(forNodeTime: render) {
            // 受信待ちで再生キューが空になった場合は現在の再生時刻より先へ予約する。
            start = max(start, time.sampleTime + 512)
        }
        let id = epoch
        let end = pcmStart + frames
        segments.append(Segment(nodeStart: start, pcmStart: pcmStart, frames: frames))
        scheduledEnd = start + AVAudioFramePosition(frames)
        player.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: start, atRate: SpeechPCMStream.sampleRate), options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.epoch == id else { return }
                self.completedFrames = end
                if !self.isReceiving, end >= self.pcm.data.count / 2 {
                    self.pauseImmediately(atFrame: end)
                }
            }
        }
    }

    private func handlePlaybackError(_ error: Error) {
        pause()
        playbackError = error.localizedDescription
#if DEBUG
        print("Speech playback failed: \(error.localizedDescription)")
#endif
    }

    deinit {
        controlTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        engine?.stop()
    }
}
