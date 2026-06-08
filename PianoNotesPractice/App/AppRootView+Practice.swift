import Combine
import Foundation
import SwiftUI

extension AppRootView {
    /// Resets transient Tutorial progress when a different Tutorial becomes active.
    func synchronizeTutorialProgress() {
        guard practiceSession.tutorials.activeTutorialID != tutorialProgressID else { return }

        practiceSession.tutorials.reset()
        practiceSession.tutorials.activeTutorialID = tutorialProgressID
        dismissedOctaveIntroductionID = nil
    }

    func nextNote(animated: Bool = true) {
        synchronizeTutorialProgress()
        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = nil
        pendingReplayTask?.cancel()
        pendingReplayTask = nil
        isAdvancingToNextNote = false
        isReplayFeedbackDelayComplete = false
        isReplayWaitingForPlayback = false

        if isTutorialActive {
            guard let next = currentTutorialNote else { return }
            AppLog.practice.info("Loading next tutorial Cue; index \(self.tutorialNoteIndex, privacy: .public)")
            updateOctaveIntroductionDismissal(for: next)
            currentNote = next
            promptSequence = [next]
            currentGuessIndex = 0
            hasFailedCurrentSequence = false
            resetPromptResponseTimer()
            noteAppearanceID += 1
            warmLikelyOctaveAudioCaches()
            playNewPromptIfPracticeTabIsVisible()
            return
        }

        let previousPlayedNote = lastPlayedPromptNote
        let next = quizGenerator.weightedRandomNote(
            excluding: [],
            avoidingAdjacentTo: sequenceLength == 1 ? previousPlayedNote : nil
        )

        AppLog.practice.info(
            "Loading next Practice Cue; clef \(next.clef.rawValue, privacy: .public), octave \(next.octave, privacy: .public), sequence length \(self.sequenceLength, privacy: .public)"
        )
        updateOctaveIntroductionDismissal(for: next)
        currentNote = next

        promptSequence = quizGenerator.makePromptSequence(
            for: next,
            sequenceLength: sequenceLength,
            avoidingAdjacentTo: previousPlayedNote
        )
        currentGuessIndex = 0
        hasFailedCurrentSequence = false
        resetPromptResponseTimer()
        noteAppearanceID += 1
        warmLikelyOctaveAudioCaches()
        playNewPromptIfPracticeTabIsVisible()
    }

    func playNewPromptIfPracticeTabIsVisible() {
        guard selectedTab == .home else { return }
        guard activeOctaveIntroduction == nil else { return }
        guard staffTutorialHelperText == nil else { return }
        guard keyboardTutorialHelperText == nil else { return }

        if isStaffVisible {
            playAppearedNotes()
        } else if isToneEnabled {
            replayCurrentNote()
        }
    }

    func answerMatchesCurrentSequence(_ answer: NoteAnswer) -> Bool {
        guard let expectedNote = expectedSequenceNote else { return false }
        return NotePitch.semitone(for: answer) == NotePitch.semitone(letter: expectedNote.letter, accidental: expectedNote.accidental)
    }

