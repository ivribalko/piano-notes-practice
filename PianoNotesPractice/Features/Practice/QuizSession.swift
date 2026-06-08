import Foundation
import Observation

/// Holds the transient sequence and response-timing state for one Practice quiz.
@Observable
@MainActor
final class QuizSession {
    var promptSequence: [QuizNote] = []
    var currentGuessIndex = 0
    var hasFailedCurrentSequence = false
    var promptResponseTimeStartedAt: Date?
    var accumulatedPromptResponseTime: TimeInterval = 0

    /// Resets state that must not survive a newly generated Cue sequence.
    func resetForNewPrompt(at date: Date = .now) {
        currentGuessIndex = 0
        hasFailedCurrentSequence = false
        promptResponseTimeStartedAt = date
        accumulatedPromptResponseTime = 0
    }
}
