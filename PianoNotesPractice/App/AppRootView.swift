import Combine
import Observation
import Foundation
import QuartzCore
import SwiftUI
import UIKit

/// Defers creation of the long-lived Practice dependencies until the app root first appears.
struct AppRootContainerView: View {
    @State private var dependencies: AppRootDependencies?

    var body: some View {
        Color.clear
            .overlay {
                if let dependencies {
                    AppRootView(
                        practiceSession: dependencies.practiceSession,
                        adaptiveStats: dependencies.adaptiveStats
                    )
                }
            }
            .task {
                guard dependencies == nil else { return }
                dependencies = AppRootDependencies()
            }
    }
}

/// Creates and configures the long-lived services and initial learning state for the app root.
@MainActor
private struct AppRootDependencies {
    let practiceSession: PracticeSession
    let adaptiveStats: [AdaptiveNoteKey: AdaptiveNoteStats]

    init(defaults: UserDefaults = .standard) {
        let session = PracticeSession()
        session.settings.selectedClef = ClefMode(rawValue: defaults.string(forKey: "selectedClef") ?? "") ?? .treble
        session.settings.includeSharps = defaults.bool(forKey: "includeSharps")
        session.settings.includeFlats = defaults.bool(forKey: "includeFlats")
        session.settings.isStaffVisible = defaults.object(forKey: "isStaffVisible") as? Bool ?? true
        session.settings.isToneEnabled = defaults.object(forKey: "isToneEnabled") as? Bool ?? false
        session.settings.isKeyboardEffectEnabled = defaults.object(forKey: "isKeyboardEffectEnabled") as? Bool ?? true
        session.settings.isNoteBounceEffectEnabled = defaults.object(forKey: "isNoteBounceEffectEnabled") as? Bool ?? !UIAccessibility.isReduceMotionEnabled
        session.settings.isHelperGlowEnabled = defaults.object(forKey: "isHelperGlowEnabled") as? Bool ?? true
        session.settings.isTempoMeterEnabled = defaults.object(forKey: "isTempoMeterEnabled") as? Bool ?? false
        session.settings.usesNativeDarkPracticeColors = defaults.bool(forKey: "usesNativeDarkPracticeColors")
        session.settings.sequenceLength = NoteQuizGenerator.sequenceLength(from: defaults.object(forKey: "sequenceLength") as? Int ?? 1)
        session.settings.selectedOctaves = NoteQuizGenerator.selectedOctaves(from: defaults.string(forKey: "selectedOctaves") ?? "4")

        practiceSession = session
        adaptiveStats = AdaptiveLearningStore.loadStats()
        AppLog.practice.info("Practice root initialized")
    }
}

/// Hosts the tab-based app shell and owns the practice state.
struct AppRootView: View {
    @AppStorage("selectedClef") var selectedClefStorage = ClefMode.treble.rawValue
    @AppStorage("includeSharps") var includeSharpsStorage = false
    @AppStorage("includeFlats") var includeFlatsStorage = false
    @AppStorage("isStaffVisible") var isStaffVisibleStorage = true
    @AppStorage("isToneEnabled") var isToneEnabledStorage = false
    @AppStorage("isKeyboardEffectEnabled") var isKeyboardEffectEnabledStorage = true
    @AppStorage("isNoteBounceEffectEnabled") var isNoteBounceEffectEnabledStorage = true
    @AppStorage("isHelperGlowEnabled") var isHelperGlowEnabledStorage = true
    @AppStorage("isTempoMeterEnabled") var isTempoMeterEnabledStorage = false
    @AppStorage("usesNativeDarkPracticeColors") var usesNativeDarkPracticeColorsStorage = false
    @AppStorage("sequenceLength") var sequenceLengthStorage = 1
    @AppStorage("selectedOctaves") var selectedOctavesStorage = "4"
    @AppStorage("hasCompletedFirstOctaveTutorial") var hasCompletedFirstOctaveTutorial = false
    @AppStorage("hasCompletedAccidentalTutorial") var hasCompletedAccidentalTutorial = false
    @AppStorage("hasAcknowledgedBurstMeterHelper") var hasAcknowledgedBurstMeterHelper = false
    @AppStorage("hasCompletedMiddleCTutorial") var hasCompletedMiddleCTutorial = false
    @AppStorage("hasCompletedReferenceNoteTutorial") var hasCompletedReferenceNoteTutorial = false

