import SwiftUI

/// Describes a keyboard tap initiated by app logic instead of direct touch input.
struct SimulatedKeyboardPress: Equatable {
    let id: Int
    let answer: NoteAnswer
    let octave: Int?
    let submitsGuess: Bool
    let forcesSound: Bool
    let suppressesSound: Bool
    let pulseTint: KeyboardPressPulseTint
}

/// Selects the visual feedback color for a keyboard tap pulse.
enum KeyboardPressPulseTint: Equatable {
    case evaluated
    case accent
}

/// Shows the answer keyboard used to submit note guesses.
struct NoteKeyboardView: View {
    let answers: [NoteAnswer]
    let highlightedAnswers: Set<NoteAnswer>
    let octave: Int
    let tutorialHelperText: String?
    let octaveIntroductionText: String?
    let simulatedPress: SimulatedKeyboardPress?
    let debugMelodyDisplayNumber: Int
    let debugSkipsTutorialsAndCelebrations: Bool
    let isAllSoundsEnabled: Bool
    let isKeyboardEffectEnabled: Bool
    let isInputEnabled: Bool
    let isNoteBounceEffectEnabled: Bool
    let usesNativeDarkPracticeColors: Bool
    let isMilestoneBurstEnabled: Bool
    let milestoneBurstProgress: Double
    let milestoneBurstFillColor: Color
    let isMilestoneBurstHighlighted: Bool
    let isAnswerCorrect: (NoteAnswer) -> Bool
    let onKeyPress: (NoteAnswer, Int?, Bool) -> Void
    let onGuess: (NoteAnswer) -> Void
    let onDebugWin: () -> Void
    let onDebugToggleSkipTutorialsAndCelebrations: () -> Void
    let onDebugToggleAllSounds: () -> Void
    let onDebugPlayMelody: () -> Void
    let onAcknowledgeTutorial: () -> Void

    private let naturalLetters = ["C", "D", "E", "F", "G", "A", "B"]
    private let sharpLetters = ["C", "D", "F", "G", "A"]
    private let flatLetters = ["D", "E", "G", "A", "B"]

