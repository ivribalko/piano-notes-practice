import Combine
import Foundation
import SwiftUI

extension AppRootView {
    @ViewBuilder
    var debugControls: some View {
        #if DEBUG
        HStack(spacing: 8) {
            debugIconButton(
                systemImage: isToneEnabled || isKeyboardEffectEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                accessibilityLabel: isToneEnabled || isKeyboardEffectEnabled ? "Debug disable all sounds" : "Debug enable all sounds",
                action: debugToggleAllSounds
            )

            debugIconButton(
                systemImage: "checkmark.seal.fill",
                accessibilityLabel: "Debug win current note",
                action: debugWinCurrentNote
            )

            debugIconButton(
                systemImage: debugSkipsTutorialsAndCelebrations ? "forward.end.fill" : "forward.end",
                accessibilityLabel: "Debug skip all tutorials and celebrations",
                accessibilityValue: debugSkipsTutorialsAndCelebrations ? "On" : "Off",
                action: debugToggleSkipTutorialsAndCelebrations
            )

            debugIconButton(
                systemImage: "trash.fill",
                accessibilityLabel: "Debug purge audio cache",
                action: debugPurgeAudioCache
            )

            debugTextButton(
                title: "\(debugMelodyDisplayNumber)",
                accessibilityLabel: "Debug play melody",
                action: debugPlayMelody
            )
        }
        #endif
    }

    func debugIconButton(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.practicePanelPrimaryTextColor)
                .frame(width: Theme.debugControlVisualSize, height: Theme.debugControlVisualSize)
                .background {
                    Circle()
                        .fill(.clear)
                }
                .overlay {
                    Circle()
                        .stroke(Theme.practicePanelPrimaryTextColor.opacity(0.45), lineWidth: 1.25)
                }
                .frame(width: Theme.debugControlHitSize, height: Theme.debugControlHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
    }

