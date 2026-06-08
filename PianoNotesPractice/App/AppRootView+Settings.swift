import Combine
import Foundation
import SwiftUI

extension AppRootView {
    /// Keeps Store capture prompts visible long enough to read after Continue is enabled.
    var storeTutorialCapturePromptDisplayDelay: TimeInterval {
        max(NoteTutorial.promptContinueDelay, 1.9)
    }

    func debugToggleSkipTutorialsAndCelebrations() {
        #if DEBUG
        debugSkipsTutorialsAndCelebrations.toggle()
        #endif
    }

    func handleDebugSkipTutorialsAndCelebrationsChange(_ shouldSkip: Bool) {
        #if DEBUG
        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = nil
        pendingReplayTask?.cancel()
        pendingReplayTask = nil
        isAdvancingToNextNote = false
        isReplayFeedbackDelayComplete = false
        isReplayWaitingForPlayback = false

        isShowingTutorialCompletion = false
        celebrationReasonText = nil
        cancelTutorialCompletionCelebration()
        noteSoundPlayer.stopPlayback()
        resetNoteQueue()
        debugFinishAppearedTutorialsAndCelebrationsIfNeeded()
        nextNote()

        if !shouldSkip {
            playWelcomeCelebrationMusicIfNeeded()
        }
        #endif
    }

    var debugSkippablePromptSignature: String {
        #if DEBUG
        let kind = pendingTutorialKind.map(NoteTutorial.idPrefix(for:)) ?? "none"
        let welcome = pendingShouldShowWelcomeCelebration(kind: pendingTutorialKind) ? "welcome" : "no-welcome"
        let staffPrompt = pendingStaffTutorialHelperText(kind: pendingTutorialKind) ?? "no-staff"
        let keyboardPrompt = pendingKeyboardHelperText(kind: pendingTutorialKind) ?? "no-keyboard"
        let celebration = celebrationReasonText ?? "no-celebration"

        return [kind, welcome, staffPrompt, keyboardPrompt, celebration].joined(separator: "|")
        #else
        return ""
        #endif
    }

    func debugFinishAppearedTutorialsAndCelebrationsIfNeeded() {
        #if DEBUG
        guard debugSkipsTutorialsAndCelebrations else { return }

        let appearedTutorialKind = pendingTutorialKind
        let appearedStaffPrompt = pendingStaffTutorialHelperText(kind: appearedTutorialKind)
        let appearedKeyboardPrompt = pendingKeyboardHelperText(kind: appearedTutorialKind)
        let appearedWelcomeCelebration = pendingShouldShowWelcomeCelebration(kind: appearedTutorialKind)

        if appearedWelcomeCelebration {
            acknowledgedStaffTutorialPromptIDs.insert(
                staffTutorialPromptID(for: NoteTutorial.welcomeTutorialText, kind: appearedTutorialKind)
            )
        }

        if let appearedTutorialKind {
            switch appearedTutorialKind {
            case .firstOctave:
                hasCompletedFirstOctaveTutorial = true
            case .accidentals:
                hasCompletedAccidentalTutorial = true
            }

            tutorialNoteIndex = 0
        }

        if let appearedStaffPrompt {
            acknowledgeTutorialPrompt(
                appearedStaffPrompt,
                kind: appearedTutorialKind
            )
        }

        if let appearedKeyboardPrompt {
            acknowledgedStaffTutorialPromptIDs.insert(
                staffTutorialPromptID(for: appearedKeyboardPrompt, kind: appearedTutorialKind)
            )
        }

        celebrationReasonText = nil
        isShowingTutorialCompletion = false
        cancelTutorialCompletionCelebration()
        noteSoundPlayer.stopPlayback()
        #endif
    }

