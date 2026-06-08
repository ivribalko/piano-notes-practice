import Combine
import SwiftUI

/// Identifies the currently active one-time guided practice sequence.
enum TutorialKind {
    case firstOctave
    case accidentals
}

/// Identifies the Middle C tutorial step shown before the Bass Clef Octave 3 overview.
enum MiddleCTutorialStep: Int {
    case ledgerLine
    case bassC4
    case trebleC4
    case connection
    case handRange
}

/// Identifies the reference-note tutorial step shown before the Treble Clef Octave 5 overview.
enum ReferenceNoteTutorialStep: Int {
    case trebleG
    case bassF
    case referencePoints
    case positionReading
}

/// Describes the Practice context and presentation style for a Tutorial.
extension TutorialProgressID {
    var requiredPractice: (clef: Clef, octave: Int)? {
        switch self {
        case .firstOctave:
            return (.treble, 4)
        case .middleC:
            return (.bass, 3)
        case .referenceNotes:
            return (.treble, 5)
        case .accidentals:
            return nil
        }
    }

    var noteTutorialKind: TutorialKind? {
        switch self {
        case .firstOctave:
            return .firstOctave
        case .accidentals:
            return .accidentals
        case .middleC, .referenceNotes:
            return nil
        }
    }

    var isGuidedTutorial: Bool {
        self == .middleC || self == .referenceNotes
    }

    var promptIDPrefix: String {
        switch self {
        case .firstOctave:
            return "first-octave"
        case .middleC:
            return "middle-c"
        case .referenceNotes:
            return "reference-note"
        case .accidentals:
            return "accidentals"
        }
    }
}

/// Identifies a Clef and Octave overview that should be introduced before practice starts.
struct OctaveIntroduction: Equatable, Identifiable {
    let clef: Clef
    let octave: Int

    var id: String {
        "\(clef.rawValue)-\(octave)"
    }

    var promptText: String {
        "\(clef.rawValue) Clef, Octave \(octave)."
    }
}

/// Computes tutorial overlay text, prompts, highlights, and labels for the practice flow.
struct NoteTutorial {
    /// The delay before a Tutorial prompt reveals its Continue control.
    static let promptContinueDelay: TimeInterval = 1

    static let pressHighlightedWhiteKeyTutorialText = "Next, tap the highlighted White Piano Key."
    static let whiteKeyNaturalNoteTutorialText = "A White Piano Key plays a Natural Note."
    static let octaveWhiteKeysTutorialText = "The seven Natural Note names make up one Octave and repeat in every Octave."
    static let staffPositionTutorialText = "A Staff position is one line or one space."
    static let whiteKeysMoveTutorialText = "Adjacent Natural Notes move one Staff position at a time."
    static let welcomeTutorialText = "Welcome to Piano Notes Practice."
    static let welcomeCelebrationText = "Welcome to Piano Notes Practice!"
    static let sheetMusicStaffIntroText = "This is the Sheet Music Staff with Note Cues."
    static let pianoKeyboardIntroText = "This is the Piano Keyboard with Note Names."
    static let burstMeterHelperText = "The Tempo Meter fills with quick correct answers."
    static let firstOctaveNextStepsHelperText = "Enable Sharps and Flats in Settings, or choose another Octave in Progress."
    static let ledgerLineDefinitionText = "A ledger line is a short line that extends the Staff."
    static let middleCBassC4Text = "In Bass Clef, C4 sits on the first ledger line above the Staff."
    static let middleCTrebleC4Text = "In Treble Clef, C4 sits on the first ledger line below the Staff."
    static let middleCConnectionText = "C4 is Middle C. It sits between the Bass and Treble Staves."
    static let middleCHandRangeText = "Together, the Bass and Treble Staves form one continuous range of Notes."
    static let referenceNoteTrebleGText = "Treble Clef is also called the G Clef because it wraps around the G line."
    static let referenceNoteBassFText = "Bass Clef is also called the F Clef because its dots surround the F line."
    static let referenceNoteReferencePointsText = "Use these and other Notes as reference points to read Notes faster."
    static let referenceNotePositionReadingText = "Once you know a reference Note, nearby Notes are easier to read by position."

    private init() { }

