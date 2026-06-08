import Combine
import Foundation
import Observation
import QuartzCore
import SwiftUI

#if DEBUG
/// Samples display refresh callbacks and exposes a one-second rolling frame rate.
@Observable
final class RollingFPSMonitor: NSObject {
    fileprivate(set) var framesPerSecond = 0

    let rollingWindow: CFTimeInterval = 1
    var displayLink: CADisplayLink?
    var frameTimestamps: [CFTimeInterval] = []

    func start() {
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        frameTimestamps.removeAll()
        framesPerSecond = 0
    }

    @objc func displayLinkDidTick(_ displayLink: CADisplayLink) {
        let currentTimestamp = displayLink.timestamp
        frameTimestamps.append(currentTimestamp)

        while let oldestTimestamp = frameTimestamps.first,
              currentTimestamp - oldestTimestamp > rollingWindow {
            frameTimestamps.removeFirst()
        }

        framesPerSecond = frameTimestamps.count
    }

    deinit {
        stop()
    }
}

/// Displays the current rolling frame rate in debug builds.
struct RollingFPSOverlay: View {
    @State var monitor = RollingFPSMonitor()

    let isCachingAudio: Bool

    var body: some View {
        HStack(spacing: 7) {
            Text("FPS \(monitor.framesPerSecond)")
            Text("|")
            Text(isCachingAudio ? "audio caching..." : "audio cached")
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.68), in: Capsule())
        .accessibilityHidden(true)
        .onAppear(perform: monitor.start)
        .onDisappear(perform: monitor.stop)
    }
}
#endif

/// Defines the app's primary bottom navigation destinations.
enum AppTab: Hashable {
    case home
    case score
    case settings
}

/// Defines destinations available inside the Settings navigation stack.
enum SettingsRoute: Hashable {
    case practiceCue
}

/// Identifies one score bucket for a specific clef and octave pair.
struct ScoreBucket: Hashable, Identifiable {
    let clef: Clef
    let octave: Int

    var id: String {
        "\(clef.rawValue)-\(octave)"
    }

    static let firstRecommended = ScoreBucket(clef: .treble, octave: 4)

    static let suggestedSequence = [
        firstRecommended,
        ScoreBucket(clef: .bass, octave: 3),
        ScoreBucket(clef: .treble, octave: 5),
        ScoreBucket(clef: .bass, octave: 2),
        ScoreBucket(clef: .treble, octave: 3),
        ScoreBucket(clef: .bass, octave: 4),
        ScoreBucket(clef: .treble, octave: 6),
        ScoreBucket(clef: .bass, octave: 5),
        ScoreBucket(clef: .treble, octave: 2),
        ScoreBucket(clef: .bass, octave: 6)
    ]
}