    var body: some View {
        GlassSection(tint: panelTint) {
            ZStack(alignment: .topTrailing) {
                keyboardContent
                    .opacity(activePromptText == nil ? 1 : 0)
                    .allowsHitTesting(activePromptText == nil)

                if let activePromptText {
                    PromptOverlayView(
                        systemImage: "questionmark.circle.fill",
                        text: activePromptText,
                        allowsMotion: isNoteBounceEffectEnabled
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous))
                    .transition(.opacity)
                }

                if activePromptText == nil {
                    octaveLabel
                }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.panelHeight)
            .animation(.easeOutCubic(duration: 0.24), value: isMilestoneBurstEnabled)
        }
        .promptPanelBehavior(
            promptKey: activePromptText ?? "",
            isActive: activePromptText != nil,
            allowsMotion: isNoteBounceEffectEnabled,
            onAcknowledge: onAcknowledgeTutorial
        )
        .practiceSurfaceColorScheme(
            usesNativeDarkPracticeColors: usesNativeDarkPracticeColors
        )
    }

    private var panelTint: Color {
        if activePromptText != nil {
            return Theme.selectedControlTint
        }

        return usesNativeDarkPracticeColors ? Theme.nativePracticePanelSurface : Theme.practicePanelSurface
    }

    private var activePromptText: String? {
        octaveIntroductionText ?? tutorialHelperText
    }

    private var keyboardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)

            PianoKeyboardRow(
                answers: answers,
                highlightedAnswers: highlightedAnswers,
                isKeyboardEffectEnabled: isKeyboardEffectEnabled,
                usesNativeDarkPracticeColors: usesNativeDarkPracticeColors,
                naturalLetters: naturalLetters,
                sharpLetters: sharpLetters,
                flatLetters: flatLetters,
                simulatedPress: simulatedPress,
                isAnswerCorrect: isAnswerCorrect,
                onKeyPress: onKeyPress,
                onGuess: onGuess
            )
            .padding(.bottom, 8)
            .frame(height: 96)
            .allowsHitTesting(isInputEnabled)

            Spacer(minLength: 0)

            bottomStatusSlot
        }
    }

    private var octaveLabel: some View {
        Text("Octave \(octave)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.practicePanelSecondaryTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 10)
            .padding(.trailing, 12)
            .accessibilityLabel("Octave \(octave)")
    }

    @ViewBuilder
    private var bottomStatusSlot: some View {
        if isMilestoneBurstEnabled {
            MilestoneBurstProgressView(
                progress: milestoneBurstProgress,
                fillColor: milestoneBurstFillColor,
                isHighlighted: isMilestoneBurstHighlighted
            )
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var debugControls: some View {
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
        .padding(12)
        #endif
    }

    private func debugIconButton(
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

    private func debugTextButton(
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
}

/// Prompts the user to answer by playing the note on a connected MIDI keyboard.
struct MIDIGuessView: View {
    let isMIDIDeviceConnected: Bool
    let isAllSoundsEnabled: Bool
    let debugMelodyDisplayNumber: Int
    let debugSkipsTutorialsAndCelebrations: Bool
    let usesNativeDarkPracticeColors: Bool
    let isNoteBounceEffectEnabled: Bool
    let isMilestoneBurstEnabled: Bool
    let milestoneBurstProgress: Double
    let milestoneBurstFillColor: Color
    let isMilestoneBurstHighlighted: Bool
    let octaveIntroductionText: String?
    let onAcknowledgeOctaveIntroduction: () -> Void
    let onDebugWin: () -> Void
    let onDebugToggleSkipTutorialsAndCelebrations: () -> Void
    let onDebugToggleAllSounds: () -> Void
    let onDebugPlayMelody: () -> Void

    var body: some View {
        GlassSection(tint: panelTint) {
            ZStack {
                midiContent
                    .opacity(octaveIntroductionText == nil ? 1 : 0)

                if let octaveIntroductionText {
                    PromptOverlayView(
                        systemImage: "questionmark.circle.fill",
                        text: octaveIntroductionText,
                        allowsMotion: isNoteBounceEffectEnabled
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous))
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.panelHeight)
            .padding(.vertical, 6)
        }
        .promptPanelBehavior(
            promptKey: octaveIntroductionText ?? "",
            isActive: octaveIntroductionText != nil,
            allowsMotion: isNoteBounceEffectEnabled,
            onAcknowledge: onAcknowledgeOctaveIntroduction
        )
        .practiceSurfaceColorScheme(
            usesNativeDarkPracticeColors: usesNativeDarkPracticeColors
        )
    }

    private var panelTint: Color {
        if octaveIntroductionText != nil {
            return Theme.selectedControlTint
        }

        return usesNativeDarkPracticeColors ? Theme.nativePracticePanelSurface : Theme.practicePanelSurface
    }

    private var midiContent: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Image(systemName: isMIDIDeviceConnected ? "pianokeys.inverse" : "cable.connector.slash")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.practicePanelPrimaryTextColor)

                Text(isMIDIDeviceConnected ? "Play your answer on the MIDI keyboard" : "Connect a MIDI keyboard to answer here")
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.practicePanelPrimaryTextColor)

                Text(isMIDIDeviceConnected ? "Each Note you play is submitted as an answer." : "MIDI mode becomes active during regular Practice when a device is available.")
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.practicePanelSecondaryTextColor)
            }

            Spacer(minLength: 0)

            milestoneBurstProgressView
        }
    }

    @ViewBuilder
    private var milestoneBurstProgressView: some View {
        if isMilestoneBurstEnabled {
            MilestoneBurstProgressView(
                progress: milestoneBurstProgress,
                fillColor: milestoneBurstFillColor,
                isHighlighted: isMilestoneBurstHighlighted
            )
        }
    }

    @ViewBuilder
    private var debugControls: some View {
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
        .padding(12)
        #endif
    }

    private func debugIconButton(
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

    private func debugTextButton(
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
}

/// Lays out white and black piano keys for the answer keyboard.
private struct PianoKeyboardRow: View {
    @State private var activeGestureAnswer: NoteAnswer?
    @State private var pressedAnswer: NoteAnswer?
    @State private var pulseAnswer: NoteAnswer?
    @State private var pulseTint = Theme.selectedControlTint
    @State private var pulseID = 0
    @State private var lastSimulatedPressID = 0
    @State private var pendingSimulatedReleaseTask: Task<Void, Never>?

    let answers: [NoteAnswer]
    let highlightedAnswers: Set<NoteAnswer>
    let isKeyboardEffectEnabled: Bool
    let usesNativeDarkPracticeColors: Bool
    let naturalLetters: [String]
    let sharpLetters: [String]
    let flatLetters: [String]
    let simulatedPress: SimulatedKeyboardPress?
    let isAnswerCorrect: (NoteAnswer) -> Bool
    let onKeyPress: (NoteAnswer, Int?, Bool) -> Void
    let onGuess: (NoteAnswer) -> Void

    private let simulatedPressHoldDuration: TimeInterval = 0.11

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let availableWhiteKeyWidth = max(
                proxy.size.width - spacing * CGFloat(naturalLetters.count - 1),
                0
            )
            let whiteKeyWidth = availableWhiteKeyWidth / CGFloat(naturalLetters.count)
            let blackKeyWidth = max(whiteKeyWidth * 0.62, 0)
            let blackKeyHeight = max(proxy.size.height * 0.64, 0)

            keyboardStack(
                proxy: proxy,
                spacing: spacing,
                whiteKeyWidth: whiteKeyWidth,
                blackKeyWidth: blackKeyWidth,
                blackKeyHeight: blackKeyHeight
            )
        }
    }

    @ViewBuilder
    private func keyboardStack(
        proxy: GeometryProxy,
        spacing: CGFloat,
        whiteKeyWidth: CGFloat,
        blackKeyWidth: CGFloat,
        blackKeyHeight: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: spacing) {
                ForEach(naturalLetters, id: \.self) { letter in
                    if let answer = answer(letter: letter, accidental: .natural) {
                        PianoKeyView(
                            title: answer.label,
                            foreground: whiteKeyForeground,
                            tint: whiteKeyTint,
                            height: proxy.size.height,
                            isHighlighted: highlightedAnswers.contains(answer),
                            isPressed: pressedAnswer == answer,
                            pulseID: keyPulseID(for: answer),
                            pulseTint: keyPulseTint(for: answer)
                        )
                        .frame(width: whiteKeyWidth)
                        .accessibilityLabel(answer.label)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            playKeyboardEffectIfNeeded(for: answer, octave: nil, force: false)
                            onGuess(answer)
                        }
                    }
                }
            }

            ForEach(Array(sharpLetters.enumerated()), id: \.element) { blackKeyIndex, letter in
                let answer = blackKeyAnswer(
                    sharpLetter: letter,
                    flatLetter: flatLetters[blackKeyIndex]
                )

                if let index = naturalLetters.firstIndex(of: letter) {
                    PianoBlackKeyView(
                        height: blackKeyHeight,
                        tint: blackKeyTint,
                        strokeColor: blackKeyStrokeColor,
                        isHighlighted: highlightedAnswers.contains(answer),
                        isPressed: pressedAnswer == answer,
                        pulseID: keyPulseID(for: answer),
                        pulseTint: keyPulseTint(for: answer)
                    )
                    .frame(width: blackKeyWidth)
                    .position(
                        x: sharpKeyCenterX(
                            afterWhiteKeyAt: index,
                            whiteKeyWidth: whiteKeyWidth,
                            blackKeyWidth: blackKeyWidth,
                            spacing: spacing
                        ),
                        y: blackKeyHeight / 2
                    )
                    .zIndex(1)
                    .accessibilityLabel(answer.label)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        playKeyboardEffectIfNeeded(for: answer, octave: nil, force: false)
                        onGuess(answer)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            keyboardGesture(
                proxy: proxy,
                spacing: spacing,
                whiteKeyWidth: whiteKeyWidth,
                blackKeyWidth: blackKeyWidth,
                blackKeyHeight: blackKeyHeight
            )
        )
        .onChange(of: simulatedPress) { _, newValue in
            guard let newValue, newValue.id > lastSimulatedPressID else { return }
            lastSimulatedPressID = newValue.id
            performSimulatedPress(newValue)
        }
        .onDisappear {
            pendingSimulatedReleaseTask?.cancel()
            pendingSimulatedReleaseTask = nil
            activeGestureAnswer = nil
            pressedAnswer = nil
        }
    }

    private func answer(letter: String, accidental: Accidental) -> NoteAnswer? {
        answers.first { $0.letter == letter && $0.accidental == accidental }
    }

    private func keyPulseID(for answer: NoteAnswer) -> Int {
        pulseAnswer == answer ? pulseID : 0
    }

    private func keyPulseTint(for answer: NoteAnswer) -> Color {
        pulseAnswer == answer ? pulseTint : Theme.selectedControlTint
    }

    private var whiteKeyForeground: Color {
        usesNativeDarkPracticeColors ? Theme.nativeNotationColor : Theme.notationColor
    }

    private var whiteKeyTint: Color {
        usesNativeDarkPracticeColors ? Theme.nativePianoKeySurface : Color.white.opacity(0.92)
    }

    private var blackKeyTint: Color {
        usesNativeDarkPracticeColors ? Theme.nativeBlackPianoKeySurface : Color.black
    }

    private var blackKeyStrokeColor: Color {
        usesNativeDarkPracticeColors ? Color(uiColor: .separator).opacity(0.55) : Color.white.opacity(0.08)
    }

    private func blackKeyAnswer(sharpLetter: String, flatLetter: String) -> NoteAnswer {
        if let preferredSharp = answer(letter: sharpLetter, accidental: .sharp) {
            return preferredSharp
        }

        if let preferredFlat = answer(letter: flatLetter, accidental: .flat) {
            return preferredFlat
        }

        return NoteAnswer(letter: sharpLetter, accidental: .sharp)
    }

    private func playKeyboardEffectIfNeeded(for answer: NoteAnswer, octave: Int?, force: Bool) {
        guard force || isKeyboardEffectEnabled else { return }
        onKeyPress(answer, octave, force)
    }

    private func beginPressFeedback(for answer: NoteAnswer, pulseTint requestedPulseTint: KeyboardPressPulseTint = .evaluated) {
        pulseAnswer = answer
        switch requestedPulseTint {
        case .evaluated:
            pulseTint = isAnswerCorrect(answer) ? Theme.selectedControlTint : Theme.failedAnswerFeedbackTint
        case .accent:
            pulseTint = Theme.selectedControlTint
        }
        pulseID += 1
        pressedAnswer = answer
    }

    private func performSimulatedPress(_ simulatedPress: SimulatedKeyboardPress) {
        AppLog.input.info("Simulated keyboard tap started; submits guess \(simulatedPress.submitsGuess, privacy: .public)")
        pendingSimulatedReleaseTask?.cancel()
        beginPressFeedback(for: simulatedPress.answer, pulseTint: simulatedPress.pulseTint)
        if !simulatedPress.suppressesSound {
            playKeyboardEffectIfNeeded(
                for: simulatedPress.answer,
                octave: simulatedPress.octave,
                force: simulatedPress.forcesSound
            )
        }

        let releaseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            if simulatedPress.submitsGuess {
                onGuess(simulatedPress.answer)
            }

            if pressedAnswer == simulatedPress.answer {
                pressedAnswer = nil
            }
        }

        pendingSimulatedReleaseTask = releaseTask
    }

    private func sharpKeyCenterX(
        afterWhiteKeyAt index: Int,
        whiteKeyWidth: CGFloat,
        blackKeyWidth: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        let whiteKeyLeadingX = CGFloat(index) * (whiteKeyWidth + spacing)
        return whiteKeyLeadingX + whiteKeyWidth + spacing / 2
    }

    private func keyboardGesture(
        proxy: GeometryProxy,
        spacing: CGFloat,
        whiteKeyWidth: CGFloat,
        blackKeyWidth: CGFloat,
        blackKeyHeight: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let nextAnswer = answer(
                    at: value.location,
                    keyboardHeight: proxy.size.height,
                    spacing: spacing,
                    whiteKeyWidth: whiteKeyWidth,
                    blackKeyWidth: blackKeyWidth,
                    blackKeyHeight: blackKeyHeight
                )
                let resolvedAnswer = activeGestureAnswer ?? nextAnswer

                if activeGestureAnswer == nil {
                    activeGestureAnswer = nextAnswer
                    if let nextAnswer {
                        playKeyboardEffectIfNeeded(for: nextAnswer, octave: nil, force: false)
                    }
                }

                if resolvedAnswer != pressedAnswer {
                    if let resolvedAnswer {
                        beginPressFeedback(for: resolvedAnswer)
                    }
                }

                pressedAnswer = resolvedAnswer
            }
            .onEnded { value in
                let finalAnswer = answer(
                    at: value.location,
                    keyboardHeight: proxy.size.height,
                    spacing: spacing,
                    whiteKeyWidth: whiteKeyWidth,
                    blackKeyWidth: blackKeyWidth,
                    blackKeyHeight: blackKeyHeight
                )
                let resolvedAnswer = activeGestureAnswer ?? finalAnswer

                if let answer = resolvedAnswer {
                    AppLog.input.info("On-screen keyboard answer submitted")
                    onGuess(answer)
                }

                activeGestureAnswer = nil
                pressedAnswer = nil
            }
    }

    private func answer(
        at location: CGPoint,
        keyboardHeight: CGFloat,
        spacing: CGFloat,
        whiteKeyWidth: CGFloat,
        blackKeyWidth: CGFloat,
        blackKeyHeight: CGFloat
    ) -> NoteAnswer? {
        guard location.x >= 0, location.y >= 0, location.y <= keyboardHeight else {
            return nil
        }

        if location.y <= blackKeyHeight {
            for (blackKeyIndex, letter) in sharpLetters.enumerated() {
                guard let index = naturalLetters.firstIndex(of: letter) else { continue }

                let centerX = sharpKeyCenterX(
                    afterWhiteKeyAt: index,
                    whiteKeyWidth: whiteKeyWidth,
                    blackKeyWidth: blackKeyWidth,
                    spacing: spacing
                )
                let leftEdge = centerX - blackKeyWidth / 2
                let rightEdge = centerX + blackKeyWidth / 2

                if location.x >= leftEdge, location.x <= rightEdge {
                    return blackKeyAnswer(
                        sharpLetter: letter,
                        flatLetter: flatLetters[blackKeyIndex]
                    )
                }
            }
        }

        for (index, letter) in naturalLetters.enumerated() {
            let leftEdge = CGFloat(index) * (whiteKeyWidth + spacing)
            let rightEdge = leftEdge + whiteKeyWidth

            if location.x >= leftEdge, location.x <= rightEdge {
                return answer(letter: letter, accidental: .natural)
            }
        }

        return nil
    }
}