    static func notes(
        kind: TutorialKind?,
        letters: [String],
        sharpLetters: [String],
        flatLetters: [String],
        makeNote: (String, Accidental) -> QuizNote
    ) -> [QuizNote] {
        switch kind {
        case .firstOctave:
            return letters.map { makeNote($0, .natural) }
        case .accidentals:
            let sharpNotes = sharpLetters.map { makeNote($0, .sharp) }
            let flatNotes = flatLetters.reversed().map { makeNote($0, .flat) }
            return sharpNotes + flatNotes
        case nil:
            return []
        }
    }

    static func currentNote(
        from notes: [QuizNote],
        index: Int
    ) -> QuizNote? {
        guard !notes.isEmpty else { return nil }
        let clampedIndex = min(max(index, 0), notes.count - 1)
        return notes[clampedIndex]
    }

    static func highlightedAnswers(
        celebrationHighlightedAnswers: Set<NoteAnswer>,
        isActive: Bool,
        expectedNote: QuizNote?,
        answerOptions: [NoteAnswer]
    ) -> Set<NoteAnswer> {
        if !celebrationHighlightedAnswers.isEmpty {
            return celebrationHighlightedAnswers
        }

        guard isActive, let expectedNote else { return [] }
        return Set(
            answerOptions.filter {
                semitone(for: $0) == semitone(letter: expectedNote.letter, accidental: expectedNote.accidental)
            }
        )
    }

    static func keyboardHighlightedAnswers(
        staffHelperText: String?,
        answerOptions: [NoteAnswer],
        fallbackHighlights: Set<NoteAnswer>
    ) -> Set<NoteAnswer> {
        if staffHelperText == whiteKeysMoveTutorialText {
            return Set(
                answerOptions.filter {
                    $0.accidental == .natural && ["C", "D"].contains($0.letter)
                }
            )
        }

        if staffHelperText == octaveWhiteKeysTutorialText {
            return Set(answerOptions.filter { $0.accidental == .natural })
        }

        if staffHelperText == pianoKeyboardIntroText {
            return Set(answerOptions.filter { $0.accidental == .natural })
        }

        return staffHelperText == nil ? fallbackHighlights : []
    }

    static func keyboardHelperText(
        kind: TutorialKind?,
        noteIndex: Int,
        isShowingCompletion: Bool,
        sharpLetterCount: Int,
        acknowledgedPromptIDs: Set<String>
    ) -> String? {
        guard kind != nil else { return nil }
        guard !isShowingCompletion else { return nil }

        switch kind {
        case .firstOctave:
            switch noteIndex {
            case 0:
                return pressHighlightedWhiteKeyTutorialText
            case 1:
                return whiteKeyNaturalNoteTutorialText
            case 2:
                let staffPositionPromptID = promptID(
                    kind: kind,
                    text: staffPositionTutorialText
                )
                return acknowledgedPromptIDs.contains(staffPositionPromptID)
                    ? whiteKeysMoveTutorialText
                    : staffPositionTutorialText
            case 3:
                return whiteKeysMoveTutorialText
            default:
                return octaveWhiteKeysTutorialText
            }
        case .accidentals:
            switch noteIndex {
            case 0..<sharpLetterCount:
                return "A Sharp raises the pitch of a Note without changing its Staff position."
            default:
                return "A Flat lowers the pitch of a Note without changing its Staff position."
            }
        case nil:
            return nil
        }
    }

    static func staffHelperText(
        kind: TutorialKind?,
        keyboardHelperText: String?,
        acknowledgedPromptIDs: Set<String>,
        showsFirstOctaveNextSteps: Bool,
        firstOctaveNextStepsText: String? = nil,
        showsBurstMeter: Bool
    ) -> String? {
        if shouldShowPianoKeyboardIntro(
            kind: kind,
            acknowledgedPromptIDs: acknowledgedPromptIDs
        ) {
            return pianoKeyboardIntroText
        }

        if let candidateText = staffCandidateText(
            kind: kind,
            keyboardHelperText: keyboardHelperText,
            acknowledgedPromptIDs: acknowledgedPromptIDs
        ) {
            let promptID = promptID(kind: kind, text: candidateText)
            guard !acknowledgedPromptIDs.contains(promptID) else { return nil }

            return candidateText
        }

        if showsFirstOctaveNextSteps {
            return firstOctaveNextStepsText ?? firstOctaveNextStepsHelperText
        }

        guard showsBurstMeter else { return nil }

        return burstMeterHelperText
    }

