import SwiftUI

/// Draws the current quiz sequence on a five-line staff.
struct StaffView: View {
    @State private var previousNotes: [QuizNote] = []
    @State private var exitingNotes: [QuizNote] = []
    @State private var exitRemovalTask: Task<Void, Never>?
    @State private var isHidingCurrentNotes = false
    @State private var currentNoteGlowPulseID = 0


    let notes: [QuizNote]
    let currentGuessIndex: Int
    let isNoteBounceEffectEnabled: Bool
    let isHelperGlowEnabled: Bool
    let usesNativeDarkPracticeColors: Bool
    let appearanceTrigger: Int
    let disappearanceTrigger: Int

    var body: some View {
        GeometryReader { proxy in
            let visibleNotes = isHidingCurrentNotes ? [] : notes
            let size = proxy.size
            let lineGap = min(size.height * 0.09, 18)
            let noteWidth = lineGap * 1.55
            let noteHeight = lineGap * 0.82
            let margin = lineGap * 1.4
            let clef = staffClef(for: visibleNotes)
            let noteXPositions = noteXPositions(
                for: visibleNotes,
                clef: clef,
                in: size,
                lineGap: lineGap,
                noteWidth: noteWidth
            )
            let rawNoteYs = visibleNotes.map { rawNoteY(for: $0, size: size, lineGap: lineGap) }
            let lowestRawNoteY = rawNoteYs.max() ?? size.height * 0.5
            let highestRawNoteY = rawNoteYs.min() ?? size.height * 0.5
            let centerShift: CGFloat = {
                if highestRawNoteY < margin {
                    return margin - highestRawNoteY
                } else if lowestRawNoteY > size.height - margin {
                    return size.height - margin - lowestRawNoteY
                } else {
                    return .zero
                }
            }()
            let centerY = size.height * 0.5 + centerShift

            ZStack {
                staffLines(size: size, centerY: centerY, lineGap: lineGap)

                let clefLayout = clefLayout(for: clef, size: size, centerY: centerY, lineGap: lineGap)
                Text(clef.symbol)
                    .font(.system(size: clefLayout.fontSize, weight: .regular, design: .serif))
                    .foregroundStyle(staffColor)
                    .position(x: clefLayout.x, y: clefLayout.y)
                    .accessibilityHidden(true)

                noteMarks(
                    for: exitingNotes,
                    size: size,
                    lineGap: lineGap,
                    noteWidth: noteWidth,
                    noteHeight: noteHeight,
                    phase: .exiting
                )

                ForEach(Array(visibleNotes.enumerated()), id: \.offset) { index, note in
                    let noteX = noteXPositions[index]
                    let noteY = noteY(for: note, centerY: centerY, lineGap: lineGap)
                    let isCurrentNote = isHelperGlowEnabled && visibleNotes.count > 1 && index == currentGuessIndex

                    StaffNoteMarkView(
                        note: note,
                        noteX: noteX,
                        noteY: noteY,
                        centerY: centerY,
                        lineGap: lineGap,
                        noteWidth: noteWidth,
                        noteHeight: noteHeight,
                        staffColor: staffColor,
                        isCurrentNote: isCurrentNote,
                        glowPulseID: currentNoteGlowPulseID,
                        isNoteBounceEffectEnabled: isNoteBounceEffectEnabled,
                        appearanceTrigger: appearanceTrigger,
                        phase: .entering
                    )
                }
            }
            .drawingGroup()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: visibleNotes))
            .onAppear {
                previousNotes = notes
                pulseCurrentNoteGlow()
            }
            .onChange(of: currentGuessIndex) { _, _ in
                pulseCurrentNoteGlow()
            }
            .onChange(of: notes) { _, _ in
                pulseCurrentNoteGlow()
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(950))
                    guard !Task.isCancelled else { return }
                    pulseCurrentNoteGlow()
                }
            }
            .onChange(of: appearanceTrigger) { _, _ in
                isHidingCurrentNotes = false
                updateExitingNotes()
            }
            .onChange(of: disappearanceTrigger) { _, _ in
                startImmediateExit()
            }
        }
    }

    private var staffColor: Color {
        usesNativeDarkPracticeColors ? Theme.nativeNotationColor : Theme.notationColor
    }

    private func staffClef(for visibleNotes: [QuizNote]) -> Clef {
        visibleNotes.first?.clef
            ?? exitingNotes.first?.clef
            ?? previousNotes.first?.clef
            ?? notes.first?.clef
            ?? .treble
    }

    private func rawNoteY(for note: QuizNote, size: CGSize, lineGap: CGFloat) -> CGFloat {
        size.height * 0.5 + CGFloat(note.staffStep - 4) * lineGap / 2
    }

    private func noteY(for note: QuizNote, centerY: CGFloat, lineGap: CGFloat) -> CGFloat {
        centerY + CGFloat(note.staffStep - 4) * lineGap / 2
    }

    private func staffLineLeadingX(in size: CGSize) -> CGFloat {
        .zero
    }

    private func staffLineTrailingX(in size: CGSize) -> CGFloat {
        size.width
    }

    private func noteXPositions(
        for notes: [QuizNote],
        clef: Clef,
        in size: CGSize,
        lineGap: CGFloat,
        noteWidth: CGFloat
    ) -> [CGFloat] {
        guard !notes.isEmpty else { return [] }

        let clefLayout = clefLayout(for: clef, size: size, centerY: size.height * 0.5, lineGap: lineGap)
        let clefRightEdge = clefLayout.x + clefLayout.fontSize * clef.noteLaneClearanceFactor
        let markHalfWidth = max(noteWidth * 3.4, 58) / 2
        let startX = min(max(clefRightEdge, size.width * 0.28), size.width * 0.42)
        let endX = staffLineTrailingX(in: size) - markHalfWidth

        if notes.count == 1 {
            return [(startX + endX) / 2]
        }

        let maximumStep = (endX - startX) / CGFloat(notes.count - 1)
        let preferredStep = max(noteWidth * 2.25, 34)
        let step = min(preferredStep, maximumStep)
        let sequenceWidth = step * CGFloat(notes.count - 1)
        let centeredStartX = ((startX + endX) / 2) - (sequenceWidth / 2)
        let compactStartX = min(max(centeredStartX, startX), endX - sequenceWidth)

        return notes.indices.map { compactStartX + CGFloat($0) * step }
    }

    private func staffLines(size: CGSize, centerY: CGFloat, lineGap: CGFloat) -> some View {
        Path { path in
            for line in 0..<5 {
                let y = centerY + CGFloat(line - 2) * lineGap
                path.move(to: CGPoint(x: staffLineLeadingX(in: size), y: y))
                path.addLine(to: CGPoint(x: staffLineTrailingX(in: size), y: y))
            }
        }
        .stroke(staffColor, lineWidth: 2)
    }

    @ViewBuilder
    private func noteMarks(
        for notes: [QuizNote],
        size: CGSize,
        lineGap: CGFloat,
        noteWidth: CGFloat,
        noteHeight: CGFloat,
        phase: StaffNoteAnimationPhase
    ) -> some View {
        let noteXPositions = noteXPositions(
            for: notes,
            clef: staffClef(for: notes),
            in: size,
            lineGap: lineGap,
            noteWidth: noteWidth
        )
        let rawNoteYs = notes.map { rawNoteY(for: $0, size: size, lineGap: lineGap) }
        let lowestRawNoteY = rawNoteYs.max() ?? size.height * 0.5
        let highestRawNoteY = rawNoteYs.min() ?? size.height * 0.5
        let margin = lineGap * 1.4
        let centerShift: CGFloat = {
            if highestRawNoteY < margin {
                return margin - highestRawNoteY
            } else if lowestRawNoteY > size.height - margin {
                return size.height - margin - lowestRawNoteY
            } else {
                return .zero
            }
        }()
        let centerY = size.height * 0.5 + centerShift

        ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
            let noteX = noteXPositions[index]
            let noteY = noteY(for: note, centerY: centerY, lineGap: lineGap)

            StaffNoteMarkView(
                note: note,
                noteX: noteX,
                noteY: noteY,
                centerY: centerY,
                lineGap: lineGap,
                noteWidth: noteWidth,
                noteHeight: noteHeight,
                staffColor: staffColor,
                isCurrentNote: false,
                glowPulseID: 0,
                isNoteBounceEffectEnabled: isNoteBounceEffectEnabled,
                appearanceTrigger: appearanceTrigger,
                phase: phase
            )
        }
    }

    private func clefLayout(for clef: Clef, size: CGSize, centerY: CGFloat, lineGap: CGFloat) -> (fontSize: CGFloat, x: CGFloat, y: CGFloat) {
        switch clef {
        case .treble:
            return (
                fontSize: lineGap * 9,
                x: size.width * 0.10,
                y: centerY - lineGap * 0.4
            )
        case .bass:
            return (
                fontSize: lineGap * 5,
                x: size.width * 0.10,
                y: centerY - lineGap * 0.5
            )
        }
    } 

    private func accessibilityLabel(for notes: [QuizNote]) -> String {
        let labels = notes.map { "\($0.answer.label) Octave \($0.octave)" }.joined(separator: ", ")
        return "\(staffClef(for: notes).rawValue) Clef Cue: \(labels)"
    }

    private func pulseCurrentNoteGlow() {
        guard notes.indices.contains(currentGuessIndex), !isHidingCurrentNotes else { return }
        currentNoteGlowPulseID += 1
    }

    private func updateExitingNotes() {
        exitRemovalTask?.cancel()

        guard isNoteBounceEffectEnabled, !previousNotes.isEmpty, previousNotes != notes else {
            exitingNotes = []
            previousNotes = notes
            return
        }

        exitingNotes = previousNotes
        previousNotes = notes

        let removalTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            exitingNotes = []
        }

        exitRemovalTask = removalTask
    }

    private func startImmediateExit() {
        exitRemovalTask?.cancel()

        guard isNoteBounceEffectEnabled, !notes.isEmpty else {
            isHidingCurrentNotes = false
            exitingNotes = []
            previousNotes = notes
            return
        }

        isHidingCurrentNotes = true
        exitingNotes = notes
        previousNotes = []

        let removalTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            exitingNotes = []
        }

        exitRemovalTask = removalTask
    }
}

