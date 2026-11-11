import Foundation

extension ChatMessage {
    @MainActor
    private func speechRevisionSnapshot() -> ChatMessage {
        let snapshot = ChatMessage(role: role, content: content, createdAt: createdAt)
        snapshot.isSpeechGeneration = true
        snapshot.speechPlayback = speechPlayback
        snapshot.speechVoice = speechVoice
        snapshot.speechModelName = speechModelName
        snapshot.statistics = statistics
        snapshot.totalDuration = totalDuration
        snapshot.isStopped = isStopped
        return snapshot
    }

    @MainActor
    func speechRevisionsForRetry() -> [ChatMessage] {
        // 過去の版を表示していても、最新の生成結果まで順番を保って引き継ぐ。
        let latest = currentRevisionIndex == revisions.count ? speechRevisionSnapshot() : latestSpeechRevision
        return revisions + (latest.map { [$0] } ?? [])
    }

    @MainActor
    func selectSpeechRevision(at index: Int) {
        guard isSpeechGeneration, !isStreaming, index >= 0, index <= revisions.count,
              index != currentRevisionIndex else { return }
        if currentRevisionIndex == revisions.count {
            latestSpeechRevision = speechRevisionSnapshot()
        }
        let revision = index < revisions.count ? revisions[index] : latestSpeechRevision
        guard let revision else { return }
        speechPlayback?.pause()
        revision.speechPlayback?.pause()
        if let playback = speechPlayback {
            revision.speechPlayback?.inheritVolume(from: playback)
        }
        revision.speechPlayback?.seekFromControl(to: 0)
        content = revision.content
        createdAt = revision.createdAt
        statistics = revision.statistics
        totalDuration = revision.totalDuration
        isStopped = revision.isStopped
        speechPlayback = revision.speechPlayback
        speechVoice = revision.speechVoice
        speechModelName = revision.speechModelName
        currentRevisionIndex = index
    }

    @MainActor
    func stopSpeechRevisions() {
        speechPlayback?.stop()
        latestSpeechRevision?.speechPlayback?.stop()
        revisions.forEach { $0.speechPlayback?.stop() }
    }
}