    func submitGuess(isCorrect: Bool) {
        guard activeOctaveIntroduction == nil else { return }
        guard !isGuidedTutorialActive else { return }
        guard !isAdvancingToNextNote else { return }
        guard !isShowingTutorialCompletion else { return }

        cancelKeyboardHint()
        let submittedAt = Date()
        let responseTime = currentPromptResponseTime(at: submittedAt)
        let submittedNote = expectedSequenceNote
        let canCountLearnedProgress = isCorrect
            && !hasFailedCurrentSequence
            && !isTutorialActive
            && !isGuidedTutorialActive
        let canFillMilestoneBurst = canCountLearnedProgress && responseTime < activeQuickAnswerThreshold

        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = nil
        pendingReplayTask?.cancel()
        pendingReplayTask = nil
        isReplayFeedbackDelayComplete = false
        isReplayWaitingForPlayback = false

        if let submittedNote {
            recordGuess(
                for: submittedNote,
                responseTime: responseTime,
                canCountLearnedProgress: canCountLearnedProgress
            )
        }

        AppLog.practice.info(
            "Practice guess submitted; correct \(isCorrect, privacy: .public), tutorial active \(self.isTutorialActive, privacy: .public), response time \(responseTime, privacy: .public)"
        )

        if isCorrect {
            monitorCompletedOctaveNextStepsReminder(for: submittedNote)

            if canFillMilestoneBurst {
                updateMilestoneBurstProgress(isCorrect: true)
            }

            if currentGuessIndex + 1 < promptSequence.count {
                currentGuessIndex += 1
                AppLog.practice.info("Advanced within prompt sequence; next guess index \(self.currentGuessIndex, privacy: .public)")
                resetPromptResponseTimer(at: submittedAt)
                flash(Theme.selectedControlTint)
            } else if isTutorialActive {
                completeCurrentTutorialNote()
            } else {
                completeCurrentSequence()
            }
        } else {
            resetCompletedOctaveNextStepsMonitor()
            hasFailedCurrentSequence = true
            resetPromptResponseTimer(at: submittedAt)
            if !isTutorialActive {
                updateMilestoneBurstProgress(isCorrect: false)
            }
            flash(Theme.failedAnswerFeedbackTint, scale: 0.965)
            if isToneEnabled {
                isReplayWaitingForPlayback = !noteSoundPlayer.isReplayReady

                let replayTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    isReplayFeedbackDelayComplete = true

                    if !isReplayWaitingForPlayback {
                        replayCurrentNote()
                    }
                }

                pendingReplayTask = replayTask
            }
        }
    }

    func completeCurrentSequence() {
        guard !isAdvancingToNextNote else { return }

        AppLog.practice.info("Practice sequence completed")
        isAdvancingToNextNote = true
        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = nil
        pendingReplayTask?.cancel()
        pendingReplayTask = nil
        isReplayFeedbackDelayComplete = false
        isReplayWaitingForPlayback = false

        noteDisappearanceID += 1

        flash(Theme.selectedControlTint)
        let advanceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            nextNote()
        }

        pendingAdvanceTask = advanceTask
    }

    func advanceGuidedTutorial() {
        guard let activeGuidedTutorialID else { return }

        let lastStepIndex: Int
        switch activeGuidedTutorialID {
        case .middleC:
            lastStepIndex = MiddleCTutorialStep.handRange.rawValue
        case .referenceNotes:
            lastStepIndex = ReferenceNoteTutorialStep.positionReading.rawValue
        case .firstOctave, .accidentals:
            return
        }

        if tutorialNoteIndex < lastStepIndex {
            tutorialNoteIndex += 1
            currentGuessIndex = 0
            hasFailedCurrentSequence = false
            resetPromptResponseTimer()
            noteAppearanceID += 1
        } else {
            finishGuidedTutorial()
        }
    }

    func completeCurrentTutorialNote() {
        guard !isAdvancingToNextNote else { return }
        guard activeTutorialKind != nil else { return }

        AppLog.tutorial.info("Tutorial Cue completed; index \(self.tutorialNoteIndex, privacy: .public)")
        isAdvancingToNextNote = true
        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = nil
        pendingReplayTask?.cancel()
        pendingReplayTask = nil
        isReplayFeedbackDelayComplete = false
        isReplayWaitingForPlayback = false
        noteDisappearanceID += 1
        flash(Theme.selectedControlTint)

        let isLastTutorialNote = tutorialNoteIndex >= tutorialNotes.count - 1
        if isLastTutorialNote {
            startTutorialCompletionCelebration()
            return
        }

        let advanceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            tutorialNoteIndex += 1
            nextNote()
        }

        pendingAdvanceTask = advanceTask
    }

    func startTutorialCompletionCelebration() {
        AppLog.tutorial.info("Tutorial completion celebration started")
        isShowingTutorialCompletion = true
        cancelTutorialCompletionCelebration()

        playRandomCelebrationMelody(reasonText: tutorialCelebrationReasonText)
    }

    var tutorialCelebrationReasonText: String {
        NoteTutorial.celebrationReasonText(kind: activeTutorialKind)
    }

    func finishCurrentTutorial() {
        guard let tutorialID = activeTutorialProgressID, let activeTutorialKind else { return }

        AppLog.tutorial.info("Tutorial finished; kind \(String(describing: activeTutorialKind), privacy: .public)")
        markTutorialCompleted(tutorialID)

        cancelTutorialCompletionCelebration()
        celebrationReasonText = nil
        resetNoteQueue()
        nextNote()
    }

    func markTutorialCompleted(_ tutorialID: TutorialProgressID) {
        switch tutorialID {
        case .firstOctave:
            hasCompletedFirstOctaveTutorial = true
        case .middleC:
            hasCompletedMiddleCTutorial = true
        case .referenceNotes:
            hasCompletedReferenceNoteTutorial = true
        case .accidentals:
            hasCompletedAccidentalTutorial = true
        }

        synchronizeTutorialProgress()
    }

    func acknowledgeCelebration() {
        guard let celebrationReasonText else { return }

        AppLog.tutorial.info("Celebration acknowledged")
        if isShowingTutorialCompletion {
            finishCurrentTutorial()
        } else if celebrationReasonText.hasPrefix(NoteTutorial.welcomeCelebrationText) {
            acknowledgedStaffTutorialPromptIDs.insert(staffTutorialPromptID(for: NoteTutorial.welcomeTutorialText))
            self.celebrationReasonText = nil
            cancelMelodyKeyboardPlayback()
            tutorialCelebrationHighlightedAnswers = []
            playNewPromptIfPracticeTabIsVisible()
        } else {
            self.celebrationReasonText = nil
            cancelMelodyKeyboardPlayback()
        }
    }

    func acknowledgeStaffTutorialPrompt() {
        guard let staffTutorialHelperText else { return }

        AppLog.tutorial.info("Staff tutorial prompt acknowledged")
        if activeGuidedTutorialID != nil,
           staffTutorialHelperText == guidedTutorialPromptText {
            acknowledgeGuidedTutorialPrompt()
            return
        }

        acknowledgeTutorialPrompt(
            staffTutorialHelperText,
            kind: activeTutorialKind
        )

        if staffTutorialHelperText == NoteTutorial.welcomeTutorialText {
            cancelMelodyKeyboardPlayback()
            tutorialCelebrationHighlightedAnswers = []
        }

        if self.staffTutorialHelperText == nil {
            playNewPromptIfPracticeTabIsVisible()
        }
    }

    func acknowledgeTutorialPrompt(_ text: String, kind: TutorialKind?) {
        AppLog.tutorial.info("Tutorial prompt acknowledged; kind \(String(describing: kind), privacy: .public)")
        if text == NoteTutorial.burstMeterHelperText {
            hasAcknowledgedBurstMeterHelper = true
        } else if isFirstOctaveNextStepsHelperText(text) {
            isCompletedOctaveNextStepsReminderPresented = false
        } else {
            acknowledgedStaffTutorialPromptIDs.insert(staffTutorialPromptID(for: text, kind: kind))
        }
    }

    func isFirstOctaveNextStepsHelperText(_ text: String) -> Bool {
        text == NoteTutorial.firstOctaveNextStepsHelperText
            || text.hasSuffix(NoteTutorial.firstOctaveNextStepsHelperText)
            || text == completedOctaveNextStepsHelperText
    }

    func acknowledgeOctaveIntroduction() {
        guard let activeOctaveIntroduction else { return }

        AppLog.tutorial.info(
            "Octave introduction acknowledged; clef \(activeOctaveIntroduction.clef.rawValue, privacy: .public), octave \(activeOctaveIntroduction.octave, privacy: .public)"
        )
        dismissedOctaveIntroductionID = activeOctaveIntroduction.id
        resetPromptResponseTimer()

        if self.activeOctaveIntroduction == nil {
            playNewPromptIfPracticeTabIsVisible()
        }
    }

    func acknowledgeKeyboardTutorialPrompt() {
        if activeOctaveIntroduction != nil {
            acknowledgeOctaveIntroduction()
            return
        }

        guard let keyboardTutorialHelperText else { return }

        AppLog.tutorial.info("Keyboard tutorial prompt acknowledged")
        if activeGuidedTutorialID != nil {
            acknowledgeGuidedTutorialPrompt()
            return
        }

        acknowledgedStaffTutorialPromptIDs.insert(staffTutorialPromptID(for: keyboardTutorialHelperText))

        if self.keyboardTutorialHelperText == nil {
            playNewPromptIfPracticeTabIsVisible()
        }
    }

    func acknowledgeGuidedTutorialPrompt() {
        guard let activeGuidedTutorialID, let guidedTutorialPromptID else { return }

        AppLog.tutorial.info("Guided Tutorial prompt acknowledged; kind \(String(describing: activeGuidedTutorialID), privacy: .public)")
        acknowledgedStaffTutorialPromptIDs.insert(guidedTutorialPromptID)
        advanceGuidedTutorial()
    }

    func finishGuidedTutorial() {
        guard let activeGuidedTutorialID else { return }

        AppLog.tutorial.info("Guided Tutorial finished; kind \(String(describing: activeGuidedTutorialID), privacy: .public)")
        markTutorialCompleted(activeGuidedTutorialID)
        resetPromptResponseTimer()
        nextNote()
    }

    func cancelTutorialCompletionCelebration() {
        pendingTutorialCelebrationTasks.forEach { $0.cancel() }
        pendingTutorialCelebrationTasks.removeAll()
        cancelMelodyKeyboardPlayback()
        tutorialCelebrationHighlightedAnswers = []
    }

    func midiNoteMatchesCurrentSequence(_ noteNumber: UInt8) -> Bool {
        guard
            let expectedNote = expectedSequenceNote,
            let expectedNoteNumber = NotePitch.midiNoteNumber(for: expectedNote)
        else {
            return false
        }

        return noteNumber == expectedNoteNumber
    }

    var expectedSequenceNote: QuizNote? {
        if let guidedTutorialNote {
            return guidedTutorialNote
        }

        guard promptSequence.indices.contains(currentGuessIndex) else {
            return promptSequence.last ?? currentNote
        }

        return promptSequence[currentGuessIndex]
    }

    var lastPlayedPromptNote: QuizNote? {
        promptSequence.last
    }

    func resetNoteQueue() {
        currentGuessIndex = 0
        hasFailedCurrentSequence = false
    }

    func middleCReferenceNote(clef: Clef) -> QuizNote {
        referenceNote(letter: "C", octave: 4, clef: clef)
    }

    func referenceNote(letter: String, octave: Int, clef: Clef) -> QuizNote {
        QuizNote(
            letter: letter,
            octave: octave,
            clef: clef,
            staffStep: NotePitch.staffStep(letter: letter, octave: octave, clef: clef),
            accidental: .natural
        )
    }

    func tutorialNote(letter: String, accidental: Accidental) -> QuizNote {
        let clef = selectedClef.allowedClefs.first ?? .treble
        let octave = selectedOctaves.first ?? 4

        return QuizNote(
            letter: letter,
            octave: octave,
            clef: clef,
            staffStep: NotePitch.staffStep(letter: letter, octave: octave, clef: clef),
            accidental: accidental
        )
    }

    func resetScore() {
        let firstRecommendedBucket = ScoreBucket.firstRecommended

        AppLog.learning.info("Resetting all Progress")
        adaptiveStats.removeAll()
        AdaptiveLearningStore.persist(adaptiveStats)
        selectPracticeBucket(firstRecommendedBucket)
        resetNoteQueue()
        nextNote()
        warmLikelyOctaveAudioCaches()
    }

    func debugToggleLearnedNote(_ key: AdaptiveNoteKey) {
        #if DEBUG
        if adaptiveStats[key]?.learnedPercent == 100 {
            adaptiveStats.removeValue(forKey: key)
        } else {
            adaptiveStats[key] = AdaptiveNoteStats(quickCorrectAnswers: 3)
        }

        AdaptiveLearningStore.persist(adaptiveStats)
        warmLikelyOctaveAudioCaches()
        #endif
    }

    func resetTutorials() {
        AppLog.tutorial.info("Resetting tutorials")
        hasCompletedFirstOctaveTutorial = false
        hasCompletedAccidentalTutorial = false
        hasAcknowledgedBurstMeterHelper = false
        cancelTutorialCompletionCelebration()
        celebrationReasonText = nil
        dismissedOctaveIntroductionID = nil
        hasCompletedMiddleCTutorial = false
        hasCompletedReferenceNoteTutorial = false
        practiceSession.tutorials.activeTutorialID = nil
        practiceSession.tutorials.reset()
        synchronizeTutorialProgress()
        milestoneBurstProgress = 0
        lastMilestoneBurstDrainDate = Date()
        resetNoteQueue()
        nextNote()
    }

    func recordGuess(
        for note: QuizNote,
        responseTime: TimeInterval,
        canCountLearnedProgress: Bool
    ) {
        guard canCountLearnedProgress else { return }

        let result = AdaptiveLearningStore.recordGuess(
            for: note,
            responseTime: responseTime,
            quickThreshold: activeQuickAnswerThreshold,
            answerOptions: answerOptions,
            stats: &adaptiveStats
        )
        warmLikelyOctaveAudioCaches()
        guard let result, result.didCompleteOctave else { return }

        AppLog.learning.info(
            "Learned octave celebration queued; clef \(result.completedOctaveClef.rawValue, privacy: .public), octave \(result.completedOctave, privacy: .public)"
        )
        playRandomCelebrationMelody(
            reasonText: learnedOctaveCelebrationText(for: result)
        )
    }

    func learnedOctaveCelebrationText(for result: AdaptiveGuessRecordResult) -> String {
        let baseText = "\(result.completedOctaveClef.rawValue) Clef, Octave \(result.completedOctave)"
        guard includeSharps && includeFlats else { return "\(baseText) learned!" }

        return "\(baseText) with Sharps and Flats learned!"
    }

    func monitorCompletedOctaveNextStepsReminder(for note: QuizNote?) {
        guard !isTutorialActive, let note else { return }
        guard selectedOctaves.count == 1, selectedOctaves.contains(note.octave) else {
            resetCompletedOctaveNextStepsMonitor()
            return
        }
        guard progressedOctaves == [note.octave] else {
            resetCompletedOctaveNextStepsMonitor()
            return
        }
        guard isOctaveLearned(clef: note.clef, octave: note.octave) else {
            resetCompletedOctaveNextStepsMonitor()
            return
        }

        recordCompletedOctaveNextStepsAnswer(for: note)
    }

    func recordCompletedOctaveNextStepsAnswer(for note: QuizNote) {
        let bucketID = OctaveIntroduction(clef: note.clef, octave: note.octave).id
        if completedOctaveNextStepsBucketID != bucketID {
            completedOctaveNextStepsBucketID = bucketID
            completedOctaveNextStepsAnswerCount = 0
        }

        completedOctaveNextStepsAnswerCount += 1

        guard completedOctaveNextStepsAnswerCount >= completedOctaveNextStepsReminderInterval else { return }

        AppLog.learning.info("Completed-octave next steps reminder presented")
        completedOctaveNextStepsAnswerCount = 0
        isCompletedOctaveNextStepsReminderPresented = true
    }

    func isOctaveLearned(clef: Clef, octave: Int) -> Bool {
        AdaptiveLearningStore.learnedPercent(
            clef: clef,
            octave: octave,
            answerOptions: answerOptions,
            stats: adaptiveStats
        ) == 100
    }

    var progressedOctaves: Set<Int> {
        Set(adaptiveStats.keys.map(\.octave))
    }

    func resetCompletedOctaveNextStepsMonitor() {
        completedOctaveNextStepsAnswerCount = 0
        completedOctaveNextStepsBucketID = nil
        isCompletedOctaveNextStepsReminderPresented = false
    }

    func updateMilestoneBurstProgress(isCorrect: Bool) {
        guard isTempoMeterEnabled else { return }

        lastMilestoneBurstDrainDate = Date()

        withAnimation(.easeOutCubic(duration: 0.2)) {
            if isCorrect {
                milestoneBurstProgress = min(milestoneBurstProgress + 0.06, 1)
            } else {
                milestoneBurstProgress = max(milestoneBurstProgress - 0.22, 0)
            }
        }
    }

    func drainMilestoneBurstProgress(at date: Date) {
        guard isTempoMeterEnabled else { return }

        let elapsed = max(date.timeIntervalSince(lastMilestoneBurstDrainDate), 0)
        lastMilestoneBurstDrainDate = date
        guard elapsed > 0, milestoneBurstProgress > 0 else { return }

        let drainRate = 0.025
        let nextProgress = max(milestoneBurstProgress - elapsed * drainRate, 0)

        withAnimation(.easeOutCubic(duration: 0.25)) {
            milestoneBurstProgress = nextProgress
        }
    }

    func persistSelectedOctaves() {
        selectedOctavesStorage = selectedOctaves
            .sorted()
            .map(String.init)
            .joined(separator: ",")
    }

    func isOctaveWithoutProgress(_ introduction: OctaveIntroduction) -> Bool {
        AdaptiveLearningStore.learnedPercent(
            clef: introduction.clef,
            octave: introduction.octave,
            answerOptions: answerOptions,
            stats: adaptiveStats
        ) == 0
    }

    func updateOctaveIntroductionDismissal(for note: QuizNote) {
        let introductionID = OctaveIntroduction(clef: note.clef, octave: note.octave).id
        guard dismissedOctaveIntroductionID != nil, dismissedOctaveIntroductionID != introductionID else { return }

        dismissedOctaveIntroductionID = nil
    }

    func normalizeClefSelectionForSequenceLength() {
        let normalized = normalizedClefMode(for: selectedClef)
        guard normalized != selectedClef else { return }
        selectedClef = normalized
        selectedClefStorage = normalized.rawValue
    }

    func normalizedClefMode(for clefMode: ClefMode) -> ClefMode {
        NoteQuizGenerator.normalizedClefMode(for: clefMode, sequenceLength: sequenceLength)
    }

}
