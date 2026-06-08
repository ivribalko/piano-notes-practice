import Observation

/// Identifies a Tutorial and its shared in-memory progress.
enum TutorialProgressID: CaseIterable, Hashable {
    case firstOctave
    case middleC
    case referenceNotes
    case accidentals
}

/// Tracks the in-memory progression and prompt acknowledgements for Tutorials.
@Observable
@MainActor
final class TutorialFlow {
    var activeTutorialID: TutorialProgressID?
    var noteIndex = 0
    var isShowingCompletion = false
    var acknowledgedStaffPromptIDs = Set<String>()

    /// Clears all ephemeral state shared by every Tutorial.
    func reset() {
        noteIndex = 0
        isShowingCompletion = false
        acknowledgedStaffPromptIDs.removeAll()
    }
}