    func debugToggleAllSounds() {
        let shouldEnableSounds = !(isToneEnabled && isKeyboardEffectEnabled)
        isToneEnabled = shouldEnableSounds
        isKeyboardEffectEnabled = shouldEnableSounds

        if !shouldEnableSounds {
            isStaffVisible = true
            noteSoundPlayer.stopPlayback()
        }

        persistPracticeModeSettings()
        isKeyboardEffectEnabledStorage = isKeyboardEffectEnabled
    }

    func debugPlayMelody() {
        playCelebrationMelody(number: nextDebugMelodyNumber)
    }

    func debugPurgeAudioCache() {
        #if DEBUG
        noteSoundPlayer.purgeAudioCache()
        #endif
    }

    func randomCelebrationMelodyNumber() -> Int {
        let melodyCount = max(noteSoundPlayer.celebrationMelodyCount, 1)
        let candidates = Array(1...melodyCount).filter { $0 != lastCelebrationMelodyNumber }
        return candidates.randomElement() ?? nextDebugMelodyNumber
    }

    func playRandomCelebrationMelody(reasonText: String? = nil, onFinished: (() -> Void)? = nil) {
        playCelebrationMelody(
            number: randomCelebrationMelodyNumber(),
            reasonText: reasonText,
            onFinished: onFinished
        )
    }

    func playWelcomeCelebrationMusicIfNeeded() {
        #if STORE_TUTORIAL_CAPTURE
        guard hasStartedStoreTutorialCaptureWelcome else { return }
        #endif
        guard shouldShowWelcomeCelebration else { return }
        guard celebrationReasonText == nil else { return }
        guard selectedTab == .home else { return }

        AppLog.tutorial.info("Starting welcome celebration")
        playRandomCelebrationMelody(reasonText: NoteTutorial.welcomeCelebrationText)
    }