    static func shouldShowPianoKeyboardIntro(
        kind: TutorialKind?,
        acknowledgedPromptIDs: Set<String>
    ) -> Bool {
        guard kind == .firstOctave else { return false }
        guard hasAcknowledgedWelcome(kind: kind, acknowledgedPromptIDs: acknowledgedPromptIDs) else { return false }

        return !hasAcknowledgedPianoKeyboardIntro(kind: kind, acknowledgedPromptIDs: acknowledgedPromptIDs)
    }

    static func shouldShowSheetMusicStaffIntro(
        kind: TutorialKind?,
        acknowledgedPromptIDs: Set<String>
    ) -> Bool {
        guard kind == .firstOctave else { return false }
        guard hasAcknowledgedWelcome(kind: kind, acknowledgedPromptIDs: acknowledgedPromptIDs) else { return false }
        guard hasAcknowledgedPianoKeyboardIntro(kind: kind, acknowledgedPromptIDs: acknowledgedPromptIDs) else { return false }

        return !hasAcknowledgedSheetMusicStaffIntro(kind: kind, acknowledgedPromptIDs: acknowledgedPromptIDs)
    }

    static func promptID(kind: TutorialKind?, text: String) -> String {
        let tutorialPrefix = kind.map(idPrefix(for:)) ?? "tutorial"

        return "\(tutorialPrefix)-\(text)"
    }

    static func celebrationReasonText(kind: TutorialKind?) -> String {
        switch kind {
        case .firstOctave:
            return "First Octave complete—ready to Practice!"
        case .accidentals:
            return "Sharps and Flats Tutorial complete!"
        case nil:
            return "Tutorial complete!"
        }
    }

    static func idPrefix(for kind: TutorialKind) -> String {
        switch kind {
        case .firstOctave:
            return "first-octave"
        case .accidentals:
            return "accidentals"
        }
    }

    private static func staffCandidateText(
        kind: TutorialKind?,
        keyboardHelperText: String?,
        acknowledgedPromptIDs: Set<String>
    ) -> String? {
        guard kind != nil else { return nil }
        _ = acknowledgedPromptIDs

        guard keyboardHelperText != pressHighlightedWhiteKeyTutorialText else { return nil }
        guard keyboardHelperText != staffPositionTutorialText else { return nil }
        guard keyboardHelperText != octaveWhiteKeysTutorialText else { return nil }

        return keyboardHelperText
    }

    private static func hasAcknowledgedWelcome(
        kind: TutorialKind?,
        acknowledgedPromptIDs: Set<String>
    ) -> Bool {
        acknowledgedPromptIDs.contains(promptID(kind: kind, text: welcomeTutorialText))
    }

    private static func hasAcknowledgedSheetMusicStaffIntro(
        kind: TutorialKind?,
        acknowledgedPromptIDs: Set<String>
    ) -> Bool {
        acknowledgedPromptIDs.contains(promptID(kind: kind, text: sheetMusicStaffIntroText))
    }

    private static func hasAcknowledgedPianoKeyboardIntro(
        kind: TutorialKind?,
        acknowledgedPromptIDs: Set<String>
    ) -> Bool {
        acknowledgedPromptIDs.contains(promptID(kind: kind, text: pianoKeyboardIntroText))
    }

    private static func semitone(for answer: NoteAnswer) -> Int {
        NotePitch.semitone(for: answer)
    }

    private static func semitone(letter: String, accidental: Accidental) -> Int {
        NotePitch.semitone(letter: letter, accidental: accidental)
    }
}

/// Shows the time-draining meter that controls the next completed-sequence burst size.
struct MilestoneBurstProgressView: View {
    let progress: Double
    let fillColor: Color
    let isHighlighted: Bool