/// Renders an individual black piano key surface.
private struct PianoBlackKeyView: View {
    let height: CGFloat
    let tint: Color
    let strokeColor: Color
    let isHighlighted: Bool
    let isPressed: Bool
    let pulseID: Int
    let pulseTint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        shape
            .fill(tint)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(
                shape
                    .stroke(strokeColor, lineWidth: 1)
            )
            .overlay(
                KeyPressPulseView(
                    trigger: pulseID,
                    tint: pulseTint,
                    cornerRadius: 6,
                    expansionAmount: 3
                )
            )
            .overlay(
                KeyboardHighlightGlow(isActive: isHighlighted, cornerRadius: 6)
            )
            .shadow(color: .black.opacity(isPressed ? 0.08 : 0.22), radius: isPressed ? 2 : 8, y: isPressed ? 1 : 5)
            .scaleEffect(x: isPressed ? 0.97 : 1, y: isPressed ? 0.985 : 1, anchor: .top)
            .offset(y: isPressed ? 2 : 0)
            .animation(.spring(response: 0.36, dampingFraction: 0.8), value: isPressed)
            .animation(.easeOutCubic(duration: 0.18), value: isHighlighted)
    }
}

/// Renders an individual white piano key surface.
private struct PianoKeyView: View {
    let title: String
    let foreground: Color
    let tint: Color
    let height: CGFloat
    let isHighlighted: Bool
    let isPressed: Bool
    let pulseID: Int
    let pulseTint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        Text(title)
            .font(.headline.bold())
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .bottom)
            .padding(.bottom, 10)
            .background {
                GlassBackgroundView(
                    tint: tint,
                    cornerRadius: 10,
                    isInteractive: false
                )
                .overlay(
                    shape
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                )
            }
            .overlay(
                KeyPressPulseView(
                    trigger: pulseID,
                    tint: pulseTint,
                    cornerRadius: 10,
                    expansionAmount: 3
                )
            )
            .overlay(
                KeyboardHighlightGlow(isActive: isHighlighted, cornerRadius: 10)
            )
            .shadow(color: .black.opacity(isPressed ? 0.04 : 0.14), radius: isPressed ? 1 : 5, y: isPressed ? 1 : 3)
            .scaleEffect(x: isPressed ? 0.975 : 1, y: isPressed ? 0.985 : 1, anchor: .top)
            .offset(y: isPressed ? 2 : 0)
            .foregroundStyle(foreground)
            .animation(.spring(response: 0.36, dampingFraction: 0.8), value: isPressed)
            .animation(.easeOutCubic(duration: 0.18), value: isHighlighted)
    }
}

