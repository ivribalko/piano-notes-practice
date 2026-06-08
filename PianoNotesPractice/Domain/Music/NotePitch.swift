import Foundation

/// Provides pitch math shared by note generation, MIDI input, scoring, and tutorials.
struct NotePitch: Sendable {
    static let naturalLetters = ["C", "D", "E", "F", "G", "A", "B"]
    static let sharpLetters = ["C", "D", "F", "G", "A"]
    static let flatLetters = ["D", "E", "G", "A", "B"]

    private init() { }

    static func semitone(for answer: NoteAnswer) -> Int {
        semitone(letter: answer.letter, accidental: answer.accidental)
    }

    static func semitone(letter: String, accidental: Accidental) -> Int {
        let naturalSemitone: [String: Int] = [
            "C": 0,
            "D": 2,
            "E": 4,
            "F": 5,
            "G": 7,
            "A": 9,
            "B": 11
        ]
        let rawValue = (naturalSemitone[letter] ?? 0) + accidental.semitoneOffset
        return (rawValue + 12) % 12
    }

    static func staffStep(letter: String, octave: Int, clef: Clef) -> Int {
        let letterIndex = naturalLetters.firstIndex(of: letter) ?? 0
        let noteIndex = octave * naturalLetters.count + letterIndex

        switch clef {
        case .treble:
            let trebleTopLineF5 = 5 * naturalLetters.count + 3
            return trebleTopLineF5 - noteIndex
        case .bass:
            let bassTopLineA3 = 3 * naturalLetters.count + 5
            return bassTopLineA3 - noteIndex
        }
    }

    static func midiNoteNumber(for note: QuizNote) -> UInt8? {
        let rawValue = ((note.octave + 1) * 12) + semitone(letter: note.letter, accidental: note.accidental)
        guard rawValue >= Int(UInt8.min), rawValue <= Int(UInt8.max) else {
            return nil
        }

        return UInt8(rawValue)
    }

    static func displayKeyboardAnswer(
        for note: QuizNote,
        answerOptions: [NoteAnswer]
    ) -> NoteAnswer {
        let targetSemitone = semitone(letter: note.letter, accidental: note.accidental)
        let naturalAnswer = NoteAnswer(letter: note.letter, accidental: .natural)

        if note.accidental == .natural {
            return answerOptions.first { $0 == naturalAnswer } ?? naturalAnswer
        }

        if let sharpAnswer = answerOptions.first(where: { $0.accidental == .sharp && semitone(for: $0) == targetSemitone }) {
            return sharpAnswer
        }

        if let exactAnswer = answerOptions.first(where: { $0.letter == note.letter && $0.accidental == note.accidental }) {
            return exactAnswer
        }

        return note.answer
    }
}

/// Generates quiz notes and prompt sequences from the active practice settings.
struct NoteQuizGenerator: Sendable {
    let selectedClef: ClefMode
    let activeOctaves: Set<Int>
    let answerOptions: [NoteAnswer]
    let adaptiveStats: [AdaptiveNoteKey: AdaptiveNoteStats]

    static func answerOptions(
        includeSharps: Bool,
        includeFlats: Bool
    ) -> [NoteAnswer] {
        var answers = NotePitch.naturalLetters.map {
            NoteAnswer(letter: $0, accidental: .natural)
        }

        if includeSharps {
            answers += NotePitch.sharpLetters.map {
                NoteAnswer(letter: $0, accidental: .sharp)
            }
        }

        if includeFlats {
            answers += NotePitch.flatLetters.map {
                NoteAnswer(letter: $0, accidental: .flat)
            }
        }

        return answers
    }

    static func selectedOctaves(from storage: String) -> Set<Int> {
        let allowedOctaves = Set([2, 3, 4, 5, 6])
        let restoredOctaves = Set(
            storage
                .split(separator: ",")
                .compactMap { Int($0) }
                .filter { allowedOctaves.contains($0) }
        )

        return restoredOctaves.isEmpty ? [4] : restoredOctaves
    }

    static func sequenceLength(from value: Int) -> Int {
        min(max(value, 1), 7)
    }

    static func normalizedClefMode(for clefMode: ClefMode, sequenceLength: Int) -> ClefMode {
        guard sequenceLength > 1, clefMode == .both else { return clefMode }
        return .treble
    }

    func quizNote(answer: NoteAnswer, clef: Clef) -> QuizNote {
        let octave = activeOctaves.randomElement() ?? 4

        return quizNote(answer: answer, clef: clef, octave: octave)
    }

