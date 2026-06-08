import Foundation

/// Represents a musical staff clef used to display quiz notes.
enum Clef: String, CaseIterable, Codable, Sendable {
    case treble = "Treble"
    case bass = "Bass"

    var symbol: String {
        switch self {
        case .treble: return "𝄞"
        case .bass: return "𝄢"
        }
    }
}

/// Limits note generation to a specific clef selection.
enum ClefMode: String, CaseIterable, Sendable {
    case both = "Both"
    case treble = "Treble"
    case bass = "Bass"

    var allowedClefs: [Clef] {
        switch self {
        case .both: return [.treble, .bass]
        case .treble: return [.treble]
        case .bass: return [.bass]
        }
    }

    func includes(_ clef: Clef) -> Bool {
        allowedClefs.contains(clef)
    }

    func toggled(_ clef: Clef) -> ClefMode? {
        let current = Set(allowedClefs)
        var updated = current

        if current.contains(clef) {
            updated.remove(clef)
        } else {
            updated.insert(clef)
        }

        switch updated {
        case [.treble, .bass]:
            return .both
        case [.treble]:
            return .treble
        case [.bass]:
            return .bass
        default:
            return nil
        }
    }
}

/// Describes the accidental applied to a note spelling.
enum Accidental: String, Codable, Sendable {
    case natural
    case sharp
    case flat

    var symbol: String {
        switch self {
        case .natural: return ""
        case .sharp: return "♯"
        case .flat: return "♭"
        }
    }

    var semitoneOffset: Int {
        switch self {
        case .natural: return 0
        case .sharp: return 1
        case .flat: return -1
        }
    }
}

/// Represents a selectable answer shown on the practice keyboard.
struct NoteAnswer: Equatable, Hashable, Identifiable, Sendable {
    let letter: String
    let accidental: Accidental

    var id: String { label }
    var label: String {
        letter + accidental.symbol
    }

}

/// Stores the generated note that drives the current quiz prompt.
struct QuizNote: Equatable, Sendable {
    let letter: String
    let octave: Int
    let clef: Clef
    let staffStep: Int
    let accidental: Accidental

    var answer: NoteAnswer {
        NoteAnswer(letter: letter, accidental: accidental)
    }
}