/// Describes whether a staff note mark is appearing or leaving the staff.
private enum StaffNoteAnimationPhase {
    case entering
    case exiting
}

private extension Clef {
    var noteLaneClearanceFactor: CGFloat {
        switch self {
        case .treble: return 0.36
        case .bass: return 0.26
        }
    }
}

/// Renders one staff note, including accidentals and ledger lines, as one animated unit.
private struct StaffNoteMarkView: View {
    let note: QuizNote
    let noteX: CGFloat
    let noteY: CGFloat
    let centerY: CGFloat
    let lineGap: CGFloat
    let noteWidth: CGFloat
    let noteHeight: CGFloat
    let staffColor: Color
    let isCurrentNote: Bool
    let glowPulseID: Int
    let isNoteBounceEffectEnabled: Bool
    let appearanceTrigger: Int
    let phase: StaffNoteAnimationPhase

    @State private var noteheadScale = 1.0
    @State private var markOpacity = 1.0
    @State private var accidentalOpacity = 1.0
    @State private var accidentalMotionOffset: CGFloat = 0

    var body: some View {
        ZStack {
            if phase == .entering {
                ledgerLines
            }

            animatedNoteMark
                .compositingGroup()
        }
        .frame(width: markWidth, height: markHeight)
        .position(x: noteX, y: noteY)
        .onAppear(perform: runPhaseAnimationIfNeeded)
        .onChange(of: appearanceTrigger) { _, _ in
            runPhaseAnimationIfNeeded()
        }
    }