    let availableOctaves = [2, 3, 4, 5, 6]
    let quickAnswerThreshold: TimeInterval = 1.25
    let completedOctaveNextStepsReminderInterval = 10
    var activeQuickAnswerThreshold: TimeInterval {
        includeSharps && includeFlats ? quickAnswerThreshold * 1.5 : quickAnswerThreshold
    }

    @State var currentNote = QuizNote(
        letter: "C",
        octave: 4,
        clef: .treble,
        staffStep: 10,
        accidental: .natural
    )
    var selectedClef: ClefMode {
        get { practiceSession.settings.selectedClef }
        nonmutating set { practiceSession.settings.selectedClef = newValue }
    }
    var includeSharps: Bool {
        get { practiceSession.settings.includeSharps }
        nonmutating set { practiceSession.settings.includeSharps = newValue }
    }
    var includeFlats: Bool {
        get { practiceSession.settings.includeFlats }
        nonmutating set { practiceSession.settings.includeFlats = newValue }
    }
    var isStaffVisible: Bool {
        get { practiceSession.settings.isStaffVisible }
        nonmutating set { practiceSession.settings.isStaffVisible = newValue }
    }
    var isToneEnabled: Bool {
        get { practiceSession.settings.isToneEnabled }
        nonmutating set { practiceSession.settings.isToneEnabled = newValue }
    }
    var isKeyboardEffectEnabled: Bool {
        get { practiceSession.settings.isKeyboardEffectEnabled }
        nonmutating set { practiceSession.settings.isKeyboardEffectEnabled = newValue }
    }
    var isNoteBounceEffectEnabled: Bool {
        get { practiceSession.settings.isNoteBounceEffectEnabled }
        nonmutating set { practiceSession.settings.isNoteBounceEffectEnabled = newValue }
    }
    var isHelperGlowEnabled: Bool {
        get { practiceSession.settings.isHelperGlowEnabled }
        nonmutating set { practiceSession.settings.isHelperGlowEnabled = newValue }
    }
    var isTempoMeterEnabled: Bool {
        get { practiceSession.settings.isTempoMeterEnabled }
        nonmutating set { practiceSession.settings.isTempoMeterEnabled = newValue }
    }
    var usesNativeDarkPracticeColors: Bool {
        get { practiceSession.settings.usesNativeDarkPracticeColors }
        nonmutating set { practiceSession.settings.usesNativeDarkPracticeColors = newValue }
    }
    var sequenceLength: Int {
        get { practiceSession.settings.sequenceLength }
        nonmutating set { practiceSession.settings.sequenceLength = newValue }
    }
    var selectedOctaves: Set<Int> {
        get { practiceSession.settings.selectedOctaves }
        nonmutating set { practiceSession.settings.selectedOctaves = newValue }
    }
    var promptSequence: [QuizNote] {
        get { practiceSession.quiz.promptSequence }
        nonmutating set { practiceSession.quiz.promptSequence = newValue }
    }
    var currentGuessIndex: Int {
        get { practiceSession.quiz.currentGuessIndex }
        nonmutating set { practiceSession.quiz.currentGuessIndex = newValue }
    }
    var hasFailedCurrentSequence: Bool {
        get { practiceSession.quiz.hasFailedCurrentSequence }
        nonmutating set { practiceSession.quiz.hasFailedCurrentSequence = newValue }
    }
    @State var adaptiveStats: [AdaptiveNoteKey: AdaptiveNoteStats]
    var promptResponseTimeStartedAt: Date? {
        get { practiceSession.quiz.promptResponseTimeStartedAt }
        nonmutating set { practiceSession.quiz.promptResponseTimeStartedAt = newValue }
    }
    var accumulatedPromptResponseTime: TimeInterval {
        get { practiceSession.quiz.accumulatedPromptResponseTime }
        nonmutating set { practiceSession.quiz.accumulatedPromptResponseTime = newValue }
    }
    @State var flashColor = Color.clear
    @State var noteScale = 1.0
    @State var hasLoadedInitialNote = false
    @State var noteAppearanceID = 0
    @State var noteDisappearanceID = 0
    @State var milestoneBurstProgress = 0.0
    @State var lastMilestoneBurstDrainDate = Date()
    @State var selectedTab = AppTab.home
    @State var settingsNavigationPath: [SettingsRoute] = []
    @State var pendingFlashResetTask: Task<Void, Never>?
    @State var pendingReplayTask: Task<Void, Never>?
    @State var pendingAdvanceTask: Task<Void, Never>?
    @State var pendingKeyboardHintTask: Task<Void, Never>?
    @State var isAdvancingToNextNote = false
    @State var isReplayFeedbackDelayComplete = false
    @State var isReplayWaitingForPlayback = false
    var tutorialNoteIndex: Int {
        get { practiceSession.tutorials.noteIndex }
        nonmutating set { practiceSession.tutorials.noteIndex = newValue }
    }
    var isShowingTutorialCompletion: Bool {
        get { practiceSession.tutorials.isShowingCompletion }
        nonmutating set { practiceSession.tutorials.isShowingCompletion = newValue }
    }
    var tutorialCelebrationHighlightedAnswers: Set<NoteAnswer> {
        get { practiceSession.celebrations.highlightedAnswers }
        nonmutating set { practiceSession.celebrations.highlightedAnswers = newValue }
    }
    @State var delayedKeyboardHighlightedAnswers: Set<NoteAnswer> = []
    var acknowledgedStaffTutorialPromptIDs: Set<String> {
        get { practiceSession.tutorials.acknowledgedStaffPromptIDs }
        nonmutating set { practiceSession.tutorials.acknowledgedStaffPromptIDs = newValue }
    }
    @State var completedOctaveNextStepsAnswerCount = 0
    @State var completedOctaveNextStepsBucketID: String?
    @State var isCompletedOctaveNextStepsReminderPresented = false
    @State var dismissedOctaveIntroductionID: String?
    var celebrationReasonText: String? {
        get { practiceSession.celebrations.reasonText }
        nonmutating set { practiceSession.celebrations.reasonText = newValue }
    }
    @State var simulatedKeyboardPress: SimulatedKeyboardPress?
    @State var simulatedKeyboardPressID = 0
    var keyboardCelebrationMelodyNumber: Int? {
        get { practiceSession.celebrations.keyboardMelodyNumber }
        nonmutating set { practiceSession.celebrations.keyboardMelodyNumber = newValue }
    }
    @State var lastCelebrationMelodyNumber = 0
    @State var pendingMelodyKeyboardTasks: [Task<Void, Never>] = []
    @State var pendingTutorialCelebrationTasks: [Task<Void, Never>] = []
    #if STORE_TUTORIAL_CAPTURE
    @State var hasStartedStoreTutorialCaptureAutomation = false
    @State var hasStartedStoreTutorialCaptureWelcome = false
    @State var pendingStoreTutorialCaptureTask: Task<Void, Never>?
    @State var storeTutorialCapturePromptID: String?
    #endif
    @State var debugSkipsTutorialsAndCelebrations = false
    let practiceSession: PracticeSession


