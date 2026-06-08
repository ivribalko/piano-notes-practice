import Foundation

/// Identifies one generated note for persisted adaptive learning stats.
struct AdaptiveNoteKey: Hashable, Codable, Identifiable, Sendable {
    let letter: String
    let accidental: Accidental
    let clef: Clef
    let octave: Int

    var id: String {
        "\(clef.rawValue)-\(octave)-\(noteLabel)"
    }

    var noteLabel: String {
        letter + accidental.symbol
    }
}

/// Stores the user's persisted learning state for one note.
struct AdaptiveNoteStats: Codable, Sendable {
    private static let quickAnswersForLearned = 3

    var quickCorrectAnswers = 0

    var learnedPercent: Int {
        let progress = Double(min(quickCorrectAnswers, Self.quickAnswersForLearned)) / Double(Self.quickAnswersForLearned)
        return Int((progress * 100).rounded())
    }

    mutating func record(
        responseTime: TimeInterval,
        quickThreshold: TimeInterval
    ) {
        guard responseTime < quickThreshold else { return }
        quickCorrectAnswers += 1
    }

    init(quickCorrectAnswers: Int = 0) {
        self.quickCorrectAnswers = quickCorrectAnswers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quickCorrectAnswers = try container.decodeIfPresent(Int.self, forKey: .quickCorrectAnswers) ?? 0
    }
}

/// Encodes one adaptive note stats entry for local persistence.
struct AdaptiveNoteStatsSnapshot: Codable, Sendable {
    let key: AdaptiveNoteKey
    let stats: AdaptiveNoteStats
}

/// Presents persisted learning stats alongside their note identity.
struct LearnedNoteStatRow: Identifiable, Sendable {
    let key: AdaptiveNoteKey
    let stats: AdaptiveNoteStats

    var id: String {
        key.id
    }
}

/// Describes the outcome of recording a guess in adaptive note stats.
struct AdaptiveGuessRecordResult: Sendable {
    let didCompleteOctave: Bool
    let completedOctaveClef: Clef
    let completedOctave: Int
}

/// Loads, persists, sorts, and updates adaptive learning progress.
struct AdaptiveLearningStore {
    private static let statsStorageKey = "adaptiveNoteStats"

    private init() { }

    static func key(for note: QuizNote) -> AdaptiveNoteKey {
        AdaptiveNoteKey(
            letter: note.letter,
            accidental: note.accidental,
            clef: note.clef,
            octave: note.octave
        )
    }

    static func loadStats() -> [AdaptiveNoteKey: AdaptiveNoteStats] {
        guard let data = UserDefaults.standard.data(forKey: statsStorageKey) else {
            AppLog.learning.info("No adaptive learning stats found")
            return [:]
        }
        guard let snapshots = try? JSONDecoder().decode([AdaptiveNoteStatsSnapshot].self, from: data) else {
            AppLog.learning.error("Adaptive learning stats failed to decode; clearing saved stats")
            UserDefaults.standard.removeObject(forKey: statsStorageKey)
            return [:]
        }

        var restoredStats: [AdaptiveNoteKey: AdaptiveNoteStats] = [:]
        for snapshot in snapshots {
            guard restoredStats[snapshot.key] == nil else {
                AppLog.learning.error("Adaptive learning stats contained duplicate keys; clearing saved stats")
                UserDefaults.standard.removeObject(forKey: statsStorageKey)
                return [:]
            }

            restoredStats[snapshot.key] = snapshot.stats
        }

        AppLog.learning.info("Loaded adaptive learning stats; row count \(restoredStats.count, privacy: .public)")
        return restoredStats
    }

    static func persist(_ stats: [AdaptiveNoteKey: AdaptiveNoteStats]) {
        let snapshots = stats.map { key, stats in
            AdaptiveNoteStatsSnapshot(key: key, stats: stats)
        }

        guard let data = try? JSONEncoder().encode(snapshots) else {
            AppLog.learning.error("Adaptive learning stats failed to encode")
            return
        }
        UserDefaults.standard.set(data, forKey: statsStorageKey)
        AppLog.learning.info("Persisted adaptive learning stats; row count \(stats.count, privacy: .public)")
    }

    static func learnedRows(from stats: [AdaptiveNoteKey: AdaptiveNoteStats]) -> [LearnedNoteStatRow] {
        stats.map { key, stats in
            LearnedNoteStatRow(key: key, stats: stats)
        }
        .sorted {
            if $0.key.clef != $1.key.clef {
                return clefSortOrder($0.key.clef) < clefSortOrder($1.key.clef)
            }

            if $0.key.octave != $1.key.octave {
                return $0.key.octave < $1.key.octave
            }

            let leftPitch = NotePitch.semitone(letter: $0.key.letter, accidental: $0.key.accidental)
            let rightPitch = NotePitch.semitone(letter: $1.key.letter, accidental: $1.key.accidental)
            if leftPitch != rightPitch {
                return leftPitch < rightPitch
            }

            return $0.key.noteLabel < $1.key.noteLabel
        }
    }

    static func zeroProgressRows(
        clef: Clef,
        octave: Int,
        answerOptions: [NoteAnswer]
    ) -> [LearnedNoteStatRow] {
        answerOptions.map { answer in
            LearnedNoteStatRow(
                key: AdaptiveNoteKey(
                    letter: answer.letter,
                    accidental: answer.accidental,
                    clef: clef,
                    octave: octave
                ),
                stats: AdaptiveNoteStats()
            )
        }
    }

    static func learnedPercent(
        clef: Clef,
        octave: Int,
        answerOptions: [NoteAnswer],
        stats: [AdaptiveNoteKey: AdaptiveNoteStats]
    ) -> Int {
        let rows = answerOptions.map { answer in
            stats[
                AdaptiveNoteKey(
                    letter: answer.letter,
                    accidental: answer.accidental,
                    clef: clef,
                    octave: octave
                ),
                default: AdaptiveNoteStats()
            ]
        }

        guard !rows.isEmpty else { return 0 }
        let total = rows.reduce(0) { $0 + $1.learnedPercent }
        return Int((Double(total) / Double(rows.count)).rounded())
    }

    static func recordGuess(
        for note: QuizNote,
        responseTime: TimeInterval,
        quickThreshold: TimeInterval,
        answerOptions: [NoteAnswer],
        stats: inout [AdaptiveNoteKey: AdaptiveNoteStats]
    ) -> AdaptiveGuessRecordResult? {
        let key = key(for: note)
        let previousOctaveLearnedPercent = learnedPercent(
            clef: note.clef,
            octave: note.octave,
            answerOptions: answerOptions,
            stats: stats
        )
        var noteStats = stats[key, default: AdaptiveNoteStats()]
        noteStats.record(
            responseTime: responseTime,
            quickThreshold: quickThreshold
        )
        stats[key] = noteStats
        persist(stats)

        let updatedOctaveLearnedPercent = learnedPercent(
            clef: note.clef,
            octave: note.octave,
            answerOptions: answerOptions,
            stats: stats
        )
        guard previousOctaveLearnedPercent < 100, updatedOctaveLearnedPercent == 100 else {
            return nil
        }

        AppLog.learning.info(
            "Completed adaptive learning octave; clef \(note.clef.rawValue, privacy: .public), octave \(note.octave, privacy: .public)"
        )

        return AdaptiveGuessRecordResult(
            didCompleteOctave: true,
            completedOctaveClef: note.clef,
            completedOctave: note.octave
        )
    }

    private static func clefSortOrder(_ clef: Clef) -> Int {
        switch clef {
        case .treble:
            return 0
        case .bass:
            return 1
        }
    }
}