    private var animatedNoteMark: some View {
        ZStack {
            stemmedNotehead
                .scaleEffect(noteheadScale)
                .opacity(markOpacity)

            if note.accidental != .natural {
                Text(note.accidental.symbol)
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .foregroundStyle(staffColor)
                    .position(
                        x: markCenterX - noteWidth * 1.15,
                        y: markCenterY + accidentalYOffset
                    )
                    .offset(y: accidentalMotionOffset)
                    .opacity(accidentalOpacity)
                    .accessibilityHidden(true)
            }
        }
    }

    private var stemmedNotehead: some View {
        ZStack {
            noteSprite
                .frame(width: markWidth, height: markHeight)
                .position(x: markCenterX, y: markCenterY)
                .shadow(
                    color: Theme.selectedControlTint.opacity(isCurrentNote ? 0.32 : 0),
                    radius: isCurrentNote ? 6 : 0
                )
                .shadow(color: staffColor.opacity(0.15), radius: 3, y: 2)

            KeyPressPulseView(
                trigger: isCurrentNote ? glowPulseID : 0,
                cornerRadius: noteHeight / 2,
                expansionAmount: 2
            )
            .frame(width: noteWidth, height: noteHeight)
            .opacity(0.38)
            .rotationEffect(.degrees(-18))
            .position(x: markCenterX, y: markCenterY)
        }
    }