    var noteSoundPlayer: NoteSoundPlayer { practiceSession.audio }
    var midiInputManager: MIDIInputManager { practiceSession.midi }

    init(
        practiceSession: PracticeSession,
        adaptiveStats: [AdaptiveNoteKey: AdaptiveNoteStats]
    ) {
        self.practiceSession = practiceSession
        _adaptiveStats = State(initialValue: adaptiveStats)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PracticeTabView(
                    currentNote: displayedCurrentNote,
                    promptSequence: displayedPromptSequence,
                    currentGuessIndex: displayedCurrentGuessIndex,
                    isStaffVisible: isStaffVisible,
                    isToneEnabled: isToneEnabled,
                    isAudioCacheLoading: noteSoundPlayer.isPreparingAudioCache,
                    flashColor: flashColor,
                    celebrationReasonText: celebrationReasonText,
                    noteScale: noteScale,
                    isNoteBounceEffectEnabled: isNoteBounceEffectEnabled,
                    isHelperGlowEnabled: isHelperGlowEnabled,
                    isTempoMeterEnabled: isTempoMeterEnabled,
                    usesNativeDarkPracticeColors: usesNativeDarkPracticeColors,
                    noteAppearanceID: noteAppearanceID,
                    noteDisappearanceID: noteDisappearanceID,
                    milestoneBurstProgress: milestoneBurstProgress,
                    octaveIntroduction: activeOctaveIntroduction,
                    octaveIntroductionNotes: staffOverviewNotes,
                    highlightedAnswers: keyboardHighlightedAnswers,
                    staffTutorialHelperText: staffTutorialHelperText,
                    keyboardHelperText: keyboardTutorialHelperText,
                    isWelcomeTutorialPrompt: isWelcomeTutorialPrompt,
                    simulatedKeyboardPress: simulatedKeyboardPress,
                    debugMelodyDisplayNumber: debugMelodyDisplayNumber,
                    debugSkipsTutorialsAndCelebrations: debugSkipsTutorialsAndCelebrations,
                    isTutorialActive: isTutorialActive,
                    isTutorialCompletionCelebrating: isShowingTutorialCompletion,
                    answerOptions: answerOptions,
                    isAllSoundsEnabled: isToneEnabled && isKeyboardEffectEnabled,
                    isKeyboardEffectEnabled: isKeyboardEffectEnabled,
                    isMIDIModeActive: isMIDIModeActive
                        && !isTutorialActive
                        && !isGuidedTutorialActive,
                    isMIDIDeviceConnected: midiInputManager.isDeviceConnected,
                    isMilestoneBurstHighlighted: isMilestoneBurstHighlighted,
                    onReplay: replayCurrentNote,
                    onAcknowledgeCelebration: acknowledgeCelebration,
                    onAcknowledgeStaffTutorial: acknowledgeStaffTutorialPrompt,
                    onAcknowledgeKeyboardTutorial: acknowledgeKeyboardTutorialPrompt,
                    onAcknowledgeOctaveIntroduction: acknowledgeOctaveIntroduction,
                    onDebugWin: debugWinCurrentNote,
                    onDebugToggleSkipTutorialsAndCelebrations: debugToggleSkipTutorialsAndCelebrations,
                    onDebugToggleAllSounds: debugToggleAllSounds,
                    onDebugPlayMelody: debugPlayMelody,
                    isAnswerCorrect: answerMatchesCurrentSequence,
                    onKeyboardPress: playKeyboardEffect,
                    onGuess: guess
                )
            }
            .tabItem {
                Label("Practice", systemImage: "music.quarternote.3")
            }
            .tag(AppTab.home)

