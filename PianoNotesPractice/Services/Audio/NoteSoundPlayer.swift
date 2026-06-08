@preconcurrency import AVFoundation
import Observation
/// Carries an AVFoundation player safely across its real-time completion callback.
private struct ScheduledAudioPlayer: @unchecked Sendable {
    let node: AVAudioPlayerNode
}
/// Synthesizes and plays the quiz note audio used for ear practice prompts.
@Observable
final class NoteSoundPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private let channelCount: AVAudioChannelCount = 2
    private let toneDuration = 2.3
    private let noteSpacing = 0.7
    private let replayTailTrim = 0.32
    private let toneCacheDirectoryName = "ToneCache-v3-44100hz-2300ms-stereo-f32-pitch"
    private let celebrationMelodyCacheDirectoryName = "CelebrationMelodyCache-v2-44100hz-stereo-f32"
    private var playbackToken = UUID()
    private var replayReadyTask: Task<Void, Never>?
    private let toneBufferLock = NSLock()
    private let tonePreparationLock = NSLock()
    private var toneBuffers: [String: AVAudioPCMBuffer] = [:]
    private var promptPlayers: [AVAudioPlayerNode] = []
    private var promptStartTasks: [Task<Void, Never>] = []
    private var currentPromptNoteStartedAt: Date?
    private var effectPlayers: [AVAudioPlayerNode] = []
    private var celebrationMelodyPlayers: [AVAudioPlayerNode] = []
    private var celebrationMelodyBuffers: [Int: AVAudioPCMBuffer] = [:]
    private var lastCelebrationMelodyNumber = 0
    private(set) var isReplayReady = true
    private(set) var isPreparingAudioCache = false
    private(set) var isWarmingAudioCache = false
    private(set) var isPreparingCelebrationMelodyCache = false
    private var preparedToneKeys: Set<String> = []
    private var warmingOctaves: Set<Int> = []
    private var warmedOctaves: Set<Int> = []
    private(set) var celebrationMelodyNumber: Int?
    @ObservationIgnored private var playbackFinishedContinuation: AsyncStream<Void>.Continuation?
    /// Reports whether the active prompt audio is still playing.
    var isPlaying: Bool {
        promptPlayers.contains { $0.isPlaying }
    }
    var celebrationMelodyCount: Int {
        Self.celebrationMelodies.count
    }
    init() {
        AppLog.audio.info(
            "Note sound player initialized; sample rate \(self.sampleRate, privacy: .public), channels \(self.channelCount, privacy: .public), tone duration \(self.toneDuration, privacy: .public)"
        )
    }
    /// Returns prompt-completion events without exposing a Combine publisher.
    func playbackFinishedEvents() -> AsyncStream<Void> {
        AsyncStream { continuation in
            playbackFinishedContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.playbackFinishedContinuation = nil
            }
        }
    }
    func play(note: QuizNote) {
        play(notes: [note])
    }
    func play(notes: [QuizNote]) {
        guard !notes.isEmpty else { return }
        AppLog.audio.info("Prompt playback requested; note count \(notes.count, privacy: .public)")
        prepareAudioCache(for: notes)
        playbackToken = UUID()
        let activePlaybackToken = playbackToken
        replayReadyTask?.cancel()
        replayReadyTask = nil
        isReplayReady = false
        cancelPromptPlayback()
        let noteBuffers = notes.compactMap { note in
            cachedToneBuffer(
                letter: note.letter,
                accidental: note.accidental,
                octave: note.octave
            )
        }
        guard !noteBuffers.isEmpty else {
            AppLog.audio.info("Prompt playback finished early because no prepared buffers were available")
            finishPlayback(for: activePlaybackToken)
            return
        }
        schedulePromptPlayback(buffers: noteBuffers, token: activePlaybackToken)
    }
    func playKeyboardEffect(for answer: NoteAnswer, octave: Int) {
        prepareAudioCache(for: answer, octave: octave)
        cancelPendingPromptNotes()
        if let buffer = cachedToneBuffer(letter: answer.letter, accidental: answer.accidental, octave: octave) {
            scheduleKeyboardEffect(buffer)
            return
        }
        AppLog.audio.info("Keyboard effect skipped because the tone buffer was unavailable")
    }
    func playNextCelebrationMelody() {
        let nextNumber = (lastCelebrationMelodyNumber % Self.celebrationMelodies.count) + 1
        playCelebrationMelody(number: nextNumber)
    }
    func playRandomCelebrationMelody() {
        let candidates = Self.celebrationMelodies.map(\.number)
        guard !candidates.isEmpty else { return }
        let nextNumber = candidates.filter { $0 != lastCelebrationMelodyNumber }.randomElement() ?? candidates[0]
        playCelebrationMelody(number: nextNumber)
    }
    func playCelebrationMelody(number: Int) {
        guard Self.celebrationMelodies.contains(where: { $0.number == number }) else { return }
        AppLog.audio.info("Celebration melody requested: \(number, privacy: .public)")
        lastCelebrationMelodyNumber = number
        prepareCelebrationMelodyCache(number: number)
        if let buffer = celebrationMelodyBuffers[number] {
            scheduleCelebrationMelody(buffer, number: number)
        } else {
            AppLog.audio.info("Celebration melody skipped because the buffer was unavailable: \(number, privacy: .public)")
        }
    }
    func celebrationMelodyKeyPresses(number: Int) -> [CelebrationMelodyKeyPress] {
        guard let melody = Self.celebrationMelodies.first(where: { $0.number == number }) else { return [] }
        return melody.notes.map { note in
            CelebrationMelodyKeyPress(
                answer: NoteAnswer(letter: note.letter, accidental: note.accidental),
                octave: note.octave,
                duration: note.duration
            )
        }
    }
    func prepareAudioCache(for note: QuizNote) {
        prepareToneBuffer(letter: note.letter, accidental: note.accidental, octave: note.octave)
        warmOctaveToneCacheInBackgroundIfNeeded(octave: note.octave)
    }
    func prepareAudioCache(for notes: [QuizNote]) {
        let missingNotes = notes.filter {
            !isTonePrepared(key: toneBufferKey(letter: $0.letter, accidental: $0.accidental, octave: $0.octave))
        }
        if missingNotes.isEmpty {
            notes.forEach { warmOctaveToneCacheInBackgroundIfNeeded(octave: $0.octave) }
            return
        }
        AppLog.audio.info("Preparing prompt tone buffers; missing count \(missingNotes.count, privacy: .public)")
        isPreparingAudioCache = true
        for note in missingNotes {
            prepareToneBuffer(letter: note.letter, accidental: note.accidental, octave: note.octave)
        }
        isPreparingAudioCache = false
        AppLog.audio.info("Prompt tone buffer preparation finished")
        notes.forEach { warmOctaveToneCacheInBackgroundIfNeeded(octave: $0.octave) }
    }
    func prepareAudioCache(for answer: NoteAnswer, octave: Int) {
        prepareToneBuffer(letter: answer.letter, accidental: answer.accidental, octave: octave)
        warmOctaveToneCacheInBackgroundIfNeeded(octave: octave)
    }
    func warmAudioCache(forOctave octave: Int) {
        warmOctaveToneCacheInBackgroundIfNeeded(octave: octave)
    }
    func purgeAudioCache() {
        AppLog.audio.info("Purging audio cache")
        stopPlayback()
        toneBufferLock.lock()
        toneBuffers.removeAll()
        celebrationMelodyBuffers.removeAll()
        toneBufferLock.unlock()
        tonePreparationLock.lock()
        preparedToneKeys.removeAll()
        tonePreparationLock.unlock()
        warmingOctaves.removeAll()
        warmedOctaves.removeAll()
        isPreparingAudioCache = true
        isWarmingAudioCache = false
        isPreparingCelebrationMelodyCache = false
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            self.removeCacheDirectory(named: self.toneCacheDirectoryName)
            self.removeCacheDirectory(named: self.celebrationMelodyCacheDirectoryName)
            await MainActor.run {
                self.isPreparingAudioCache = false
                AppLog.audio.info("Audio cache purge finished")
            }
        }
    }
    func prepareCelebrationMelodyCache(number: Int) {
        guard celebrationMelodyBuffers[number] == nil else {
            AppLog.audio.info("Celebration melody cache already prepared: \(number, privacy: .public)")
            return
        }
        guard let melody = Self.celebrationMelodies.first(where: { $0.number == number }) else { return }
        AppLog.audio.info("Preparing celebration melody cache: \(number, privacy: .public)")
        isPreparingCelebrationMelodyCache = true
        if let buffer = cachedOrCreateCelebrationMelodyBuffer(melody: melody) {
            celebrationMelodyBuffers[number] = buffer
        }
        isPreparingCelebrationMelodyCache = false
        AppLog.audio.info("Celebration melody cache preparation finished: \(number, privacy: .public)")
    }
    private func prepareToneBuffer(letter: String, accidental: Accidental, octave: Int) {
        let key = toneBufferKey(letter: letter, accidental: accidental, octave: octave)
        guard !isTonePrepared(key: key) else { return }
        guard cachedOrCreateToneBuffer(letter: letter, accidental: accidental, octave: octave) != nil else { return }
        markTonePrepared(key: key)
    }
    private func warmOctaveToneCacheInBackgroundIfNeeded(octave: Int) {
        guard !(warmedOctaves.contains(octave) || warmingOctaves.contains(octave)) else { return }
        warmingOctaves.insert(octave)
        isWarmingAudioCache = true
        AppLog.audio.info("Background tone cache warm-up started; octave \(octave, privacy: .public)")
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let pitchOffsets = self.pitchOffsets(octave: octave)
            for pitchOffset in pitchOffsets {
                let key = self.toneBufferKey(pitchOffset: pitchOffset)
                guard !self.isTonePrepared(key: key) else { continue }
                guard self.cachedOrCreateToneBuffer(pitchOffset: pitchOffset) != nil else { continue }
                self.markTonePrepared(key: key)
            }
            await MainActor.run {
                self.warmingOctaves.remove(octave)
                self.warmedOctaves.insert(octave)
                self.isWarmingAudioCache = !self.warmingOctaves.isEmpty
                AppLog.audio.info("Background tone cache warm-up finished; octave \(octave, privacy: .public)")
            }
        }
    }
    private func isTonePrepared(key: String) -> Bool {
        tonePreparationLock.lock()
        let isPrepared = preparedToneKeys.contains(key)
        tonePreparationLock.unlock()
        return isPrepared
    }
    private func markTonePrepared(key: String) {
        tonePreparationLock.lock()
        preparedToneKeys.insert(key)
        tonePreparationLock.unlock()
    }
    private func schedulePromptPlayback(buffers: [AVAudioPCMBuffer], token: UUID) {
        for noteIndex in buffers.indices {
            let isLastNote = noteIndex == buffers.index(before: buffers.endIndex)
            let startDelay = Double(noteIndex) * noteSpacing
            let buffer = buffers[noteIndex]
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(startDelay))
                guard !Task.isCancelled else { return }
                self?.startPromptNotePlayback(
                    buffer: buffer,
                    isLastNote: isLastNote,
                    token: token
                )
            }
            promptStartTasks.append(task)
        }
    }
    private func startPromptNotePlayback(buffer: AVAudioPCMBuffer, isLastNote: Bool, token: UUID) {
        guard playbackToken == token else { return }
        currentPromptNoteStartedAt = Date()
        let promptPlayer = AVAudioPlayerNode()
        promptPlayers.append(promptPlayer)
        engine.attach(promptPlayer)
        engine.connect(promptPlayer, to: engine.mainMixerNode, format: buffer.format)
        do {
            try ensureEngineIsRunning()
        } catch {
            AppLog.audio.error("Prompt playback failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            engine.detach(promptPlayer)
            promptPlayers.removeAll { $0 === promptPlayer }
            finishPlayback(for: token)
            return
        }
        let scheduledPromptPlayer = ScheduledAudioPlayer(node: promptPlayer)
        promptPlayer.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self, scheduledPromptPlayer] _ in
            Task { @MainActor [weak self, scheduledPromptPlayer] in
                guard let self else { return }
                let promptPlayer = scheduledPromptPlayer.node
                promptPlayer.stop()
                self.engine.detach(promptPlayer)
                self.promptPlayers.removeAll { $0 === promptPlayer }
            }
        }
        if isLastNote {
            scheduleReplayReady(after: effectiveSingleNotePlaybackDuration(), token: token)
        }
        promptPlayer.play()
    }
    private func scheduleKeyboardEffect(_ buffer: AVAudioPCMBuffer) {
        let effectPlayer = AVAudioPlayerNode()
        effectPlayers.append(effectPlayer)
        engine.attach(effectPlayer)
        engine.connect(effectPlayer, to: engine.mainMixerNode, format: buffer.format)
        do {
            try ensureEngineIsRunning()
        } catch {
            AppLog.audio.error("Keyboard effect failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            engine.detach(effectPlayer)
            effectPlayers.removeAll { $0 === effectPlayer }
            return
        }
        let scheduledEffectPlayer = ScheduledAudioPlayer(node: effectPlayer)
        effectPlayer.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self, scheduledEffectPlayer] _ in
            Task { @MainActor [weak self, scheduledEffectPlayer] in
                guard let self else { return }
                let effectPlayer = scheduledEffectPlayer.node
                effectPlayer.stop()
                self.engine.detach(effectPlayer)
                self.effectPlayers.removeAll { $0 === effectPlayer }
            }
        }
        effectPlayer.play()
    }
    private func scheduleCelebrationMelody(_ buffer: AVAudioPCMBuffer, number: Int) {
        cancelPendingPromptNotes()
        let player = AVAudioPlayerNode()
        celebrationMelodyPlayers.append(player)
        celebrationMelodyNumber = number
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        do {
            try ensureEngineIsRunning()
        } catch {
            AppLog.audio.error("Celebration melody failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            engine.detach(player)
            celebrationMelodyPlayers.removeAll { $0 === player }
            celebrationMelodyNumber = nil
            return
        }
        let scheduledMelodyPlayer = ScheduledAudioPlayer(node: player)
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self, scheduledMelodyPlayer] _ in
            Task { @MainActor [weak self, scheduledMelodyPlayer] in
                guard let self else { return }
                let player = scheduledMelodyPlayer.node
                player.stop()
                self.engine.detach(player)
                self.celebrationMelodyPlayers.removeAll { $0 === player }
                if self.celebrationMelodyPlayers.isEmpty {
                    self.celebrationMelodyNumber = nil
                }
            }
        }
        player.play()
        AppLog.audio.info("Celebration melody playback started: \(number, privacy: .public)")
    }
    private func finishPlayback(for token: UUID) {
        guard playbackToken == token, !isReplayReady else { return }
        isReplayReady = true
        playbackFinishedContinuation?.yield(())
        AppLog.audio.info("Prompt playback finished")
    }
    func stopPlayback() {
        AppLog.audio.info("Stopping playback")
        playbackToken = UUID()
        replayReadyTask?.cancel()
        replayReadyTask = nil
        isReplayReady = true
        cancelPromptPlayback()
        celebrationMelodyNumber = celebrationMelodyPlayers.isEmpty ? nil : celebrationMelodyNumber
    }
    private func cancelPromptPlayback() {
        let activePromptPlayerCount = promptPlayers.count
        let pendingPromptCount = promptStartTasks.count
        promptStartTasks.forEach { $0.cancel() }
        promptStartTasks.removeAll()
        currentPromptNoteStartedAt = nil
        if pendingPromptCount > 0 || activePromptPlayerCount > 0 {
            AppLog.audio.info("Canceling prompt playback")
        }
    }
    private func cancelPendingPromptNotes() {
        guard !isReplayReady else { return }
        AppLog.audio.info("Canceling pending prompt notes while preserving replay timing")
        promptStartTasks.forEach { $0.cancel() }
        promptStartTasks.removeAll()
        replayReadyTask?.cancel()
        replayReadyTask = nil
        guard let currentPromptNoteStartedAt else {
            finishPlayback(for: playbackToken)
            return
        }
        let elapsed = Date().timeIntervalSince(currentPromptNoteStartedAt)
        let remainingDuration = max(0.0, effectiveSingleNotePlaybackDuration() - elapsed)
        scheduleReplayReady(after: remainingDuration, token: playbackToken)
    }
    private func scheduleReplayReady(after duration: TimeInterval, token: UUID) {
        replayReadyTask?.cancel()
        let replayReadyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.finishPlayback(for: token)
        }
        self.replayReadyTask = replayReadyTask
    }
    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            AppLog.audio.error("Audio session configuration failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        #endif
    }
    private func ensureEngineIsRunning() throws {
        try configureAudioSession()
        if !engine.isRunning {
            do {
                try engine.start()
                AppLog.audio.info("Audio engine started")
            } catch {
                AppLog.audio.error("Audio engine start failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }
    private func frequency(for note: QuizNote) -> Double {
        frequency(letter: note.letter, accidental: note.accidental, octave: note.octave)
    }
    private func frequency(letter: String, accidental: Accidental, octave: Int) -> Double {
        let offset = pitchOffset(letter: letter, accidental: accidental, octave: octave)
        return frequency(pitchOffset: offset)
    }
    private func frequency(pitchOffset: Int) -> Double {
        let offset = pitchOffset
        return 440.0 * pow(2.0, Double(offset) / 12.0)
    }
    private func pitchOffset(letter: String, accidental: Accidental, octave: Int) -> Int {
        let semitoneFromA: [String: Int] = [
            "C": -9,
            "D": -7,
            "E": -5,
            "F": -4,
            "G": -2,
            "A": 0,
            "B": 2
        ]
        return (semitoneFromA[letter] ?? 0) + accidental.semitoneOffset + (octave - 4) * 12
    }
    private func audioFormat() -> AVAudioFormat? {
        AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channelCount
        )
    }
    private func pitchOffsets(octave: Int) -> [Int] {
        let firstOffset = pitchOffset(letter: "C", accidental: .natural, octave: octave)
        return (0..<12).map { firstOffset + $0 }
    }
    private func cachedToneBuffer(letter: String, accidental: Accidental, octave: Int) -> AVAudioPCMBuffer? {
        toneBufferLock.lock()
        let buffer = toneBuffers[toneBufferKey(letter: letter, accidental: accidental, octave: octave)]
        toneBufferLock.unlock()
        return buffer
    }
    private func cachedOrCreateToneBuffer(letter: String, accidental: Accidental, octave: Int) -> AVAudioPCMBuffer? {
        cachedOrCreateToneBuffer(
            pitchOffset: pitchOffset(letter: letter, accidental: accidental, octave: octave)
        )
    }
    private func cachedOrCreateToneBuffer(pitchOffset: Int) -> AVAudioPCMBuffer? {
        let key = toneBufferKey(pitchOffset: pitchOffset)
        toneBufferLock.lock()
        let cachedBuffer = toneBuffers[key]
        toneBufferLock.unlock()
        if let cachedBuffer {
            return cachedBuffer
        }
        if let diskBuffer = loadCachedToneBufferFromDisk(key: key) {
            toneBufferLock.lock()
            toneBuffers[key] = diskBuffer
            toneBufferLock.unlock()
            return diskBuffer
        }
        let buffer = toneBuffer(
            frequency: frequency(pitchOffset: pitchOffset),
            duration: toneDuration,
            gain: 0.34,
            dampingFactor: 1.45
        )
        guard let buffer else { return nil }
        toneBufferLock.lock()
        let storedBuffer = toneBuffers[key]
        if storedBuffer == nil {
            toneBuffers[key] = buffer
        }
        toneBufferLock.unlock()
        if let storedBuffer {
            return storedBuffer
        }
        saveToneBufferToDisk(buffer, key: key)
        return buffer
    }
    private func toneBufferKey(letter: String, accidental: Accidental, octave: Int) -> String {
        toneBufferKey(pitchOffset: pitchOffset(letter: letter, accidental: accidental, octave: octave))
    }
    private func toneBufferKey(pitchOffset: Int) -> String {
        "pitch:\(pitchOffset)"
    }
    private func toneCacheFileURL(for key: String) -> URL? {
        cacheFileURL(for: key, directoryName: toneCacheDirectoryName)
    }
    private func cacheFileURL(for key: String, directoryName: String) -> URL? {
        let filename = key.replacingOccurrences(of: ":", with: "-") + ".f32"
        return cacheDirectoryURL(named: directoryName)?
            .appendingPathComponent(filename, isDirectory: false)
    }
    private func cacheDirectoryURL(named directoryName: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(directoryName, isDirectory: true)
    }
    private func removeCacheDirectory(named directoryName: String) {
        guard let directoryURL = cacheDirectoryURL(named: directoryName) else { return }
        do {
            try FileManager.default.removeItem(at: directoryURL)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            AppLog.audio.error("Audio cache purge failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    private func loadCachedToneBufferFromDisk(key: String) -> AVAudioPCMBuffer? {
        loadCachedBufferFromDisk(
            key: key,
            directoryName: toneCacheDirectoryName,
            expectedFrameCount: AVAudioFrameCount(sampleRate * toneDuration)
        )
    }
    private func loadCachedBufferFromDisk(
        key: String,
        directoryName: String,
        expectedFrameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        guard
            let format = audioFormat(),
            let fileURL = cacheFileURL(for: key, directoryName: directoryName),
            let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }
        let expectedByteCount = Int(expectedFrameCount) * Int(format.channelCount) * MemoryLayout<Float>.size
        guard data.count == expectedByteCount else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: expectedFrameCount) else {
            return nil
        }
        buffer.frameLength = expectedFrameCount
        guard let channelData = buffer.floatChannelData else {
            return nil
        }
        let channelByteCount = Int(expectedFrameCount) * MemoryLayout<Float>.size
        data.withUnsafeBytes { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return }
            for channel in 0..<Int(format.channelCount) {
                let source = baseAddress.advanced(by: channel * channelByteCount)
                UnsafeMutableRawPointer(channelData[channel]).copyMemory(from: source, byteCount: channelByteCount)
            }
        }
        return buffer
    }
    private func saveToneBufferToDisk(_ buffer: AVAudioPCMBuffer, key: String) {
        saveBufferToDisk(buffer, key: key, directoryName: toneCacheDirectoryName)
    }
    private func saveBufferToDisk(_ buffer: AVAudioPCMBuffer, key: String, directoryName: String) {
        guard
            let fileURL = cacheFileURL(for: key, directoryName: directoryName),
            let channelData = buffer.floatChannelData
        else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var data = Data()
            let frameCount = Int(buffer.frameLength)
            data.reserveCapacity(frameCount * Int(buffer.format.channelCount) * MemoryLayout<Float>.size)
            for channel in 0..<Int(buffer.format.channelCount) {
                let rawSamples = UnsafeRawBufferPointer(
                    start: channelData[channel],
                    count: frameCount * MemoryLayout<Float>.size
                )
                data.append(contentsOf: rawSamples)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.audio.error("Audio cache write failed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    private func toneBuffer(
        frequency: Double,
        duration: TimeInterval,
        gain: Float,
        dampingFactor: Double
    ) -> AVAudioPCMBuffer? {
        guard let format = audioFormat() else {
            return nil
        }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            return nil
        }
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let normalizedTime = time / duration
            let envelope = amplitudeEnvelope(time: time, normalizedTime: normalizedTime)
            let damping = exp(-dampingFactor * normalizedTime)
            let left = pianoSample(frequency: frequency * 0.9996, time: time, stereoOffset: -0.5)
            let right = pianoSample(frequency: frequency * 1.0004, time: time, stereoOffset: 0.5)
            let finalGain = envelope * Float(damping) * gain
            channelData[0][frame] = softClip(left * finalGain)
            if Int(format.channelCount) > 1 {
                channelData[1][frame] = softClip(right * finalGain)
            }
        }
        return buffer
    }
    private func celebrationMelodyBuffer(number: Int) -> AVAudioPCMBuffer? {
        guard let melody = Self.celebrationMelodies.first(where: { $0.number == number }) else { return nil }
        return cachedOrCreateCelebrationMelodyBuffer(melody: melody)
    }
    private func cachedOrCreateCelebrationMelodyBuffer(melody: CelebrationMelody) -> AVAudioPCMBuffer? {
        let key = celebrationMelodyBufferKey(number: melody.number)
        let expectedFrameCount = celebrationMelodyFrameCount(notes: melody.notes)
        if let diskBuffer = loadCachedBufferFromDisk(
            key: key,
            directoryName: celebrationMelodyCacheDirectoryName,
            expectedFrameCount: expectedFrameCount
        ) {
            return diskBuffer
        }
        guard let buffer = melodyBuffer(notes: melody.notes) else { return nil }
        saveBufferToDisk(buffer, key: key, directoryName: celebrationMelodyCacheDirectoryName)
        return buffer
    }
    private func celebrationMelodyBufferKey(number: Int) -> String {
        "melody:\(number)"
    }
    private func celebrationMelodyFrameCount(notes: [MelodyNote]) -> AVAudioFrameCount {
        let totalDuration = notes.reduce(0.0) { $0 + $1.duration } + 0.18
        return AVAudioFrameCount(sampleRate * totalDuration)
    }
    private func melodyBuffer(notes: [MelodyNote]) -> AVAudioPCMBuffer? {
        guard let format = audioFormat() else {
            return nil
        }
        let frameCount = celebrationMelodyFrameCount(notes: notes)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            return nil
        }
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(frameCount) {
                channelData[channel][frame] = 0
            }
        }
        var noteStartFrame = 0
        for note in notes {
            let noteFrameCount = max(1, Int(sampleRate * note.duration))
            let pitchFrequency = frequency(letter: note.letter, accidental: note.accidental, octave: note.octave)
            for frame in 0..<noteFrameCount {
                let targetFrame = noteStartFrame + frame
                guard targetFrame < Int(frameCount) else { break }
                let time = Double(frame) / sampleRate
                let normalizedTime = time / note.duration
                let envelope = melodyAmplitudeEnvelope(time: time, normalizedTime: normalizedTime)
                let left = pianoSample(frequency: pitchFrequency * 0.9996, time: time, stereoOffset: -0.5)
                let right = pianoSample(frequency: pitchFrequency * 1.0004, time: time, stereoOffset: 0.5)
                let finalGain = envelope * note.gain
                channelData[0][targetFrame] = softClip(channelData[0][targetFrame] + left * finalGain)
                if Int(format.channelCount) > 1 {
                    channelData[1][targetFrame] = softClip(channelData[1][targetFrame] + right * finalGain)
                }
            }
            noteStartFrame += noteFrameCount
        }
        return buffer
    }
    private func effectiveSingleNotePlaybackDuration() -> TimeInterval {
        max(0.18, toneDuration - replayTailTrim)
    }
    private func pianoSample(frequency: Double, time: Double, stereoOffset: Double) -> Float {
        let detunedStrings = [-0.0012, 0.0, 0.0011]
        let harmonicProfile: [(Double, Double)] = [
            (1.000, 1.00),
            (2.004, 0.22),
            (3.012, 0.09),
            (4.024, 0.035),
            (5.040, 0.012)
        ]
        let keyBrightness = min(max((frequency - 130.81) / 1_000.0, 0.0), 1.0)
        let body = detunedStrings.enumerated().reduce(0.0) { partialMix, string in
            let (index, detune) = string
            let panDetune = stereoOffset * 0.00045 * Double(index + 1)
            let stringDecay = exp(-(0.88 + keyBrightness * 1.2 + Double(index) * 0.09) * time)
            let stringTone = harmonicProfile.reduce(0.0) { harmonicMix, harmonic in
                let partialFrequency = frequency * harmonic.0 * (1.0 + detune + panDetune)
                let phase = 2.0 * Double.pi * partialFrequency * time
                let partialDamping = exp(-time * harmonic.0 * (0.38 + keyBrightness * 0.9))
                return harmonicMix + sin(phase) * harmonic.1 * partialDamping
            }
            return partialMix + stringTone * stringDecay
        }
        let hammer = filteredNoise(seed: Int(frequency.rounded()), time: time) * exp(-44.0 * time) * 0.025
        let resonance =
            sin(2.0 * Double.pi * frequency * 0.5 * time) * exp(-1.65 * time) * 0.045 +
            sin(2.0 * Double.pi * frequency * 1.5 * time) * exp(-2.6 * time) * 0.012
        return Float(body * 0.34 + hammer + resonance)
    }
    private func amplitudeEnvelope(time: Double, normalizedTime: Double) -> Float {
        let attack = smoothAttack(time: time, duration: 0.026)
        let earlyDecay = 0.62 * exp(-1.62 * time)
        let tailDecay = 0.38 * exp(-0.42 * time)
        let release = smoothRelease(normalizedTime: normalizedTime, start: 0.76)
        return Float(attack * (earlyDecay + tailDecay) * release)
    }
    private func melodyAmplitudeEnvelope(time: Double, normalizedTime: Double) -> Float {
        let attack = smoothAttack(time: time, duration: 0.022)
        let decay = 0.74 * exp(-2.1 * time) + 0.26 * exp(-0.76 * time)
        let release = smoothRelease(normalizedTime: normalizedTime, start: 0.72)
        return Float(attack * decay * release)
    }
    private func smoothAttack(time: Double, duration: Double) -> Double {
        let progress = min(max(time / duration, 0.0), 1.0)
        return progress * progress * (3.0 - 2.0 * progress)
    }
    private func smoothRelease(normalizedTime: Double, start: Double) -> Double {
        guard normalizedTime > start else { return 1.0 }
        let progress = min(max((normalizedTime - start) / (1.0 - start), 0.0), 1.0)
        return 1.0 - progress * progress * (3.0 - 2.0 * progress)
    }
    private func softClip(_ sample: Float) -> Float {
        tanh(sample * 1.15) / 1.15
    }
    private func filteredNoise(seed: Int, time: Double) -> Double {
        let components = [1.0, 1.55, 2.2]
        return components.enumerated().reduce(0.0) { mix, component in
            let phaseOffset = Double((seed + component.offset * 37) % 360) * .pi / 180.0
            let frequency = 900.0 + component.element * 520.0
            return mix + sin(2.0 * .pi * frequency * time + phaseOffset) / Double(component.offset + 1)
        } / 2.2
    }
}
/// Identifies a short public-domain melody excerpt used as completion feedback.
private struct CelebrationMelody {
    let number: Int
    let notes: [MelodyNote]
}
/// Represents one synthesized note in a baked melody excerpt.
private struct MelodyNote {
    private static let tempoScale = 1.65
    let letter: String
    let accidental: Accidental
    let octave: Int
    let duration: TimeInterval
    let gain: Float
    init(_ letter: String, _ accidental: Accidental = .natural, octave: Int, duration: TimeInterval, gain: Float = 0.32) {
        self.letter = letter
        self.accidental = accidental
        self.octave = octave
        self.duration = duration * Self.tempoScale
        self.gain = gain
    }
}
/// Describes one note of a celebration melody as a keyboard tap.
struct CelebrationMelodyKeyPress {
    let answer: NoteAnswer
    let octave: Int
    let duration: TimeInterval
}
private extension NoteSoundPlayer {
    static let celebrationMelodies: [CelebrationMelody] = [
        CelebrationMelody(
            number: 1,
            notes: [
                MelodyNote("E", octave: 4, duration: 0.22),
                MelodyNote("E", octave: 4, duration: 0.22),
                MelodyNote("F", octave: 4, duration: 0.22),
                MelodyNote("G", octave: 4, duration: 0.22),
                MelodyNote("G", octave: 4, duration: 0.22),
                MelodyNote("F", octave: 4, duration: 0.22),
                MelodyNote("E", octave: 4, duration: 0.22),
                MelodyNote("D", octave: 4, duration: 0.32)
            ]
        ),
        CelebrationMelody(
            number: 2,
            notes: [
                MelodyNote("G", octave: 4, duration: 0.16),
                MelodyNote("D", octave: 5, duration: 0.16),
                MelodyNote("G", octave: 4, duration: 0.16),
                MelodyNote("D", octave: 5, duration: 0.16),
                MelodyNote("G", octave: 4, duration: 0.16),
                MelodyNote("D", octave: 5, duration: 0.16),
                MelodyNote("G", octave: 4, duration: 0.28),
                MelodyNote("B", octave: 4, duration: 0.16),
                MelodyNote("D", octave: 5, duration: 0.16),
                MelodyNote("B", octave: 4, duration: 0.16),
                MelodyNote("D", octave: 5, duration: 0.16),
                MelodyNote("B", octave: 4, duration: 0.16),
                MelodyNote("D", octave: 5, duration: 0.34)
            ]
        ),
        CelebrationMelody(
            number: 3,
            notes: [
                MelodyNote("G", octave: 4, duration: 0.24),
                MelodyNote("E", octave: 4, duration: 0.12),
                MelodyNote("F", .sharp, octave: 4, duration: 0.12),
                MelodyNote("G", octave: 4, duration: 0.12),
                MelodyNote("A", octave: 4, duration: 0.12),
                MelodyNote("B", octave: 4, duration: 0.24),
                MelodyNote("C", octave: 5, duration: 0.12),
                MelodyNote("D", octave: 5, duration: 0.12),
                MelodyNote("E", octave: 5, duration: 0.24)
            ]
        ),
        CelebrationMelody(
            number: 4,
            notes: [
                MelodyNote("E", octave: 5, duration: 0.16),
                MelodyNote("D", .sharp, octave: 5, duration: 0.16),
                MelodyNote("E", octave: 5, duration: 0.16),
                MelodyNote("D", .sharp, octave: 5, duration: 0.16),
                MelodyNote("E", octave: 5, duration: 0.16),
                MelodyNote("B", octave: 4, duration: 0.16),
                MelodyNote("D", octave: 5, duration: 0.16),
                MelodyNote("C", octave: 5, duration: 0.16),
                MelodyNote("A", octave: 4, duration: 0.32)
            ]
        ),
        CelebrationMelody(
            number: 5,
            notes: [
                MelodyNote("G", octave: 4, duration: 0.2),
                MelodyNote("D", octave: 4, duration: 0.2),
                MelodyNote("G", octave: 4, duration: 0.2),
                MelodyNote("B", octave: 4, duration: 0.2),
                MelodyNote("D", octave: 5, duration: 0.2),
                MelodyNote("G", octave: 5, duration: 0.34)
            ]
        )
    ]
}