    private var noteSprite: some View {
        Canvas { context, _ in
            let stemX = markCenterX + stemDirection.xOffset(for: noteWidth)
            var stemPath = Path()
            stemPath.move(to: CGPoint(x: stemX, y: markCenterY + stemDirection.yOffset(for: 2)))
            stemPath.addLine(to: CGPoint(x: stemX, y: markCenterY + stemDirection.yOffset(for: stemLength)))
            context.stroke(
                stemPath,
                with: .color(staffColor),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .butt)
            )

            let noteheadRect = CGRect(
                x: markCenterX - noteWidth / 2,
                y: markCenterY - noteHeight / 2,
                width: noteWidth,
                height: noteHeight
            )
            let noteheadTransform = CGAffineTransform(translationX: markCenterX, y: markCenterY)
                .rotated(by: -.pi / 10)
                .translatedBy(x: -markCenterX, y: -markCenterY)
            let noteheadPath = Path(ellipseIn: noteheadRect).applying(noteheadTransform)
            context.fill(noteheadPath, with: .color(staffColor))
        }
    }

    private var ledgerLines: some View {
        Path { path in
            for offset in ledgerLineOffsets {
                let y = markCenterY + offset
                path.move(to: CGPoint(x: markCenterX - 20, y: y))
                path.addLine(to: CGPoint(x: markCenterX + 20, y: y))
            }
        }
        .stroke(staffColor, lineWidth: 2)
    }

    private var ledgerLineOffsets: [CGFloat] {
        let lowestLineY = centerY + 2 * lineGap
        let highestLineY = centerY - 2 * lineGap
        var offsets: [CGFloat] = []

        if noteY > lowestLineY + lineGap * 0.45 {
            var y = lowestLineY + lineGap
            while y <= noteY + 1 {
                offsets.append(y - noteY)
                y += lineGap
            }
        }

        if noteY < highestLineY - lineGap * 0.45 {
            var y = highestLineY - lineGap
            while y >= noteY - 1 {
                offsets.append(y - noteY)
                y -= lineGap
            }
        }

        return offsets
    }

    private var markWidth: CGFloat {
        max(noteWidth * 3.4, 58)
    }

    private var markHeight: CGFloat {
        let ledgerExtent = ledgerLineOffsets.map { abs($0) }.max() ?? 0
        return max(noteHeight * 4.0, stemLength * 2 + lineGap, ledgerExtent * 2 + lineGap * 2)
    }

    private var markCenterX: CGFloat {
        markWidth / 2
    }

    private var markCenterY: CGFloat {
        markHeight / 2
    }

    private var accidentalYOffset: CGFloat {
        switch note.accidental {
        case .natural, .sharp: return 0
        case .flat: return -lineGap * 0.22
        }
    }

    private var stemDirection: StaffNoteStemDirection {
        note.staffStep > 4 ? .up : .down
    }

    private var stemLength: CGFloat {
        lineGap * 3.5
    }

    private func runPhaseAnimationIfNeeded() {
        guard isNoteBounceEffectEnabled else {
            noteheadScale = 1.0
            markOpacity = 1.0
            accidentalOpacity = 1.0
            accidentalMotionOffset = 0
            return
        }

        switch phase {
        case .entering:
            fadeIn()
        case .exiting:
            fadeOut()
        }
    }

    private func fadeIn() {
        noteheadScale = 0.7
        markOpacity = 0
        accidentalOpacity = 0
        accidentalMotionOffset = -lineGap * 0.42

        withAnimation(.easeOutCubic(duration: 0.12)) {
            markOpacity = 1.0
        }

        withAnimation(.easeOutCubic(duration: 0.12)) {
            accidentalOpacity = 1.0
            accidentalMotionOffset = 0
        }

        withAnimation(.interpolatingSpring(stiffness: 360, damping: 16)) {
            noteheadScale = 1.0
        }
    }

    private func fadeOut() {
        noteheadScale = 1.0
        markOpacity = 1.0
        accidentalOpacity = 1.0
        accidentalMotionOffset = 0

        withAnimation(.easeOutCubic(duration: 0.18)) {
            markOpacity = 0
        }

        withAnimation(.easeOutCubic(duration: 0.18)) {
            accidentalOpacity = 0
            accidentalMotionOffset = -lineGap * 0.42
        }

        withAnimation(.easeOutCubic(duration: 0.18)) {
            noteheadScale = 1.32
        }
    }
}

/// Defines which side and vertical direction a staff note stem uses.
private enum StaffNoteStemDirection {
    case up
    case down

    func xOffset(for noteWidth: CGFloat) -> CGFloat {
        switch self {
        case .up: return noteWidth * 0.44
        case .down: return -noteWidth * 0.44
        }
    }

    func yOffset(for stemLength: CGFloat) -> CGFloat {
        switch self {
        case .up: return -stemLength
        case .down: return stemLength
        }
    }
}
