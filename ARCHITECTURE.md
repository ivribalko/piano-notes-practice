# Architecture

## Layout

- `PianoNotesPractice/App`: SwiftUI entry point, tab shell, and `AppRootView` composition.
- `PianoNotesPractice/Core/DesignSystem`: Shared presentation primitives.
- `PianoNotesPractice/Domain/Music`: Typed music values and Cue generation.
- `PianoNotesPractice/Features`: Practice, Progress, Settings, and Tutorial UI.
- `PianoNotesPractice/Services`: Audio, MIDI, persistence, and platform integrations.
- `PianoNotesPractice/Debug`: Debug-only diagnostics and overlays.
- `PianoNotesPractice/Assets.xcassets`: Images, colors, and app icons.
- `StoreAssets/Scripts`: Deterministic Store asset tooling kept with its inputs and outputs.
- `secrets`: Ignored signing configuration and Store source/deliverable assets.

## Runtime Flow

`PianoNotesPracticeApp` presents `AppRootView`, which owns the long-lived `PracticeSession` and tab navigation. The session coordinates:

- `QuizSession` for generated sequences, answer position, and response timing.
- `PracticeSettings` for typed Cue choices backed by established `AppStorage` keys.
- `TutorialFlow` for Tutorial progression and prompt acknowledgements.
- `CelebrationCoordinator` for temporary celebration text, highlights, and melodies.
- `NoteSoundPlayer` and `MIDIInputManager` for platform audio and hardware input.

Practice controls report intent upward through state and callbacks. The active `QuizNote` flows to `StaffPracticePanel` and `StaffView`; allowed `NoteAnswer` values flow to `NoteKeyboardView`. On-screen taps and MIDI note-on events share the same guess path. USB MIDI may replace the on-screen keyboard while connected.

`NoteSoundPlayer` schedules future prompt notes with cancellable tasks. Replays and mode changes may cancel notes that have not started, while active prompt notes, keyboard effects, and celebration melodies finish through their completion callbacks.

## Boundaries

- Domain rules stay in `Domain/Music`; persistence compatibility stays in `Services/Persistence`.
- Feature views own only small SwiftUI presentation state; `PracticeSession` owns session state and service lifetime.
- AVFoundation code stays in `NoteSoundPlayer`; CoreMIDI discovery and parsing stay in `MIDIInputManager`.
- Logging categories stay in `AppDiagnostics.swift`; log collection remains an external, opt-in workflow documented in `AGENTS.md`.
- Store composition maps raw captures, panorama slices, and headlines in `StoreAssets/Scripts/compose_store_screenshots.swift`.
- Signing and build configuration remain in Xcode and ignored `secrets/Signing.xcconfig`.
