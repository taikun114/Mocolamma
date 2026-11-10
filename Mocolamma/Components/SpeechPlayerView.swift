import SwiftUI

struct SpeechPlayerView: View {
    let playback: SpeechPlayback
    @State private var scrubPosition: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playback.isPlaying)) { _ in
            VStack(alignment: .leading, spacing: 8) {
                timeline
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        transportControls
                        Spacer(minLength: 12)
                        volumeControls()
                    }
                    VStack(spacing: 12) {
                        transportControls
                        volumeControls(fillsWidth: true)
                    }
                }
                if let error = playback.playbackError {
                    Text(verbatim: error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(idealWidth: 480, maxWidth: 480)
        }
        .onDisappear {
            // スクロールなどで操作中のビューが消えた場合はプレビューを破棄する。
            scrubPosition = nil
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            MediaScrubBar(
                position: playback.currentTime,
                duration: playback.bufferedDuration,
                onScrubBegan: { scrubPosition = playback.currentTime },
                onScrubChanged: { scrubPosition = $0 },
                onScrubEnded: { position in
                    playback.seekFromControl(to: position)
                    scrubPosition = nil
                },
                onScrubCancelled: { scrubPosition = nil },
                onSeek: { playback.seekFromControl(to: $0) }
            )
            HStack {
                Text(time(scrubPosition ?? playback.currentTime))
                Spacer()
                if playback.isReceiving {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Generating speech")
                }
                Text(time(playback.bufferedDuration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 4) {
            skipButton(seconds: -15, symbol: "15.arrow.trianglehead.counterclockwise")
            skipButton(seconds: -5, symbol: "5.arrow.trianglehead.counterclockwise")
            Button {
                playback.togglePlayback()
            } label: {
                Label(playbackControlTitle, systemImage: playbackControlSymbol)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 30))
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MediaControlButtonStyle())
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: playbackControlSymbol)
            .help(playbackControlTitle)
            .disabled(!playback.hasAudio)
            skipButton(seconds: 5, symbol: "5.arrow.trianglehead.clockwise")
            skipButton(seconds: 15, symbol: "15.arrow.trianglehead.clockwise")
        }
        .foregroundStyle(.secondary)
    }

    private func skipButton(seconds: Int, symbol: String) -> some View {
        SpeechSkipButton(playback: playback, seconds: seconds, symbol: symbol)
    }

    private func volumeControls(fillsWidth: Bool = false) -> some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    playback.toggleMute()
                }
            } label: {
                Label {
                    Text(playback.isMuted || playback.volume == 0 ? "Unmute" : "Mute")
                } icon: {
                    Image(systemName: playback.volumeSymbol, variableValue: playback.isMuted || playback.volume == 0 ? nil : Double(playback.volume))
                }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14))
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MediaControlButtonStyle())
            .foregroundStyle(.secondary)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .help(playback.isMuted || playback.volume == 0 ? "Unmute" : "Mute")
            Slider(value: Binding(get: { playback.isMuted ? 0 : playback.volume }, set: setPlaybackVolume), in: 0...1) {
                Text("Volume")
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: fillsWidth ? nil : 150)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .help("Volume")
        }
    }

    private func setPlaybackVolume(_ value: Float) {
        guard value.isFinite else { return }
        let wasSilent = playback.isMuted || playback.volume == 0
        let willBeSilent = value <= 0
        if wasSilent != willBeSilent {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                playback.setVolume(value)
            }
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            playback.setVolume(value)
        }
    }

    private var playbackControlTitle: String {
        if playback.isAtEnd { return String(localized: "Play Again") }
        return playback.isPlaying ? String(localized: "Pause") : String(localized: "Play")
    }

    private var playbackControlSymbol: String {
        if playback.isAtEnd { return "arrow.trianglehead.clockwise" }
        return playback.isPlaying ? "pause.fill" : "play.fill"
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private struct MediaControlButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
    }
}

private struct SpeechSkipButton: View {
    let playback: SpeechPlayback
    let seconds: Int
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activation = 0

    private var title: String {
        seconds < 0 ? String(localized: "Skip backward \(-seconds) seconds") : String(localized: "Skip forward \(seconds) seconds")
    }

    var body: some View {
        Button {
            playback.skip(by: Double(seconds))
            if !reduceMotion { activation &+= 1 }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .symbolEffect(seconds < 0 ? .rotate.counterClockwise.byLayer : .rotate.clockwise.byLayer, options: .speed(2), value: activation)
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 23))
            .frame(width: 36, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(MediaControlButtonStyle())
        .help(title)
        .disabled(!playback.hasAudio)
    }
}