    @State private var highlightPulseID = 0


    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        progressBar
        .overlay(
            KeyPressPulseView(
                trigger: isHighlighted ? highlightPulseID : 0,
                cornerRadius: 8,
                expansionAmount: 3
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo Meter")
        .accessibilityValue("\(Int((clampedProgress * 100).rounded())) percent")
        .onAppear(perform: pulseIfHighlighted)
        .onChange(of: isHighlighted) { _, _ in
            pulseIfHighlighted()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1_200))
                guard !Task.isCancelled else { return }
                pulseIfHighlighted()
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * clampedProgress
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

            ZStack(alignment: .leading) {
                shape
                    .fill(trackColor)

                Rectangle()
                    .fill(fillColor)
                    .frame(width: fillWidth)

                HStack(spacing: 0) {
                    ForEach(1..<4, id: \.self) { _ in
                        Spacer()

                        Rectangle()
                            .fill(dividerColor)
                            .frame(width: 1)
                    }

                    Spacer(minLength: 0)
                }
            }
            .clipShape(shape)
        }
        .frame(height: 18)
    }

    private var trackColor: Color {
        Color(red: 0.78, green: 0.86, blue: 0.89)
    }

    private var dividerColor: Color {
        Color.white.opacity(0.76)
    }

    private func pulseIfHighlighted() {
        guard isHighlighted else { return }
        highlightPulseID += 1
    }
}

/// Renders full-background blue and purple aurora curtains whose visibility follows Tempo Meter progress.
struct PracticeAuroraEffectView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double

    var body: some View {
        let auroraOpacity = min(max((progress - 0.25) / 0.75, 0), 1)

        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate / 14
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                let ambientGlowRect = CGRect(
                    x: -size.width * 0.25,
                    y: -size.height * 0.25,
                    width: size.width * 1.5,
                    height: size.height * 1.5
                )

                context.fill(
                    Path(ellipseIn: ambientGlowRect),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(
                                color: Color(red: 0.18, green: 0.56, blue: 0.94).opacity(0.34),
                                location: 0
                            ),
                            .init(
                                color: Color(red: 0.38, green: 0.18, blue: 0.82).opacity(0.30),
                                location: 0.48
                            ),
                            .init(
                                color: Color(red: 0.10, green: 0.72, blue: 0.80).opacity(0.20),
                                location: 0.78
                            ),
                            .init(color: .clear, location: 1)
                        ]),
                        center: center,
                        startRadius: 0,
                        endRadius: hypot(size.width, size.height) * 0.72
                    )
                )

                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 22))

                    for ribbon in AuroraRibbon.all {
                        let path = ribbon.path(
                            in: size,
                            phase: phase
                        )
                        let gradient = Gradient(colors: ribbon.colors.map { color in
                            color.opacity(ribbon.opacity)
                        })

                        layer.fill(
                            path,
                            with: .linearGradient(
                                gradient,
                                startPoint: CGPoint(x: size.width * ribbon.gradientStart, y: 0),
                                endPoint: CGPoint(x: size.width * ribbon.gradientEnd, y: size.height)
                            )
                        )
                    }
                }
            }
        }
        .opacity(auroraOpacity)
        .blendMode(.plusLighter)
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Defines the shape, color, and motion of one aurora curtain.
private struct AuroraRibbon {
    let verticalOffset: CGFloat
    let amplitude: CGFloat
    let thickness: CGFloat
    let frequency: CGFloat
    let speed: Double
    let phaseOffset: Double
    let gradientStart: CGFloat
    let gradientEnd: CGFloat
    let opacity: Double
    let colors: [Color]