    func quizNote(answer: NoteAnswer, clef: Clef, octave: Int) -> QuizNote {
        QuizNote(
            letter: answer.letter,
            octave: octave,
            clef: clef,
            staffStep: NotePitch.staffStep(letter: answer.letter, octave: octave, clef: clef),
            accidental: answer.accidental
        )
    }

    func weightedRandomNote(
        excluding excludedKeys: Set<AdaptiveNoteKey>,
        avoidingAdjacentTo adjacentNote: QuizNote? = nil,
        alsoAvoidingAudiblePitchOf extraNotes: [QuizNote] = []
    ) -> QuizNote {
        let candidates = adaptiveNoteCandidates()
        let availableCandidates = candidates.filter { !excludedKeys.contains(AdaptiveLearningStore.key(for: $0)) }
        let nonRepeatingAvailableCandidates = availableCandidates.filter {
            !isSameAudiblePitch($0, adjacentNote)
                && !isSameAudiblePitch($0, anyOf: extraNotes)
        }
        let nonRepeatingCandidates = candidates.filter {
            !isSameAudiblePitch($0, adjacentNote)
                && !isSameAudiblePitch($0, anyOf: extraNotes)
        }
        let weightedCandidates: [QuizNote]

        if !nonRepeatingAvailableCandidates.isEmpty {
            weightedCandidates = nonRepeatingAvailableCandidates
        } else if !nonRepeatingCandidates.isEmpty {
            weightedCandidates = nonRepeatingCandidates
        } else if !availableCandidates.isEmpty {
            weightedCandidates = availableCandidates
        } else {
            weightedCandidates = candidates
        }

        guard !weightedCandidates.isEmpty else {
            return quizNote(
                answer: answerOptions.first ?? NoteAnswer(letter: "C", accidental: .natural),
                clef: selectedClef.allowedClefs.first ?? .treble,
                octave: activeOctaves.sorted().first ?? 4
            )
        }

        let weights = weightedCandidates.map { adaptiveWeight(for: $0) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            return weightedCandidates.randomElement() ?? weightedCandidates[0]
        }

        var threshold = Double.random(in: 0..<totalWeight)
        for (index, note) in weightedCandidates.enumerated() {
            threshold -= weights[index]
            if threshold <= 0 {
                return note
            }
        }

        return weightedCandidates.last ?? weightedCandidates[0]
    }

    func makePromptSequence(
        for finalNote: QuizNote,
        sequenceLength: Int,
        avoidingAdjacentTo adjacentNote: QuizNote? = nil
    ) -> [QuizNote] {
        guard sequenceLength > 1 else {
            guard !isSameAudiblePitch(finalNote, adjacentNote) else {
                return [
                    weightedRandomNote(
                        excluding: Set(adjacentNote.map { [AdaptiveLearningStore.key(for: $0)] } ?? []),
                        avoidingAdjacentTo: adjacentNote
                    )
                ]
            }

            return [finalNote]
        }

        var sequence: [QuizNote] = []
        var excludedKeys: Set<AdaptiveNoteKey> = [AdaptiveLearningStore.key(for: finalNote)]
        var previousNote = adjacentNote

        for neighborIndex in 0..<(sequenceLength - 1) {
            let isLastNeighbor = neighborIndex == sequenceLength - 2
            let note = weightedRandomNote(
                excluding: excludedKeys,
                avoidingAdjacentTo: previousNote,
                alsoAvoidingAudiblePitchOf: isLastNeighbor ? [finalNote] : []
            )
            sequence.append(note)
            excludedKeys.insert(AdaptiveLearningStore.key(for: note))
            previousNote = note
        }

        sequence.append(finalNote)
        return sequence
    }

    private func adaptiveNoteCandidates() -> [QuizNote] {
        selectedClef.allowedClefs.flatMap { clef in
            activeOctaves.sorted().flatMap { octave in
                answerOptions.map { answer in
                    quizNote(answer: answer, clef: clef, octave: octave)
                }
            }
        }
    }

    private func adaptiveWeight(for note: QuizNote) -> Double {
        let stats = adaptiveStats[AdaptiveLearningStore.key(for: note)] ?? AdaptiveNoteStats()
        return 1.0 + Double(100 - stats.learnedPercent) / 25.0
    }

    private func isSameAudiblePitch(_ note: QuizNote, _ other: QuizNote?) -> Bool {
        guard let other else { return false }

        return note.octave == other.octave
            && NotePitch.semitone(letter: note.letter, accidental: note.accidental)
                == NotePitch.semitone(letter: other.letter, accidental: other.accidental)
    }

    private func isSameAudiblePitch(_ note: QuizNote, anyOf otherNotes: [QuizNote]) -> Bool {
        otherNotes.contains { isSameAudiblePitch(note, $0) }
    }
}