/// Presents the note practice interface on the Practice tab.
struct PracticeTabView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    let currentNote: QuizNote
    let promptSequence: [QuizNote]
    let currentGuessIndex: Int
    let isStaffVisible: Bool
    let isToneEnabled: Bool
    let isAudioCacheLoading: Bool
    let flashColor: Color
    let celebrationReasonText: String?
    let noteScale: Double
    let isNoteBounceEffectEnabled: Bool
    let isHelperGlowEnabled: Bool
    let isTempoMeterEnabled: Bool
    let usesNativeDarkPracticeColors: Bool
    let noteAppearanceID: Int
    let noteDisappearanceID: Int
    let milestoneBurstProgress: Double
    let octaveIntroduction: OctaveIntroduction?
    let octaveIntroductionNotes: [QuizNote]
    let highlightedAnswers: Set<NoteAnswer>
    let staffTutorialHelperText: String?
    let keyboardHelperText: String?
    let isWelcomeTutorialPrompt: Bool
    let simulatedKeyboardPress: SimulatedKeyboardPress?
    let debugMelodyDisplayNumber: Int
    let debugSkipsTutorialsAndCelebrations: Bool
    let isTutorialActive: Bool
    let isTutorialCompletionCelebrating: Bool
    let answerOptions: [NoteAnswer]
    let isAllSoundsEnabled: Bool
    let isKeyboardEffectEnabled: Bool
    let isMIDIModeActive: Bool
    let isMIDIDeviceConnected: Bool
    let isMilestoneBurstHighlighted: Bool
    let onReplay: () -> Void
    let onAcknowledgeCelebration: () -> Void
    let onAcknowledgeStaffTutorial: () -> Void
    let onAcknowledgeKeyboardTutorial: () -> Void
    let onAcknowledgeOctaveIntroduction: () -> Void
    let onDebugWin: () -> Void
    let onDebugToggleSkipTutorialsAndCelebrations: () -> Void
    let onDebugToggleAllSounds: () -> Void
    let onDebugPlayMelody: () -> Void
    let isAnswerCorrect: (NoteAnswer) -> Bool
    let onKeyboardPress: (NoteAnswer, Int?, Bool) -> Void
    let onGuess: (NoteAnswer) -> Void

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height && !usesCenteredPhoneLayout

            ZStack(alignment: .topLeading) {
                TabPageBackgroundView()

                if isTempoMeterEnabled {
                    PracticeAuroraEffectView(progress: milestoneBurstProgress)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                if isLandscape {
                    ScrollView(.vertical, showsIndicators: false) {
                        contentStack(isLandscape: true, availableWidth: proxy.size.width)
                            .frame(maxWidth: .infinity)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, Theme.pageHorizontalPadding)
                            .padding(.top, Theme.pageTopPadding)
                            .padding(.bottom, Theme.pageBottomPadding)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        contentStack(isLandscape: false, availableWidth: proxy.size.width)
                            .frame(maxWidth: Theme.centeredPhoneLayoutMaxWidth)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, Theme.pageHorizontalPadding)
                            .padding(.top, Theme.pageTopPadding)
                            .padding(.bottom, Theme.pageBottomPadding)
                    }
                }
            }
        }
        .navigationTitle("Practice")
    }

    var usesCenteredPhoneLayout: Bool {
        horizontalSizeClass == .regular
    }

    @ViewBuilder
    func contentStack(isLandscape: Bool, availableWidth: CGFloat) -> some View {
        VStack(spacing: Theme.settingsSectionSpacing) {
            if isLandscape {
                HStack(alignment: .top, spacing: Theme.panelSpacing) {
                    practicePanel
                        .frame(width: practicePanelWidth(for: availableWidth))

                    answerInputView
                    .frame(maxWidth: .infinity)
                }
            } else {
                practicePanel
                answerInputView
                Spacer(minLength: 0)
            }
        }
    }

    var practicePanel: some View {
        StaffPracticePanel(
            notes: promptSequence.isEmpty ? [currentNote] : promptSequence,
            octaveIntroductionNotes: octaveIntroductionNotes,
            currentGuessIndex: currentGuessIndex,
            isStaffVisible: isStaffVisible,
            isToneEnabled: isToneEnabled,
            isAudioCacheLoading: isAudioCacheLoading,
            flashColor: flashColor,
            celebrationReasonText: celebrationReasonText,
            tutorialHelperText: staffTutorialHelperText,
            isTutorialCelebratory: isWelcomeTutorialPrompt,
            noteScale: noteScale,
            isNoteBounceEffectEnabled: isNoteBounceEffectEnabled,
            isHelperGlowEnabled: isHelperGlowEnabled,
            usesNativeDarkPracticeColors: usesNativeDarkPracticeColors,
            noteAppearanceID: noteAppearanceID,
            noteDisappearanceID: noteDisappearanceID,
            onReplay: onReplay,
            onAcknowledgeCelebration: onAcknowledgeCelebration,
            onAcknowledgeTutorial: onAcknowledgeStaffTutorial
        )
    }

    var milestoneBurstProgressFillColor: Color {
        flashColor == .clear ? Theme.selectedControlTint : flashColor
    }

    @ViewBuilder
    var debugControls: some View {
        #if DEBUG
        HStack(spacing: 8) {
            debugIconButton(
                systemImage: isAllSoundsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                accessibilityLabel: isAllSoundsEnabled ? "Debug disable all sounds" : "Debug enable all sounds",
                action: onDebugToggleAllSounds
            )

            debugIconButton(
                systemImage: "checkmark.seal.fill",
                accessibilityLabel: "Debug win current note",
                action: onDebugWin
            )

            debugIconButton(
                systemImage: debugSkipsTutorialsAndCelebrations ? "forward.end.fill" : "forward.end",
                accessibilityLabel: "Debug skip all tutorials and celebrations",
                accessibilityValue: debugSkipsTutorialsAndCelebrations ? "On" : "Off",
                action: onDebugToggleSkipTutorialsAndCelebrations
            )

            debugTextButton(
                title: "\(debugMelodyDisplayNumber)",
                accessibilityLabel: "Debug play melody",
                action: onDebugPlayMelody
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
                .foregroundStyle(.white)
                .frame(width: Theme.debugControlVisualSize, height: Theme.debugControlVisualSize)
                .background {
                    Circle()
                        .fill(Theme.selectedControlTint)
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
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 10)
                .frame(minWidth: Theme.debugControlHitSize)
                .frame(height: Theme.debugControlVisualSize)
                .background {
                    Capsule()
                        .fill(Theme.selectedControlTint)
                }
                .frame(height: Theme.debugControlHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    var answerInputView: some View {
        if isMIDIModeActive {
            MIDIGuessView(
                isMIDIDeviceConnected: isMIDIDeviceConnected,
                isAllSoundsEnabled: isAllSoundsEnabled,
                debugMelodyDisplayNumber: debugMelodyDisplayNumber,
                debugSkipsTutorialsAndCelebrations: debugSkipsTutorialsAndCelebrations,
                usesNativeDarkPracticeColors: usesNativeDarkPracticeColors,
                isNoteBounceEffectEnabled: isNoteBounceEffectEnabled,
                isMilestoneBurstEnabled: isTempoMeterEnabled && !isTutorialActive,
                milestoneBurstProgress: milestoneBurstProgress,
                milestoneBurstFillColor: milestoneBurstProgressFillColor,
                isMilestoneBurstHighlighted: isMilestoneBurstHighlighted,
                octaveIntroductionText: octaveIntroduction?.promptText,
                onAcknowledgeOctaveIntroduction: onAcknowledgeOctaveIntroduction,
                onDebugWin: onDebugWin,
                onDebugToggleSkipTutorialsAndCelebrations: onDebugToggleSkipTutorialsAndCelebrations,
                onDebugToggleAllSounds: onDebugToggleAllSounds,
                onDebugPlayMelody: onDebugPlayMelody
            )
        } else {
            NoteKeyboardView(
                answers: answerOptions,
                highlightedAnswers: highlightedAnswers,
                octave: currentNote.octave,
                tutorialHelperText: keyboardHelperText,
                octaveIntroductionText: octaveIntroduction?.promptText,
                simulatedPress: simulatedKeyboardPress,
                debugMelodyDisplayNumber: debugMelodyDisplayNumber,
                debugSkipsTutorialsAndCelebrations: debugSkipsTutorialsAndCelebrations,
                isAllSoundsEnabled: isAllSoundsEnabled,
                isKeyboardEffectEnabled: isKeyboardEffectEnabled,
                isInputEnabled: octaveIntroduction == nil && staffTutorialHelperText == nil && keyboardHelperText == nil,
                isNoteBounceEffectEnabled: isNoteBounceEffectEnabled,
                usesNativeDarkPracticeColors: usesNativeDarkPracticeColors,
                isMilestoneBurstEnabled: isTempoMeterEnabled && !isTutorialActive,
                milestoneBurstProgress: milestoneBurstProgress,
                milestoneBurstFillColor: milestoneBurstProgressFillColor,
                isMilestoneBurstHighlighted: isMilestoneBurstHighlighted,
                isAnswerCorrect: isAnswerCorrect,
                onKeyPress: onKeyboardPress,
                onGuess: onGuess,
                onDebugWin: onDebugWin,
                onDebugToggleSkipTutorialsAndCelebrations: onDebugToggleSkipTutorialsAndCelebrations,
                onDebugToggleAllSounds: onDebugToggleAllSounds,
                onDebugPlayMelody: onDebugPlayMelody,
                onAcknowledgeTutorial: octaveIntroduction == nil ? onAcknowledgeKeyboardTutorial : onAcknowledgeOctaveIntroduction
            )
        }
    }

    func practicePanelWidth(for availableWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 36
        let contentWidth = max(availableWidth - horizontalPadding - Theme.panelSpacing, 0)

        return max(contentWidth * 0.44, 220)
    }
}

/// Displays persistent learned progress by note.
struct ScoreTabView: View {
    let learnedStats: [LearnedNoteStatRow]
    let answerOptions: [NoteAnswer]
    let availableOctaves: [Int]
    let completedTutorialIDs: Set<TutorialProgressID>
    let onOpenClefSettings: () -> Void
    let onResetScore: () -> Void
    let onPracticeBucket: (ScoreBucket) -> Void
    let onDebugToggleLearnedNote: (AdaptiveNoteKey) -> Void
    @State var isResetConfirmationPresented = false
    @State var expandedGroupIDs: Set<String> = []
    @State var progressHelpPresentationID = 0

    var body: some View {
        Form {
            Section {
                HStack {
                    Button {
                        progressHelpPresentationID += 1
                    } label: {
                        Label("How Progress Works", systemImage: "questionmark.circle")
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    HelpPopoverButton(
                        title: "How Progress Works",
                        text: "A Note is learned after three quick correct answers. Notes that have not been learned appear more often. Misses, longer answers, and corrections after a miss in the same Cue do not change Note Progress. New Clefs and Octaves appear after the current ones are learned. Some Octaves also need their Tutorial finished before they show a checkmark.",
                        presentationID: progressHelpPresentationID
                    )
                }

                if learnedGroups.isEmpty {
                    Text("Answer Notes to build Octave Progress.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(learnedGroups) { group in
                        learnedGroupView(group)
                    }
                }
            }

            Section {
                Button(action: onOpenClefSettings) {
                    HStack {
                        Label("Practice Cue", systemImage: "music.note.list")

                        Spacer()

                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }

            Section {
                HStack {
                    Button(role: .destructive) {
                        isResetConfirmationPresented = true
                    } label: {
                        Label("Reset Progress", systemImage: "arrow.counterclockwise")
                    }

                    Spacer()

                    HelpPopoverButton(
                        title: "Reset Progress",
                        text: "Clears Note Progress stored on this device."
                    )
                }
                .confirmationDialog("Are you sure?", isPresented: $isResetConfirmationPresented, titleVisibility: .visible) {
                    Button("Reset Progress", role: .destructive, action: onResetScore)
                    Button("Cancel", role: .cancel) { }
                }
            }
        }
        .navigationTitle("Progress")
        .scrollContentBackground(.hidden)
        .background(TabPageBackgroundView())
        .tint(Theme.selectedControlTint)
    }

    var learnedGroups: [LearnedNoteStatGroup] {
        let groupedRows = Dictionary(grouping: learnedStats) { row in
            ScoreBucket(clef: row.key.clef, octave: row.key.octave)
        }
        let learnedStatsByKey = Dictionary(uniqueKeysWithValues: learnedStats.map { ($0.key, $0.stats) })

        var groups = groupedRows.keys
            .map { learnedGroup(bucket: $0, learnedStatsByKey: learnedStatsByKey) }
            .sorted(by: learnedGroupOrder)

        if !groups.contains(where: { $0.averageLearnedPercent < 100 }),
           let nextBucket = nextUnstartedBucket(after: groups.map(\.bucket)) {
            groups.append(learnedGroup(bucket: nextBucket, learnedStatsByKey: learnedStatsByKey))
            groups.sort(by: learnedGroupOrder)
        }

        return groups
    }

    @ViewBuilder
    func learnedGroupView(_ group: LearnedNoteStatGroup) -> some View {
        let isExpanded = expandedGroupIDs.contains(group.id)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack {
                    Label {
                        Text(group.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } icon: {
                        OctaveLearnedProgressAccessory(
                            learnedPercent: group.averageLearnedPercent,
                            canShowCheckmark: group.canShowCheckmark
                        )
                    }
                    .foregroundStyle(.primary)
                    .labelStyle(.titleAndIcon)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)

                    Spacer(minLength: 0)

                    Button("Practice") {
                        onPracticeBucket(group.bucket)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Practice \(group.title)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleExpandedGroup(group.id)
                }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            }

            if isExpanded {
                LazyVGrid(columns: learnedNoteGridColumns, alignment: .center, spacing: 16) {
                    ForEach(group.rows) { row in
                        LearnedNoteProgressCell(
                            row: row,
                            onDebugToggleLearnedNote: onDebugToggleLearnedNote
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
            }
        }
    }

    var learnedNoteGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 56, maximum: 56), spacing: 16)
        ]
    }

    func toggleExpandedGroup(_ id: String) {
        if expandedGroupIDs.contains(id) {
            expandedGroupIDs.remove(id)
        } else {
            expandedGroupIDs.insert(id)
        }
    }

    func clefSortOrder(_ clef: Clef) -> Int {
        switch clef {
        case .treble:
            return 0
        case .bass:
            return 1
        }
    }

    func learnedGroup(
        bucket: ScoreBucket,
        learnedStatsByKey: [AdaptiveNoteKey: AdaptiveNoteStats]
    ) -> LearnedNoteStatGroup {
        let rows = AdaptiveLearningStore.zeroProgressRows(
            clef: bucket.clef,
            octave: bucket.octave,
            answerOptions: answerOptions
        )
        .map { row in
            LearnedNoteStatRow(key: row.key, stats: learnedStatsByKey[row.key] ?? row.stats)
        }

        return LearnedNoteStatGroup(
            bucket: bucket,
            rows: rows.sorted(by: learnedNoteKeyboardOrder),
            canShowCheckmark: canShowCompletionCheckmark(for: bucket)
        )
    }

    func canShowCompletionCheckmark(for bucket: ScoreBucket) -> Bool {
        guard let tutorialID = TutorialProgressID.allCases.first(where: { tutorialID in
            guard let requiredPractice = tutorialID.requiredPractice else { return false }
            return requiredPractice.clef == bucket.clef && requiredPractice.octave == bucket.octave
        }) else { return true }

        return completedTutorialIDs.contains(tutorialID)
    }

    func nextUnstartedBucket(after displayedBuckets: [ScoreBucket]) -> ScoreBucket? {
        let displayedBucketSet = Set(displayedBuckets)
        return ScoreBucket.suggestedSequence.first {
            availableOctaves.contains($0.octave) && !displayedBucketSet.contains($0)
        }
    }

    func learnedGroupOrder(_ left: LearnedNoteStatGroup, _ right: LearnedNoteStatGroup) -> Bool {
        if left.bucket.clef != right.bucket.clef {
            return clefSortOrder(left.bucket.clef) < clefSortOrder(right.bucket.clef)
        }

        return left.bucket.octave < right.bucket.octave
    }

    func learnedNoteKeyboardOrder(_ left: LearnedNoteStatRow, _ right: LearnedNoteStatRow) -> Bool {
        let leftOrder = keyboardOrder(for: left.key)
        let rightOrder = keyboardOrder(for: right.key)

        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }

        return left.key.noteLabel < right.key.noteLabel
    }

    func keyboardOrder(for key: AdaptiveNoteKey) -> Int {
        switch (key.letter, key.accidental) {
        case ("C", .natural): return 0
        case ("C", .sharp), ("D", .flat): return 1
        case ("D", .natural): return 2
        case ("D", .sharp), ("E", .flat): return 3
        case ("E", .natural): return 4
        case ("F", .natural): return 5
        case ("F", .sharp), ("G", .flat): return 6
        case ("G", .natural): return 7
        case ("G", .sharp), ("A", .flat): return 8
        case ("A", .natural): return 9
        case ("A", .sharp), ("B", .flat): return 10
        case ("B", .natural): return 11
        default: return 12
        }
    }
}

/// Groups learned note stats for one clef and octave section.
struct LearnedNoteStatGroup: Identifiable {
    let bucket: ScoreBucket
    let rows: [LearnedNoteStatRow]
    let canShowCheckmark: Bool

    var id: String {
        bucket.id
    }

    var clef: Clef {
        bucket.clef
    }

    var octave: Int {
        bucket.octave
    }

    var title: String {
        "\(bucket.clef.rawValue.capitalized) Clef, Octave \(bucket.octave)"
    }

    var averageLearnedPercent: Int {
        guard !rows.isEmpty else { return 0 }
        let total = rows.reduce(0) { $0 + $1.stats.learnedPercent }
        return Int((Double(total) / Double(rows.count)).rounded())
    }

}

/// Shows one note's learned progress as a compact circular grid item.
struct LearnedNoteProgressCell: View {
    let row: LearnedNoteStatRow
    let onDebugToggleLearnedNote: (AdaptiveNoteKey) -> Void

    var body: some View {
        LearnedProgressAccessory(
            learnedPercent: row.stats.learnedPercent,
            label: row.key.noteLabel
        )
        .frame(width: 56, height: 56)
        .contentShape(Rectangle())
        #if DEBUG
        .onTapGesture {
            onDebugToggleLearnedNote(row.key)
        }
        .accessibilityHint("Debug toggle learned state")
        #endif
        .accessibilityLabel(row.key.noteLabel)
    }
}

/// Shows octave learned progress as a compact circular gauge.
struct OctaveLearnedProgressAccessory: View {
    let learnedPercent: Int
    let canShowCheckmark: Bool

    var body: some View {
        LearnedProgressRing(progress: learnedPercent) {
            if learnedPercent >= 100 && canShowCheckmark {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.selectedControlTint)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityValue("\(learnedPercent) percent")
    }
}

/// Shows learned progress without exposing exact percentages.
struct LearnedProgressAccessory: View {
    let learnedPercent: Int
    var label: String?

    var body: some View {
        LearnedProgressRing(progress: learnedPercent) {
            if let label {
                Text(label)
                    .font(.caption.weight(.bold))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
        }
        .accessibilityValue("\(learnedPercent) percent learned")
    }
}

/// Draws learned progress as a circular fill ring.
struct LearnedProgressRing<Label: View>: View {
    let progress: Int
    @ViewBuilder let label: Label

    var clampedProgress: Double {
        Double(min(max(progress, 0), 100)) / 100
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 5)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    Theme.selectedControlTint,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.35), value: clampedProgress)

            label
        }
    }
}

/// Presents brief explanations using the native popover presentation.
struct HelpPopoverButton: View {
    @State var isHelpPresented = false

    let title: String
    let text: String
    let presentationID: Int

    init(
        title: String,
        text: String,
        presentationID: Int = 0
    ) {
        self.title = title
        self.text = text
        self.presentationID = presentationID
    }

    var body: some View {
        Button {
            isHelpPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.body)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(title) Help")
        .help(text)
        .onChange(of: presentationID) { _, _ in
            isHelpPresented = true
        }
        .popover(isPresented: $isHelpPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(nil)

                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 280, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Draws the shared grouped background used behind each primary tab.
struct TabPageBackgroundView: View {
    var body: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }
}

/// Groups nearby glass surfaces so Liquid Glass can render them cohesively.
struct GlassEffectGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

/// Draws a reusable Liquid Glass rounded background surface.
struct GlassBackgroundView: View {
    @Environment(\.colorScheme) var colorScheme

    let tint: Color
    let cornerRadius: CGFloat
    let isInteractive: Bool

    var body: some View {
        if isInteractive {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.opacity(0.5))
                .modifier(GlassSurface(tint: tint, cornerRadius: cornerRadius, isInteractive: true))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0 : 0.42), lineWidth: 1)
                }
        }
    }
}