    func path(in size: CGSize, phase: Double) -> Path {
        let sampleCount = max(Int(size.width / 18), 24)
        let currentPhase = (phase * speed + phaseOffset) * 2 * Double.pi
        var upperPoints: [CGPoint] = []
        var lowerPoints: [CGPoint] = []

        for index in 0...sampleCount {
            let normalizedX = CGFloat(index) / CGFloat(sampleCount)
            let x = normalizedX * size.width
            let wave = sin(Double(normalizedX * frequency) * 2 * Double.pi + currentPhase)
            let secondaryWave = sin(Double(normalizedX * (frequency * 0.55)) * 2 * Double.pi - currentPhase * 0.7)
            let upperY = size.height * (
                verticalOffset
                    + amplitude * CGFloat(wave)
                    + amplitude * 0.34 * CGFloat(secondaryWave)
            )
            let curtainDepth = size.height * thickness * (
                0.82 + 0.18 * CGFloat(sin(Double(normalizedX) * 4 * Double.pi - currentPhase))
            )

            upperPoints.append(CGPoint(x: x, y: upperY))
            lowerPoints.append(CGPoint(x: x, y: upperY + curtainDepth))
        }

        var path = Path()
        guard let firstUpperPoint = upperPoints.first else { return path }

        path.move(to: firstUpperPoint)
        upperPoints.dropFirst().forEach { path.addLine(to: $0) }
        lowerPoints.reversed().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    static let all: [AuroraRibbon] = [
        AuroraRibbon(
            verticalOffset: -0.04,
            amplitude: 0.065,
            thickness: 0.48,
            frequency: 1.25,
            speed: 0.72,
            phaseOffset: 0.08,
            gradientStart: 0.05,
            gradientEnd: 0.92,
            opacity: 0.50,
            colors: [
                Color(red: 0.14, green: 0.78, blue: 0.98),
                Color(red: 0.24, green: 0.42, blue: 1.00),
                Color(red: 0.62, green: 0.20, blue: 0.94)
            ]
        ),
        AuroraRibbon(
            verticalOffset: 0.26,
            amplitude: 0.085,
            thickness: 0.50,
            frequency: 1.65,
            speed: -0.46,
            phaseOffset: 0.42,
            gradientStart: 0.95,
            gradientEnd: 0.12,
            opacity: 0.42,
            colors: [
                Color(red: 0.48, green: 0.18, blue: 0.96),
                Color(red: 0.18, green: 0.48, blue: 1.00),
                Color(red: 0.16, green: 0.90, blue: 0.88)
            ]
        ),
        AuroraRibbon(
            verticalOffset: 0.55,
            amplitude: 0.055,
            thickness: 0.50,
            frequency: 2.05,
            speed: 0.34,
            phaseOffset: 0.71,
            gradientStart: 0.18,
            gradientEnd: 0.82,
            opacity: 0.34,
            colors: [
                Color(red: 0.22, green: 0.58, blue: 1.00),
                Color(red: 0.54, green: 0.22, blue: 0.98),
                Color(red: 0.24, green: 0.88, blue: 0.92)
            ]
        )
    ]
}

/// Renders short upward confetti bursts from celebration prompts.
struct CelebrationConfettiBurstView: View {
    let triggerKey: String?

    @State private var bursts: [CelebrationConfettiBurst] = []

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                ZStack {
                    ForEach(bursts) { burst in
                        let elapsed = timeline.date.timeIntervalSince(burst.startDate)

                        ForEach(burst.particles) { particle in
                            let position = particle.position(
                                elapsed: elapsed,
                                in: proxy.size
                            )

                            particle.shape
                                .fill(particle.color)
                                .frame(width: particle.width, height: particle.height)
                                .rotationEffect(.degrees(particle.rotation(elapsed: elapsed)))
                                .rotation3DEffect(
                                    .degrees(particle.tumble(elapsed: elapsed)),
                                    axis: (x: 1, y: 0.35, z: 0)
                                )
                                .opacity(particle.opacity(elapsed: elapsed))
                                .position(position)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            emitBurst(for: triggerKey)
        }
        .onChange(of: triggerKey) { _, _ in
            emitBurst(for: triggerKey)
        }
    }

    private func emitBurst(for triggerKey: String?) {
        guard triggerKey != nil else { return }

        let nextBurst = CelebrationConfettiBurst.randomBurst()
        bursts.append(nextBurst)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(CelebrationConfettiBurst.maximumDuration))
            guard !Task.isCancelled else { return }
            bursts.removeAll { $0.id == nextBurst.id }
        }
    }
}

/// Describes one independently expiring confetti burst.
private struct CelebrationConfettiBurst: Identifiable {
    let id = UUID()
    let startDate = Date()
    let particles: [CelebrationConfettiParticle]

    static let maximumDuration: TimeInterval = 3.6

    static func randomBurst() -> CelebrationConfettiBurst {
        CelebrationConfettiBurst(
            particles: CelebrationConfettiParticle.randomParticles(count: 84)
        )
    }
}

/// Describes one confetti particle launched upward before falling.
private struct CelebrationConfettiParticle: Identifiable {
    let id = UUID()
    let edgeAnchor: CGPoint
    let xVelocity: CGFloat
    let yVelocity: CGFloat
    let gravity: CGFloat
    let flutterAmplitude: CGFloat
    let flutterFrequency: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotationStart: Double
    let rotationSpeed: Double
    let tumbleStart: Double
    let tumbleSpeed: Double
    let duration: TimeInterval
    let delay: TimeInterval
    let color: Color
    let shape: AnyShape