            NavigationStack {
                ScoreTabView(
                    learnedStats: learnedStatRows,
                    answerOptions: answerOptions,
                    availableOctaves: availableOctaves,
                    completedTutorialIDs: completedTutorialIDs,
                    onOpenClefSettings: openClefSettingsFromProgress,
                    onResetScore: resetScore,
                    onPracticeBucket: practiceOnlyBucket,
                    onDebugToggleLearnedNote: debugToggleLearnedNote
                )
            }
            .tabItem {
                Label("Progress", systemImage: "chart.bar.fill")
            }
            .tag(AppTab.score)

            NavigationStack(path: $settingsNavigationPath) {
                PracticeSettingsView(
                    selectedClef: selectedClef,
                    includeSharps: includeSharps,
                    includeFlats: includeFlats,
                    sequenceLength: sequenceLength,
                    availableOctaves: availableOctaves,
                    selectedOctaves: selectedOctaves,
                    isStaffVisible: isStaffVisible,
                    isToneEnabled: isToneEnabled,
                    isPreparingAudioCache: noteSoundPlayer.isPreparingAudioCache,
                    isKeyboardEffectEnabled: isKeyboardEffectEnabled,
                    isNoteBounceEffectEnabled: isNoteBounceEffectEnabled,
                    isHelperGlowEnabled: isHelperGlowEnabled,
                    isTempoMeterEnabled: isTempoMeterEnabled,
                    usesNativeDarkPracticeColors: usesNativeDarkPracticeColors,
                    isMIDIDeviceConnected: midiInputManager.isDeviceConnected,
                    onSelectClefMode: updateClefMode,
                    onToggleAccidentals: toggleAccidentals,
                    onSelectSequenceLength: updateSequenceLength,
                    onToggleOctave: toggleOctave,
                    onToggleStaff: toggleStaffVisibility,
                    onToggleTone: toggleTone,
                    onToggleKeyboardEffect: toggleKeyboardEffect,
                    onToggleNoteBounceEffect: toggleNoteBounceEffect,
                    onToggleHelperGlow: toggleHelperGlow,
                    onToggleTempoMeter: toggleTempoMeter,
                    onToggleNativeDarkPracticeColors: toggleNativeDarkPracticeColors,
                    onResetTutorials: resetTutorials
                )
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .practiceCue:
                        PracticeCueSettingsView(
                            selectedClef: selectedClef,
                            includeSharps: includeSharps,
                            includeFlats: includeFlats,
                            sequenceLength: sequenceLength,
                            availableOctaves: availableOctaves,
                            selectedOctaves: selectedOctaves,
                            onSelectClefMode: updateClefMode,
                            onToggleAccidentals: toggleAccidentals,
                            onSelectSequenceLength: updateSequenceLength,
                            onToggleOctave: toggleOctave
                        )
                    }
                }
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .onAppear {
            synchronizeTutorialProgress()
            loadInitialNoteIfNeeded()
        }
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 4) {
                debugControls

                RollingFPSOverlay(
                    isCachingAudio: noteSoundPlayer.isPreparingAudioCache
                        || noteSoundPlayer.isWarmingAudioCache
                        || noteSoundPlayer.isPreparingCelebrationMelodyCache
                )
                .allowsHitTesting(false)
            }
            .padding(.top, 8)
            .padding(.trailing, 10)
        }
        #endif
        .tint(Theme.selectedControlTint)
        .task {
            for await noteNumber in midiInputManager.noteEvents() {
                handleMIDINoteNumber(noteNumber)
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            handleSelectedTabChange(from: oldValue, to: newValue)
        }
        .onChange(of: tutorialProgressID) { _, _ in
            synchronizeTutorialProgress()
        }
        .onChange(of: shouldShowWelcomeCelebration) { _, _ in
            playWelcomeCelebrationMusicIfNeeded()
        }
        .onChange(of: debugSkipsTutorialsAndCelebrations) { _, shouldSkip in
            handleDebugSkipTutorialsAndCelebrationsChange(shouldSkip)
        }
        #if DEBUG
        .onChange(of: debugSkippablePromptSignature) { _, _ in
            debugFinishAppearedTutorialsAndCelebrationsIfNeeded()
        }
        #endif
        .task {
            for await _ in noteSoundPlayer.playbackFinishedEvents() {
                guard isReplayWaitingForPlayback else { continue }
                isReplayWaitingForPlayback = false
                guard isReplayFeedbackDelayComplete else { continue }
                replayCurrentNote()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                drainMilestoneBurstProgress(at: Date())
            }
        }
    }

}