/// Wraps content in the app's shared glass panel styling.
struct GlassSection<Content: View>: View {
    let tint: Color
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    init(
        tint: Color = .white,
        cornerRadius: CGFloat = Theme.panelCornerRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(Theme.panelContentPadding)
            .background {
                GlassBackgroundView(
                    tint: tint,
                    cornerRadius: cornerRadius,
                    isInteractive: false
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 24, y: 14)
    }
}

/// Styles compact option buttons with the app's glass treatment.
struct GlassChipButtonStyle: ButtonStyle {
    let tint: Color
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background {
                GlassBackgroundView(
                    tint: tint,
                    cornerRadius: 18,
                    isInteractive: true
                )
                .opacity(configuration.isPressed ? 0.88 : 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .foregroundStyle(
                isSelected
                    ? Color(red: 0.09, green: 0.16, blue: 0.26)
                    : Color(red: 0.2, green: 0.28, blue: 0.39)
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Styles piano key buttons for the answer keyboard.
struct GlassPianoKeyStyle: ButtonStyle {
    let tint: Color
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                GlassBackgroundView(
                    tint: tint,
                    cornerRadius: cornerRadius,
                    isInteractive: true
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            Color.white.opacity(0.42),
                            lineWidth: 1
                        )
                )
                .opacity(configuration.isPressed ? 0.84 : 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Applies the shared Liquid Glass effect used across the app.
struct GlassSurface: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(
            .regular
                .tint(tint.opacity(0.45))
                .interactive(isInteractive),
            in: .rect(cornerRadius: cornerRadius)
        )
    }
}
