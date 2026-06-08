import Observation

/// Coordinates transient celebration presentation and keyboard highlight state.
@Observable
@MainActor
final class CelebrationCoordinator {
    var reasonText: String?
    var highlightedAnswers = Set<NoteAnswer>()
    var keyboardMelodyNumber: Int?

    /// Clears presentation-only state without interrupting already playing audio.
    func clearPresentation() {
        reasonText = nil
        highlightedAnswers.removeAll()
        keyboardMelodyNumber = nil
    }
}
