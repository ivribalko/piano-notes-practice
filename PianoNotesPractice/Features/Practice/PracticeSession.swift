import Foundation
import Observation

/// Owns the long-lived services and domain state used by a Practice session.
@Observable
@MainActor
final class PracticeSession {
    let audio = NoteSoundPlayer()
    let midi = MIDIInputManager()
    let quiz = QuizSession()
    let settings = PracticeSettings()
    let tutorials = TutorialFlow()
    let celebrations = CelebrationCoordinator()

    init() {}
}