/// Keeps a highlighted piano key softly visible without reusing tap feedback motion.
private struct KeyboardHighlightGlow: View {
    let isActive: Bool
    let cornerRadius: CGFloat

    @State private var scale: CGFloat = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Theme.selectedControlTint.opacity(isActive ? 0.42 : 0), lineWidth: 3)
            .padding(-3)
            .blur(radius: 4)
            .scaleEffect(scale)
            .task(id: isActive) {
                guard isActive else {
                    scale = 1.0
                    return
                }

                scale = Theme.highlightGlowScaleRange.lowerBound
                withAnimation(.easeOutCubic(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale = Theme.highlightGlowScaleRange.upperBound
                }
            }
    }
}

/// Draws a one-shot active-tint wave when a piano key tap begins.
struct KeyPressPulseView: View {
    let trigger: Int
    var tint = Theme.selectedControlTint
    let cornerRadius: CGFloat
    let expansionAmount: CGFloat
    var includesInnerPulse = false
    var allowsMotion = true
    var restingGlowOpacity = 0.0

    @State private var isExpanded = false
    @State private var lastTrigger = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if includesInnerPulse {
                shape
                    .stroke(tint.opacity(max(restingGlowOpacity, isExpanded ? 0.26 : 0)), lineWidth: 17)
                    .padding(isExpanded ? -expansionAmount / 2 : 0)
                    .blur(radius: isExpanded ? 8 : 0)
            } else {
                shape
                    .stroke(tint.opacity(isExpanded ? 0.42 : 0), lineWidth: 3)
                    .padding(isExpanded ? -expansionAmount : 0)
                    .blur(radius: isExpanded ? 4 : 0)
            }
        }
        .onChange(of: trigger) { _, newValue in
            guard newValue > lastTrigger else {
                lastTrigger = newValue
                return
            }

            lastTrigger = newValue

            guard allowsMotion else {
                isExpanded = false
                return
            }

            isExpanded = false

            withAnimation(.easeOutCubic(duration: 0.22)) {
                isExpanded = true
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOutCubic(duration: 0.18)) {
                    isExpanded = false
                }
            }
        }
    }
}