    func debugTextButton(
        title: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.practicePanelPrimaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 10)
                .frame(minWidth: Theme.debugControlHitSize)
                .frame(height: Theme.debugControlVisualSize)
                .background {
                    Capsule()
                        .fill(.clear)
                }
                .overlay {
                    Capsule()
                        .stroke(Theme.practicePanelPrimaryTextColor.opacity(0.45), lineWidth: 1.25)
                }
                .frame(height: Theme.debugControlHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    var isMIDIModeActive: Bool {
        midiInputManager.isDeviceConnected
    }

    var isGuidedTutorialActive: Bool {
        activeGuidedTutorialID != nil
    }

    var activeGuidedTutorialID: TutorialProgressID? {
        guard let activeTutorialProgressID, activeTutorialProgressID.isGuidedTutorial else { return nil }
        return activeTutorialProgressID
    }

    var guidedTutorialPromptID: String? {
        guard let activeGuidedTutorialID, let guidedTutorialPromptText else { return nil }
        return "\(activeGuidedTutorialID.promptIDPrefix)-\(guidedTutorialPromptText)"
    }

    var guidedTutorialPromptText: String? {
        switch activeGuidedTutorialID {
        case .middleC:
            switch MiddleCTutorialStep(rawValue: tutorialNoteIndex) ?? .ledgerLine {
            case .ledgerLine:
                return NoteTutorial.ledgerLineDefinitionText
            case .bassC4:
                return NoteTutorial.middleCBassC4Text
            case .trebleC4:
                return NoteTutorial.middleCTrebleC4Text
            case .connection:
                return NoteTutorial.middleCConnectionText
            case .handRange:
                return NoteTutorial.middleCHandRangeText
            }
        case .referenceNotes:
            switch ReferenceNoteTutorialStep(rawValue: tutorialNoteIndex) ?? .trebleG {
            case .trebleG:
                return NoteTutorial.referenceNoteTrebleGText
            case .bassF:
                return NoteTutorial.referenceNoteBassFText
            case .referencePoints:
                return NoteTutorial.referenceNoteReferencePointsText
            case .positionReading:
                return NoteTutorial.referenceNotePositionReadingText
            }
        case .firstOctave, .accidentals, nil:
            return nil
        }
    }

    var isGuidedTutorialKeyboardStep: Bool {
        switch activeGuidedTutorialID {
        case .middleC:
            return tutorialNoteIndex <= MiddleCTutorialStep.trebleC4.rawValue
        case .referenceNotes:
            return tutorialNoteIndex <= ReferenceNoteTutorialStep.bassF.rawValue
        case .firstOctave, .accidentals, nil:
            return false
        }
    }

    var guidedTutorialNote: QuizNote? {
        guard isGuidedTutorialKeyboardStep else { return nil }

        switch activeGuidedTutorialID {
        case .middleC:
            let step = MiddleCTutorialStep(rawValue: tutorialNoteIndex) ?? .ledgerLine
            let clef: Clef = step == .trebleC4 ? .treble : .bass
            return middleCReferenceNote(clef: clef)
        case .referenceNotes:
            return tutorialNoteIndex == 0
                ? referenceNote(letter: "G", octave: 4, clef: .treble)
                : referenceNote(letter: "F", octave: 3, clef: .bass)
        case .firstOctave, .accidentals, nil:
            return nil
        }
    }

    var displayedCurrentNote: QuizNote {
        guidedTutorialNote ?? currentNote
    }

    var displayedPromptSequence: [QuizNote] {
        if let guidedTutorialNote {
            return [guidedTutorialNote]
        }

        return promptSequence
    }

    var displayedCurrentGuessIndex: Int {
        guidedTutorialNote == nil ? currentGuessIndex : 0
    }

    var activePracticeOctaves: Set<Int> {
        selectedOctaves
    }

    var activeOctaveIntroduction: OctaveIntroduction? {
        guard !isTutorialActive else { return nil }
        guard !isGuidedTutorialActive else { return nil }
        guard celebrationReasonText == nil else { return nil }
        guard !isShowingTutorialCompletion else { return nil }
        guard !shouldShowWelcomeCelebration else { return nil }

        let introduction = OctaveIntroduction(
            clef: currentNote.clef,
            octave: currentNote.octave
        )

        guard isOctaveWithoutProgress(introduction) else { return nil }

        return dismissedOctaveIntroductionID == introduction.id ? nil : introduction
    }

    var octaveIntroductionNotes: [QuizNote] {
        guard let activeOctaveIntroduction else { return [] }

        return NotePitch.naturalLetters.map { letter in
            QuizNote(
                letter: letter,
                octave: activeOctaveIntroduction.octave,
                clef: activeOctaveIntroduction.clef,
                staffStep: NotePitch.staffStep(
                    letter: letter,
                    octave: activeOctaveIntroduction.octave,
                    clef: activeOctaveIntroduction.clef
                ),
                accidental: .natural
            )
        }
    }

    var staffOverviewNotes: [QuizNote] {
        if !octaveIntroductionNotes.isEmpty {
            return octaveIntroductionNotes
        }

        if keyboardTutorialHelperText == NoteTutorial.staffPositionTutorialText {
            return Array(tutorialNotes.prefix(2))
        }

        guard keyboardTutorialHelperText == NoteTutorial.octaveWhiteKeysTutorialText else { return [] }

        return tutorialNotes
    }

    var quizGenerator: NoteQuizGenerator {
        NoteQuizGenerator(
            selectedClef: selectedClef,
            activeOctaves: activePracticeOctaves,
            answerOptions: answerOptions,
            adaptiveStats: adaptiveStats
        )
    }

    var isOnScreenKeyboardVisible: Bool {
        !(isMIDIModeActive && !isTutorialActive && !isGuidedTutorialActive)
    }

    var nextDebugMelodyNumber: Int {
        let melodyCount = max(noteSoundPlayer.celebrationMelodyCount, 1)
        return (lastCelebrationMelodyNumber % melodyCount) + 1
    }

    var debugMelodyDisplayNumber: Int {
        noteSoundPlayer.celebrationMelodyNumber ?? keyboardCelebrationMelodyNumber ?? nextDebugMelodyNumber
    }

    var isTutorialActive: Bool {
        activeTutorialKind != nil
    }

    /// Reports whether any note-sequence or guided Tutorial is running.
    var isTutorialFlowActive: Bool {
        activeTutorialProgressID != nil
    }

    /// Keeps a running Tutorial active, or selects the next eligible Tutorial when none is running.
    var tutorialProgressID: TutorialProgressID? {
        if let runningTutorialID = practiceSession.tutorials.activeTutorialID,
           !hasCompletedTutorial(runningTutorialID) {
            return runningTutorialID
        }

        return TutorialProgressID.allCases.first { tutorialID in
            isTutorialEnabled(tutorialID)
                && !hasCompletedTutorial(tutorialID)
                && isPracticingTutorial(tutorialID)
        }
    }

    var activeTutorialProgressID: TutorialProgressID? {
        debugSkipsTutorialsAndCelebrations ? nil : tutorialProgressID
    }

    func isTutorialEnabled(_ tutorialID: TutorialProgressID) -> Bool {
        tutorialID != .accidentals || includeSharps && includeFlats
    }

    func isPracticingTutorial(_ tutorialID: TutorialProgressID) -> Bool {
        if tutorialID == .accidentals {
            return selectedClef.allowedClefs.count == 1 && selectedOctaves.count == 1
        }

        guard let requiredPractice = tutorialID.requiredPractice else { return true }
        return isPracticingOnly(clef: requiredPractice.clef, octave: requiredPractice.octave)
    }

    func hasCompletedTutorial(_ tutorialID: TutorialProgressID) -> Bool {
        switch tutorialID {
        case .firstOctave:
            return hasCompletedFirstOctaveTutorial
        case .middleC:
            return hasCompletedMiddleCTutorial
        case .referenceNotes:
            return hasCompletedReferenceNoteTutorial
        case .accidentals:
            return hasCompletedAccidentalTutorial
        }
    }

    var completedTutorialIDs: Set<TutorialProgressID> {
        Set(TutorialProgressID.allCases.filter(hasCompletedTutorial))
    }

    var pendingTutorialKind: TutorialKind? {
        tutorialProgressID?.noteTutorialKind
    }

    var activeTutorialKind: TutorialKind? {
        activeTutorialProgressID?.noteTutorialKind
    }

    var currentTutorialNote: QuizNote? {
        NoteTutorial.currentNote(from: tutorialNotes, index: tutorialNoteIndex)
    }

    var tutorialNotes: [QuizNote] {
        NoteTutorial.notes(
            kind: activeTutorialKind,
            letters: NotePitch.naturalLetters,
            sharpLetters: NotePitch.sharpLetters,
            flatLetters: NotePitch.flatLetters,
            makeNote: tutorialNote
        )
    }

    var highlightedAnswers: Set<NoteAnswer> {
        NoteTutorial.highlightedAnswers(
            celebrationHighlightedAnswers: tutorialCelebrationHighlightedAnswers,
            isActive: isTutorialActive && celebrationReasonText == nil,
            expectedNote: expectedSequenceNote,
            answerOptions: answerOptions
        )
    }

    var keyboardHighlightedAnswers: Set<NoteAnswer> {
        guard activeOctaveIntroduction == nil else { return [] }

        if !tutorialCelebrationHighlightedAnswers.isEmpty {
            return tutorialCelebrationHighlightedAnswers
        }

        if let guidedTutorialNote, staffTutorialHelperText == nil, keyboardTutorialHelperText == nil {
            return [NotePitch.displayKeyboardAnswer(for: guidedTutorialNote, answerOptions: answerOptions)]
        }

        let helperHighlights = isHelperGlowEnabled ? delayedKeyboardHighlightedAnswers : []
        return NoteTutorial.keyboardHighlightedAnswers(
            staffHelperText: staffTutorialHelperText,
            answerOptions: answerOptions,
            fallbackHighlights: highlightedAnswers.union(helperHighlights)
        )
    }

    var keyboardHelperText: String? {
        pendingKeyboardHelperText(kind: activeTutorialKind)
    }

    func pendingKeyboardHelperText(kind: TutorialKind?) -> String? {
        NoteTutorial.keyboardHelperText(
            kind: kind,
            noteIndex: tutorialNoteIndex,
            isShowingCompletion: isShowingTutorialCompletion,
            sharpLetterCount: NotePitch.sharpLetters.count,
            acknowledgedPromptIDs: acknowledgedStaffTutorialPromptIDs
        )
    }

    var staffTutorialHelperText: String? {
        guard !debugSkipsTutorialsAndCelebrations else { return nil }
        if activeGuidedTutorialID != nil,
           !isGuidedTutorialKeyboardStep,
           let guidedTutorialPromptID,
           let guidedTutorialPromptText,
           !acknowledgedStaffTutorialPromptIDs.contains(guidedTutorialPromptID) {
            return guidedTutorialPromptText
        }

        return pendingStaffTutorialHelperText(kind: activeTutorialKind)
    }

    func pendingStaffTutorialHelperText(kind: TutorialKind?) -> String? {
        NoteTutorial.staffHelperText(
            kind: kind,
            keyboardHelperText: pendingKeyboardHelperText(kind: kind),
            acknowledgedPromptIDs: acknowledgedStaffTutorialPromptIDs,
            showsFirstOctaveNextSteps: shouldShowFirstOctaveNextStepsHelper,
            firstOctaveNextStepsText: completedOctaveNextStepsHelperText,
            showsBurstMeter: shouldShowBurstMeterHelper
        )
    }

    var keyboardTutorialHelperText: String? {
        guard !debugSkipsTutorialsAndCelebrations else { return nil }
        guard celebrationReasonText == nil else { return nil }
        if isGuidedTutorialKeyboardStep,
           let guidedTutorialPromptID,
           let guidedTutorialPromptText,
           !acknowledgedStaffTutorialPromptIDs.contains(guidedTutorialPromptID) {
            return guidedTutorialPromptText
        }

        if let postWelcomeKeyboardIntroText {
            return postWelcomeKeyboardIntroText
        }

        guard staffTutorialHelperText == nil, let keyboardHelperText else { return nil }
        let promptID = staffTutorialPromptID(for: keyboardHelperText)
        guard !acknowledgedStaffTutorialPromptIDs.contains(promptID) else { return nil }

        return keyboardHelperText
    }

    var postWelcomeKeyboardIntroText: String? {
        guard staffTutorialHelperText == nil else { return nil }
        guard NoteTutorial.shouldShowSheetMusicStaffIntro(
            kind: activeTutorialKind,
            acknowledgedPromptIDs: acknowledgedStaffTutorialPromptIDs
        ) else { return nil }

        return NoteTutorial.sheetMusicStaffIntroText
    }

    var isWelcomeTutorialPrompt: Bool {
        staffTutorialHelperText == NoteTutorial.welcomeTutorialText
    }

    var shouldShowWelcomeCelebration: Bool {
        guard !debugSkipsTutorialsAndCelebrations else { return false }

        return pendingShouldShowWelcomeCelebration(kind: activeTutorialKind)
    }

    func pendingShouldShowWelcomeCelebration(kind: TutorialKind?) -> Bool {
        guard kind == .firstOctave else { return false }
        let promptID = staffTutorialPromptID(for: NoteTutorial.welcomeTutorialText, kind: kind)

        return !acknowledgedStaffTutorialPromptIDs.contains(promptID)
    }

    func staffTutorialPromptID(for text: String) -> String {
        staffTutorialPromptID(for: text, kind: activeTutorialKind)
    }

    func staffTutorialPromptID(for text: String, kind: TutorialKind?) -> String {
        NoteTutorial.promptID(kind: kind, text: text)
    }

    var shouldShowBurstMeterHelper: Bool {
        !hasAcknowledgedBurstMeterHelper && isTempoMeterEnabled && !isTutorialFlowActive
    }

    var isMilestoneBurstHighlighted: Bool {
        staffTutorialHelperText == NoteTutorial.burstMeterHelperText
    }

    var shouldShowFirstOctaveNextStepsHelper: Bool {
        guard !isTutorialFlowActive else { return false }

        return isCompletedOctaveNextStepsReminderPresented
    }

    var completedOctaveNextStepsHelperText: String? {
        guard
            isCompletedOctaveNextStepsReminderPresented,
            let completedOctaveNextStepsBucketID,
            let learnedBucketText = learnedBucketText(for: completedOctaveNextStepsBucketID)
        else {
            return nil
        }

        return "\(learnedBucketText) is learned. \(completedOctaveNextStepsActionText)."
    }

    func learnedBucketText(for bucketID: String) -> String? {
        let parts = bucketID.split(separator: "-")
        guard parts.count == 2, let octave = parts.last else { return nil }

        let baseText = "\(parts[0]) Clef, Octave \(octave)"
        guard includeSharps && includeFlats else { return baseText }

        return "\(baseText) with Sharps and Flats"
    }

    var completedOctaveNextStepsActionText: String {
        "Go to Progress to choose another Octave"
    }

    var answerOptions: [NoteAnswer] {
        NoteQuizGenerator.answerOptions(
            includeSharps: includeSharps,
            includeFlats: includeFlats
        )
    }

    var learnedStatRows: [LearnedNoteStatRow] {
        AdaptiveLearningStore.learnedRows(from: adaptiveStats)
    }

    var progressVisibleBuckets: [ScoreBucket] {
        let learnedBuckets = Set(learnedStatRows.map { ScoreBucket(clef: $0.key.clef, octave: $0.key.octave) })
        var buckets = Array(learnedBuckets)

        let hasIncompleteBucket = buckets.contains { bucket in
            AdaptiveLearningStore.learnedPercent(
                clef: bucket.clef,
                octave: bucket.octave,
                answerOptions: answerOptions,
                stats: adaptiveStats
            ) < 100
        }

        if !hasIncompleteBucket, let nextBucket = nextUnstartedProgressBucket(after: buckets) {
            buckets.append(nextBucket)
        }

        return buckets
    }

    func nextUnstartedProgressBucket(after displayedBuckets: [ScoreBucket]) -> ScoreBucket? {
        let displayedBucketSet = Set(displayedBuckets)
        return ScoreBucket.suggestedSequence.first {
            availableOctaves.contains($0.octave) && !displayedBucketSet.contains($0)
        }
    }

    func warmLikelyOctaveAudioCaches() {
        let progressOctaves = progressVisibleBuckets.map(\.octave)
        let octavesToWarm = Set(selectedOctaves).union(progressOctaves)

        for octave in octavesToWarm {
            noteSoundPlayer.warmAudioCache(forOctave: octave)
        }
    }

    func guess(_ answer: NoteAnswer) {
        guard activeOctaveIntroduction == nil else { return }
        guard staffTutorialHelperText == nil else { return }
        guard keyboardTutorialHelperText == nil else { return }

        submitGuess(isCorrect: answerMatchesCurrentSequence(answer))
    }

    func handleMIDINoteNumber(_ noteNumber: UInt8) {
        guard isMIDIModeActive else { return }
        guard activeOctaveIntroduction == nil else { return }
        guard !isGuidedTutorialActive else { return }
        AppLog.input.info("MIDI note submitted as Practice answer")
        submitGuess(isCorrect: midiNoteMatchesCurrentSequence(noteNumber))
    }

    func handleSelectedTabChange(from oldValue: AppTab, to newValue: AppTab) {
        let date = Date()
        AppLog.app.info("Selected tab changed from \(String(describing: oldValue), privacy: .public) to \(String(describing: newValue), privacy: .public)")

        if oldValue == .home {
            pausePromptResponseTimer(at: date)
        }

        if newValue == .home {
            resumePromptResponseTimer(at: date)
            playWelcomeCelebrationMusicIfNeeded()
        }
    }

    func openClefSettingsFromProgress() {
        settingsNavigationPath = [.practiceCue]
        selectedTab = .settings
    }

    func debugWinCurrentNote() {
        guard let expectedSequenceNote else { return }
        simulateKeyboardPress(
            answer: NotePitch.displayKeyboardAnswer(for: expectedSequenceNote, answerOptions: answerOptions),
            submitsGuess: true
        )
    }


}