    private static let colors: [Color] = [
        Color(red: 0.98, green: 0.32, blue: 0.32),
        Color(red: 1.00, green: 0.74, blue: 0.18),
        Color(red: 0.20, green: 0.74, blue: 0.46),
        Color(red: 0.18, green: 0.58, blue: 0.96),
        Color(red: 0.78, green: 0.36, blue: 0.92),
        Color(red: 1.00, green: 0.48, blue: 0.70)
    ]

    static func randomParticles(count: Int) -> [CelebrationConfettiParticle] {
        (0..<count).map { _ in
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 130...390)
            let upwardLift = CGFloat.random(in: 45...130)

            return CelebrationConfettiParticle(
                edgeAnchor: randomEdgeAnchor(),
                xVelocity: cos(angle) * speed,
                yVelocity: sin(angle) * speed - upwardLift,
                gravity: CGFloat.random(in: 300...430),
                flutterAmplitude: CGFloat.random(in: 0.8...4.0),
                flutterFrequency: CGFloat.random(in: 1.2...2.8),
                width: CGFloat.random(in: 4...10),
                height: CGFloat.random(in: 9...22),
                rotationStart: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -260...260),
                tumbleStart: Double.random(in: -70...70),
                tumbleSpeed: Double.random(in: -460...460),
                duration: TimeInterval.random(in: 1.9...2.9),
                delay: TimeInterval.random(in: 0...0.18),
                color: colors.randomElement() ?? Theme.selectedControlTint,
                shape: randomShape()
            )
        }
    }

    func position(elapsed: TimeInterval, in size: CGSize) -> CGPoint {
        let localElapsed = max(elapsed - delay, 0)
        let seconds = CGFloat(localElapsed)
        let origin = CGPoint(
            x: size.width * edgeAnchor.x,
            y: size.height * edgeAnchor.y
        )
        let flutterPhase = CGFloat(localElapsed) * flutterFrequency
        let flutter = sin(flutterPhase * .pi * 2) * flutterAmplitude
        let x = origin.x + xVelocity * seconds + flutter
        let y = origin.y
            + yVelocity * seconds
            + 0.5 * gravity * seconds * seconds

        return CGPoint(x: x, y: y)
    }

    func rotation(elapsed: TimeInterval) -> Double {
        let localElapsed = max(elapsed - delay, 0)
        let flutter = sin(localElapsed * 5.0) * 4
        return rotationStart + rotationSpeed * localElapsed + flutter
    }

    func tumble(elapsed: TimeInterval) -> Double {
        let localElapsed = max(elapsed - delay, 0)
        return tumbleStart + tumbleSpeed * localElapsed
    }

    func opacity(elapsed: TimeInterval) -> Double {
        guard elapsed >= delay else { return 0 }

        let progress = progress(elapsed: elapsed)
        guard progress > 0.64 else { return 1 }
        return max(0, 1 - (progress - 0.64) / 0.36)
    }

    private func progress(elapsed: TimeInterval) -> CGFloat {
        let localElapsed = max(elapsed - delay, 0)
        let particleProgress = min(localElapsed / duration, 1)
        return CGFloat(particleProgress)
    }

    private static func randomEdgeAnchor() -> CGPoint {
        switch Int.random(in: 0...3) {
        case 0:
            CGPoint(x: CGFloat.random(in: 0.08...0.92), y: CGFloat.random(in: 0.02...0.14))
        case 1:
            CGPoint(x: CGFloat.random(in: 0.08...0.92), y: CGFloat.random(in: 0.86...0.98))
        case 2:
            CGPoint(x: CGFloat.random(in: 0.02...0.14), y: CGFloat.random(in: 0.16...0.84))
        default:
            CGPoint(x: CGFloat.random(in: 0.86...0.98), y: CGFloat.random(in: 0.16...0.84))
        }
    }

    private static func randomShape() -> AnyShape {
        switch Int.random(in: 0...4) {
        case 0:
            AnyShape(Capsule())
        case 1:
            AnyShape(Rectangle())
        default:
            AnyShape(RoundedRectangle(cornerRadius: CGFloat.random(in: 0.8...2.2)))
        }
    }
}
