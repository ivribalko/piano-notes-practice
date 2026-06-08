import Foundation
import Observation

/// Represents the typed, persistent-choice values used to generate Practice Cues.
@Observable
@MainActor
final class PracticeSettings {
    var selectedClef: ClefMode = .treble
    var includeSharps = false
    var includeFlats = false
    var isStaffVisible = true
    var isToneEnabled = false
    var isKeyboardEffectEnabled = true
    var isNoteBounceEffectEnabled = true
    var isHelperGlowEnabled = true
    var isTempoMeterEnabled = false
    var usesNativeDarkPracticeColors = false
    var selectedOctaves: Set<Int> = [4]
    var sequenceLength = 1

    /// Normalizes a saved setting set without changing established persistence keys.
    func normalize() {
        selectedOctaves = NoteQuizGenerator.selectedOctaves(
            from: selectedOctaves.sorted().map(String.init).joined(separator: ",")
        )
        sequenceLength = NoteQuizGenerator.sequenceLength(from: sequenceLength)
    }
}