    func playCelebrationMelody(
        number: Int,
        reasonText: String? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        guard !debugSkipsTutorialsAndCelebrations else {
            AppLog.tutorial.info("Skipping celebration because debug skip is enabled")
            cancelMelodyKeyboardPlayback()
            celebrationReasonText = nil
            tutorialCelebrationHighlightedAnswers = []
            onFinished?()
            return
        }

        cancelMelodyKeyboardPlayback()
        lastCelebrationMelodyNumber = number
        celebrationReasonText = reasonText
        AppLog.tutorial.info("Starting celebration melody; number \(number, privacy: .public)")
        let keyPresses = noteSoundPlayer.celebrationMelodyKeyPresses(number: number)
        let finishDelay = melodyDuration(for: keyPresses)

        guard isOnScreenKeyboardVisible else {
            playCelebrationMelodySoundIfEnabled(number: number)
            scheduleCelebrationFinish(after: finishDelay, onFinished: onFinished)
            return
        }

        guard !keyPresses.isEmpty else {
            playCelebrationMelodySoundIfEnabled(number: number)
            scheduleCelebrationFinish(after: finishDelay, onFinished: onFinished)
            return
        }

        keyboardCelebrationMelodyNumber = number
        playCelebrationMelodySoundIfEnabled(number: number)
        var accumulatedDelay: TimeInterval = 0

        for keyPress in keyPresses {
            let keyPressDelay = accumulatedDelay
            let task = Task { @MainActor in
                try? await Task.sleep(for: .seconds(keyPressDelay))
                guard !Task.isCancelled else { return }
                tutorialCelebrationHighlightedAnswers = [keyPress.answer]
                simulateKeyboardPress(
                    answer: keyPress.answer,
                    octave: keyPress.octave,
                    submitsGuess: false,
                    forcesSound: false,
                    // Celebration audio stays in the melody buffer because notes have different lengths; key animation only mirrors it visually.
                    suppressesSound: true
                )
            }

            pendingMelodyKeyboardTasks.append(task)
            accumulatedDelay += keyPress.duration
        }

        let finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(accumulatedDelay + 0.12))
            guard !Task.isCancelled else { return }
            tutorialCelebrationHighlightedAnswers = []
            keyboardCelebrationMelodyNumber = nil
            onFinished?()
        }
        pendingMelodyKeyboardTasks.append(finishTask)
    }

    func playCelebrationMelodySoundIfEnabled(number: Int) {
        guard isKeyboardEffectEnabled else { return }

        noteSoundPlayer.playCelebrationMelody(number: number)
    }

    func cancelMelodyKeyboardPlayback() {
        pendingMelodyKeyboardTasks.forEach { $0.cancel() }
        pendingMelodyKeyboardTasks.removeAll()
        keyboardCelebrationMelodyNumber = nil
    }

    func melodyDuration(for keyPresses: [CelebrationMelodyKeyPress]) -> TimeInterval {
        max(keyPresses.reduce(0) { $0 + $1.duration } + 0.12, 0.5)
    }

    func scheduleCelebrationFinish(after delay: TimeInterval, onFinished: (() -> Void)?) {
        let finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            onFinished?()
        }
        pendingMelodyKeyboardTasks.append(finishTask)
    }

    func loadInitialNoteIfNeeded() {
        guard !hasLoadedInitialNote else { return }
        AppLog.practice.info("Loading initial Practice state")
        hasLoadedInitialNote = true
        configureStoreTutorialCaptureIfNeeded()
        normalizeClefSelectionForSequenceLength()
        ensurePracticeModeEnabled()
        nextNote(animated: false)
        playWelcomeCelebrationMusicIfNeeded()
        startStoreTutorialCaptureAutomationIfNeeded()
    }

    func configureStoreTutorialCaptureIfNeeded() {
        #if STORE_TUTORIAL_CAPTURE
        AppLog.tutorial.info("Configuring Store tutorial capture state")
        selectedClef = .treble
        selectedClefStorage = selectedClef.rawValue
        includeSharps = false
        includeFlats = false
        includeSharpsStorage = includeSharps
        includeFlatsStorage = includeFlats
        isStaffVisible = true
        isToneEnabled = false
        isKeyboardEffectEnabled = true
        isNoteBounceEffectEnabled = false
        isHelperGlowEnabled = true
        isTempoMeterEnabled = false
        usesNativeDarkPracticeColors = false
        sequenceLength = 1
        selectedOctaves = [4]
        persistPracticeModeSettings()
        isKeyboardEffectEnabledStorage = isKeyboardEffectEnabled
        isNoteBounceEffectEnabledStorage = isNoteBounceEffectEnabled
        isHelperGlowEnabledStorage = isHelperGlowEnabled
        isTempoMeterEnabledStorage = isTempoMeterEnabled
        usesNativeDarkPracticeColorsStorage = usesNativeDarkPracticeColors
        sequenceLengthStorage = sequenceLength
        persistSelectedOctaves()
        hasCompletedFirstOctaveTutorial = false
        hasCompletedAccidentalTutorial = false
        hasAcknowledgedBurstMeterHelper = false
        tutorialNoteIndex = 0
        isShowingTutorialCompletion = false
        cancelTutorialCompletionCelebration()
        celebrationReasonText = NoteTutorial.welcomeCelebrationText
        acknowledgedStaffTutorialPromptIDs.removeAll()
        dismissedOctaveIntroductionID = nil
        milestoneBurstProgress = 0
        hasStartedStoreTutorialCaptureWelcome = false
        resetNoteQueue()
        #endif
    }

    func startStoreTutorialCaptureAutomationIfNeeded() {
        #if STORE_TUTORIAL_CAPTURE
        guard !hasStartedStoreTutorialCaptureAutomation else { return }
        AppLog.tutorial.info("Starting Store tutorial capture automation")
        hasStartedStoreTutorialCaptureAutomation = true
        scheduleStoreTutorialCaptureStep(after: 10)
        #endif
    }

    func beginStoreTutorialPromptDisplayIfNeeded(id: String) -> Bool {
        #if STORE_TUTORIAL_CAPTURE
        guard storeTutorialCapturePromptID != id else { return false }

        storeTutorialCapturePromptID = id
        scheduleStoreTutorialCaptureStep(after: storeTutorialCapturePromptDisplayDelay)
        return true
        #else
        return false
        #endif
    }

    func scheduleStoreTutorialCaptureStep(after delay: TimeInterval) {
        #if STORE_TUTORIAL_CAPTURE
        pendingStoreTutorialCaptureTask?.cancel()
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            performStoreTutorialCaptureStep()
        }
        pendingStoreTutorialCaptureTask = task
        #endif
    }

    func performStoreTutorialCaptureStep() {
        #if STORE_TUTORIAL_CAPTURE
        if !hasStartedStoreTutorialCaptureWelcome {
            hasStartedStoreTutorialCaptureWelcome = true
            AppLog.tutorial.info("Starting Store capture Welcome animation after warm-up")
            isNoteBounceEffectEnabled = true
            celebrationReasonText = NoteTutorial.welcomeCelebrationText + "\u{200B}"
            playRandomCelebrationMelody(reasonText: celebrationReasonText)
            scheduleStoreTutorialCaptureStep(after: 1.8)
            return
        }

        guard selectedTab == .home else {
            selectedTab = .home
            scheduleStoreTutorialCaptureStep(after: 0.5)
            return
        }

        if isShowingTutorialCompletion || celebrationReasonText == NoteTutorial.celebrationReasonText(kind: .firstOctave) {
            pendingStoreTutorialCaptureTask = nil
            return
        }

        if celebrationReasonText?.hasPrefix(NoteTutorial.welcomeCelebrationText) == true {
            guard !beginStoreTutorialPromptDisplayIfNeeded(id: "welcome-celebration") else { return }
            storeTutorialCapturePromptID = nil
            acknowledgeCelebration()
            scheduleStoreTutorialCaptureStep(after: 0.3)
            return
        }

        if let octaveIntroduction = activeOctaveIntroduction {
            guard !beginStoreTutorialPromptDisplayIfNeeded(id: octaveIntroduction.id) else { return }
            storeTutorialCapturePromptID = nil
            acknowledgeOctaveIntroduction()
            scheduleStoreTutorialCaptureStep(after: 0.3)
            return
        }

        if let staffTutorialHelperText {
            guard !beginStoreTutorialPromptDisplayIfNeeded(id: "staff-\(staffTutorialHelperText)") else { return }
            storeTutorialCapturePromptID = nil
            acknowledgeStaffTutorialPrompt()
            scheduleStoreTutorialCaptureStep(after: 0.3)
            return
        }

        if let keyboardTutorialHelperText {
            guard !beginStoreTutorialPromptDisplayIfNeeded(id: "keyboard-\(keyboardTutorialHelperText)") else { return }
            storeTutorialCapturePromptID = nil
            acknowledgeKeyboardTutorialPrompt()
            scheduleStoreTutorialCaptureStep(after: 0.3)
            return
        }

        if isTutorialActive, !isAdvancingToNextNote, let expectedSequenceNote {
            simulateKeyboardPress(
                answer: NotePitch.displayKeyboardAnswer(for: expectedSequenceNote, answerOptions: answerOptions),
                submitsGuess: true
            )
            scheduleStoreTutorialCaptureStep(after: 0.55)
            return
        }

        scheduleStoreTutorialCaptureStep(after: 0.3)
        #endif
    }

    func updateClefMode(_ clefMode: ClefMode) {
        let normalizedClefMode = normalizedClefMode(for: clefMode)
        guard selectedClef != normalizedClefMode else { return }
        AppLog.practice.info("Clef mode changed to \(normalizedClefMode.rawValue, privacy: .public)")
        selectedClef = normalizedClefMode
        selectedClefStorage = normalizedClefMode.rawValue
        resetNoteQueue()
        nextNote()
        playWelcomeCelebrationMusicIfNeeded()
    }

    func toggleAccidentals() {
        let shouldIncludeAccidentals = !(includeSharps && includeFlats)
        AppLog.practice.info("Sharps and Flats changed to \(shouldIncludeAccidentals, privacy: .public)")
        includeSharps = shouldIncludeAccidentals
        includeFlats = shouldIncludeAccidentals
        includeSharpsStorage = includeSharps
        includeFlatsStorage = includeFlats
        resetNoteQueue()
        nextNote()
    }

    func updateSequenceLength(_ count: Int) {
        let validatedCount = NoteQuizGenerator.sequenceLength(from: count)
        AppLog.practice.info("Sequence length changed to \(validatedCount, privacy: .public)")
        sequenceLength = validatedCount
        sequenceLengthStorage = validatedCount
        normalizeClefSelectionForSequenceLength()
        guard !isTutorialActive else {
            nextNote()
            return
        }
        let previousPlayedNote = lastPlayedPromptNote
        let updatedPromptSequence = quizGenerator.makePromptSequence(
            for: currentNote,
            sequenceLength: sequenceLength,
            avoidingAdjacentTo: previousPlayedNote
        )
        promptSequence = updatedPromptSequence
        currentNote = updatedPromptSequence.last ?? currentNote
        currentGuessIndex = 0
        hasFailedCurrentSequence = false
        resetPromptResponseTimer()
        noteAppearanceID += 1
        playNewPromptIfPracticeTabIsVisible()
    }

    func toggleStaffVisibility() {
        guard !isStaffVisible || isToneEnabled else { return }
        let updatedStaffVisibility = !isStaffVisible
        AppLog.practice.info("Staff visibility changed to \(updatedStaffVisibility, privacy: .public)")
        isStaffVisible = updatedStaffVisibility

        persistPracticeModeSettings()
    }

    func toggleTone() {
        guard !noteSoundPlayer.isPreparingAudioCache else { return }
        guard !isToneEnabled || isStaffVisible else { return }
        let updatedToneEnabled = !isToneEnabled
        AppLog.audio.info("Tone prompts changed to \(updatedToneEnabled, privacy: .public)")
        isToneEnabled = updatedToneEnabled

        persistPracticeModeSettings()

        if isToneEnabled && !isStaffVisible {
            replayCurrentNote()
        } else {
            noteSoundPlayer.stopPlayback()
        }
    }

    func toggleKeyboardEffect() {
        guard !noteSoundPlayer.isPreparingAudioCache else { return }
        isKeyboardEffectEnabled.toggle()
        AppLog.audio.info("Keyboard effect changed to \(self.isKeyboardEffectEnabled, privacy: .public)")
        isKeyboardEffectEnabledStorage = isKeyboardEffectEnabled

        if !isKeyboardEffectEnabled {
            noteSoundPlayer.stopPlayback()
        }
    }

    func toggleNoteBounceEffect() {
        isNoteBounceEffectEnabled.toggle()
        AppLog.practice.info("Note bounce effect changed to \(self.isNoteBounceEffectEnabled, privacy: .public)")
        isNoteBounceEffectEnabledStorage = isNoteBounceEffectEnabled
    }

    func toggleHelperGlow() {
        isHelperGlowEnabled.toggle()
        AppLog.practice.info("Helper glow changed to \(self.isHelperGlowEnabled, privacy: .public)")
        isHelperGlowEnabledStorage = isHelperGlowEnabled

        if !isHelperGlowEnabled {
            cancelKeyboardHint()
        }
    }

    func toggleTempoMeter() {
        isTempoMeterEnabled.toggle()
        AppLog.practice.info("Tempo meter changed to \(self.isTempoMeterEnabled, privacy: .public)")
        isTempoMeterEnabledStorage = isTempoMeterEnabled

        if isTempoMeterEnabled {
            lastMilestoneBurstDrainDate = Date()
        } else {
            milestoneBurstProgress = 0
        }
    }

    func toggleNativeDarkPracticeColors() {
        usesNativeDarkPracticeColors.toggle()
        AppLog.practice.info("Native dark Practice colors changed to \(self.usesNativeDarkPracticeColors, privacy: .public)")
        usesNativeDarkPracticeColorsStorage = usesNativeDarkPracticeColors
    }

    func resetPromptResponseTimer(at date: Date = Date()) {
        cancelKeyboardHint()
        accumulatedPromptResponseTime = 0
        promptResponseTimeStartedAt = selectedTab == .home ? date : nil
        scheduleKeyboardHintIfNeeded(at: date)
    }

    func pausePromptResponseTimer(at date: Date = Date()) {
        cancelKeyboardHint()
        guard let promptResponseTimeStartedAt else { return }
        accumulatedPromptResponseTime += max(date.timeIntervalSince(promptResponseTimeStartedAt), 0)
        self.promptResponseTimeStartedAt = nil
    }

    func resumePromptResponseTimer(at date: Date = Date()) {
        guard promptResponseTimeStartedAt == nil else { return }
        promptResponseTimeStartedAt = date
        scheduleKeyboardHintIfNeeded(at: date)
    }

    func currentPromptResponseTime(at date: Date = Date()) -> TimeInterval {
        guard let promptResponseTimeStartedAt else { return accumulatedPromptResponseTime }
        return accumulatedPromptResponseTime + max(date.timeIntervalSince(promptResponseTimeStartedAt), 0)
    }

    func scheduleKeyboardHintIfNeeded(at date: Date = Date()) {
        guard isHelperGlowEnabled else { return }
        guard selectedTab == .home else { return }
        guard isOnScreenKeyboardVisible else { return }
        guard activeOctaveIntroduction == nil else { return }
        guard !isTutorialActive else { return }
        guard staffTutorialHelperText == nil, keyboardTutorialHelperText == nil else { return }
        guard celebrationReasonText == nil else { return }
        guard !isAdvancingToNextNote, !isShowingTutorialCompletion else { return }
        guard let expectedNote = expectedSequenceNote else { return }

        let delay = max(activeQuickAnswerThreshold * 2 - currentPromptResponseTime(at: date), 0)
        let hintAnswer = NotePitch.displayKeyboardAnswer(for: expectedNote, answerOptions: answerOptions)
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard isHelperGlowEnabled else { return }
            guard selectedTab == .home else { return }
            guard isOnScreenKeyboardVisible else { return }
            guard activeOctaveIntroduction == nil else { return }
            guard !isTutorialActive else { return }
            guard staffTutorialHelperText == nil, keyboardTutorialHelperText == nil else { return }
            guard celebrationReasonText == nil else { return }
            guard !isAdvancingToNextNote, !isShowingTutorialCompletion else { return }
            guard let currentExpectedNote = expectedSequenceNote else { return }
            guard NotePitch.displayKeyboardAnswer(for: currentExpectedNote, answerOptions: answerOptions) == hintAnswer else { return }

            delayedKeyboardHighlightedAnswers = [hintAnswer]
        }

        pendingKeyboardHintTask = task
    }

    func cancelKeyboardHint() {
        pendingKeyboardHintTask?.cancel()
        pendingKeyboardHintTask = nil
        delayedKeyboardHighlightedAnswers = []
    }

    func ensurePracticeModeEnabled() {
        guard !isStaffVisible && !isToneEnabled else { return }

        isStaffVisible = true
        persistPracticeModeSettings()
    }

    func persistPracticeModeSettings() {
        isStaffVisibleStorage = isStaffVisible
        isToneEnabledStorage = isToneEnabled
    }

    func replayCurrentNote() {
        pendingReplayTask?.cancel()
        pendingReplayTask = nil
        isReplayFeedbackDelayComplete = false
        isReplayWaitingForPlayback = false
        guard isToneEnabled else { return }
        noteSoundPlayer.play(notes: remainingCueSoundNotes)
    }

    func playKeyboardEffect(_ answer: NoteAnswer, octave: Int?, force: Bool) {
        guard force || activeOctaveIntroduction == nil else { return }
        guard force || staffTutorialHelperText == nil else { return }
        guard force || keyboardTutorialHelperText == nil else { return }
        guard force || isKeyboardEffectEnabled else { return }
        let octave = octave ?? expectedSequenceNote?.octave ?? currentNote.octave
        noteSoundPlayer.playKeyboardEffect(for: answer, octave: octave)
    }

    func simulateKeyboardPress(
        answer: NoteAnswer,
        octave: Int? = nil,
        submitsGuess: Bool,
        forcesSound: Bool = false,
        suppressesSound: Bool = false
    ) {
        let pulseTint: KeyboardPressPulseTint = submitsGuess ? .evaluated : .accent
        simulatedKeyboardPressID += 1
        simulatedKeyboardPress = SimulatedKeyboardPress(
            id: simulatedKeyboardPressID,
            answer: answer,
            octave: octave,
            submitsGuess: submitsGuess,
            forcesSound: forcesSound,
            suppressesSound: suppressesSound,
            pulseTint: pulseTint
        )
    }

    func playAppearedNotes() {
        guard isToneEnabled, isStaffVisible else { return }
        noteSoundPlayer.play(notes: remainingCueSoundNotes)
    }

    /// Returns the unanswered suffix of the displayed Cue for prompt and replay audio.
    var remainingCueSoundNotes: [QuizNote] {
        let sequence = displayedPromptSequence.isEmpty ? [displayedCurrentNote] : displayedPromptSequence
        guard sequence.indices.contains(displayedCurrentGuessIndex) else { return [displayedCurrentNote] }

        return Array(sequence.dropFirst(displayedCurrentGuessIndex))
    }

    func flash(_ color: Color, scale: Double = 1.035) {
        pendingFlashResetTask?.cancel()

        withAnimation(.easeOutCubic(duration: 0.12)) {
            flashColor = color
            noteScale = isNoteBounceEffectEnabled ? scale : 1.0
        }

        let resetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                flashColor = .clear
                noteScale = 1.0
            }
        }

        pendingFlashResetTask = resetTask
    }

    func toggleOctave(_ octave: Int) {
        if selectedOctaves.contains(octave) {
            guard selectedOctaves.count > 1 else { return }
            selectedOctaves.remove(octave)
        } else {
            selectedOctaves.insert(octave)
        }

        AppLog.practice.info("Selected octaves changed; count \(self.selectedOctaves.count, privacy: .public)")
        persistSelectedOctaves()
        resetNoteQueue()
        nextNote()
    }

    func practiceOnlyBucket(_ bucket: ScoreBucket) {
        let octave = bucket.octave

        guard availableOctaves.contains(octave) else { return }

        AppLog.practice.info("Practicing Progress bucket; clef \(bucket.clef.rawValue, privacy: .public), octave \(octave, privacy: .public)")
        selectPracticeBucket(bucket)
        resetNoteQueue()
        selectedTab = .home
        nextNote()
    }

    func selectPracticeBucket(_ bucket: ScoreBucket) {
        selectedClef = clefMode(for: bucket.clef)
        selectedClefStorage = selectedClef.rawValue
        selectedOctaves = [bucket.octave]
        persistSelectedOctaves()
    }

    func clefMode(for clef: Clef) -> ClefMode {
        switch clef {
        case .treble:
            return .treble
        case .bass:
            return .bass
        }
    }

    func isPracticingOnly(clef: Clef, octave: Int) -> Bool {
        selectedClef.allowedClefs == [clef] && activePracticeOctaves == [octave]
    }


}
