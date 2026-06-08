import SwiftUI

/// Hosts the full practice configuration on a separate settings screen.
struct PracticeSettingsView: View {
    let selectedClef: ClefMode
    let includeSharps: Bool
    let includeFlats: Bool
    let sequenceLength: Int
    let availableOctaves: [Int]
    let selectedOctaves: Set<Int>
    let isStaffVisible: Bool
    let isToneEnabled: Bool
    let isPreparingAudioCache: Bool
    let isKeyboardEffectEnabled: Bool
    let isNoteBounceEffectEnabled: Bool
    let isHelperGlowEnabled: Bool
    let isTempoMeterEnabled: Bool
    let usesNativeDarkPracticeColors: Bool
    let isMIDIDeviceConnected: Bool
    let onSelectClefMode: (ClefMode) -> Void
    let onToggleAccidentals: () -> Void
    let onSelectSequenceLength: (Int) -> Void
    let onToggleOctave: (Int) -> Void
    let onToggleStaff: () -> Void
    let onToggleTone: () -> Void
    let onToggleKeyboardEffect: () -> Void
    let onToggleNoteBounceEffect: () -> Void
    let onToggleHelperGlow: () -> Void
    let onToggleTempoMeter: () -> Void
    let onToggleNativeDarkPracticeColors: () -> Void
    let onResetTutorials: () -> Void

    var body: some View {
        Form {
            PracticeTogglesView(
                selectedClef: selectedClef,
                includeSharps: includeSharps,
                includeFlats: includeFlats,
                sequenceLength: sequenceLength,
                availableOctaves: availableOctaves,
                selectedOctaves: selectedOctaves,
                isStaffVisible: isStaffVisible,
                isToneEnabled: isToneEnabled,
                isPreparingAudioCache: isPreparingAudioCache,
                isKeyboardEffectEnabled: isKeyboardEffectEnabled,
                isNoteBounceEffectEnabled: isNoteBounceEffectEnabled,
                isHelperGlowEnabled: isHelperGlowEnabled,
                isTempoMeterEnabled: isTempoMeterEnabled,
                usesNativeDarkPracticeColors: usesNativeDarkPracticeColors,
                onSelectClefMode: onSelectClefMode,
                onToggleAccidentals: onToggleAccidentals,
                onSelectSequenceLength: onSelectSequenceLength,
                onToggleOctave: onToggleOctave,
                onToggleStaff: onToggleStaff,
                onToggleTone: onToggleTone,
                onToggleKeyboardEffect: onToggleKeyboardEffect,
                onToggleNoteBounceEffect: onToggleNoteBounceEffect,
                onToggleHelperGlow: onToggleHelperGlow,
                onToggleTempoMeter: onToggleTempoMeter,
                onToggleNativeDarkPracticeColors: onToggleNativeDarkPracticeColors
            )

            InputModeSelectorView(
                isMIDIDeviceConnected: isMIDIDeviceConnected
            )

            TutorialSettingsView(onResetTutorials: onResetTutorials)
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(TabPageBackgroundView())
        .tint(Theme.selectedControlTint)
    }
}

/// Provides maintenance actions for one-time tutorial flows.
struct TutorialSettingsView: View {
    let onResetTutorials: () -> Void
    @State private var isResetConfirmationPresented = false

    var body: some View {
        Section {
            HStack {
                Button(role: .destructive) {
                    isResetConfirmationPresented = true
                } label: {
                    SettingsRowLabel(
                        title: "Reset Tutorials",
                        systemImage: "arrow.counterclockwise"
                    )
                }

                Spacer()

                SettingHelpButton(
                    title: "Reset Tutorials",
                    text: "Clears all Tutorial and helper progress so first-run guidance appears again."
                )
            }
        }
        .confirmationDialog("Are you sure?", isPresented: $isResetConfirmationPresented, titleVisibility: .visible) {
            Button("Reset Tutorials", role: .destructive, action: onResetTutorials)
            Button("Cancel", role: .cancel) { }
        }
    }
}

/// Lets the user choose how many notes are included in each Cue.
struct SequenceLengthSelectorView: View {
    let sequenceLength: Int
    let onSelectSequenceLength: (Int) -> Void

    private let availableCounts = Array(1...7)

    var body: some View {
        HStack {
            Stepper(value: sequenceLengthBinding, in: 1...7) {
                SettingsRowLabel(
                    title: "Cue Length: \(sequenceLength)",
                    systemImage: "arrow.left.and.right.text.vertical"
                )
            }

            SettingHelpButton(
                title: "Cue",
                text: "Sets how many Notes appear in each Cue. Longer Cues ask you to answer the Notes in order."
            )
        }
    }

    private var sequenceLengthBinding: Binding<Int> {
        Binding(
            get: { sequenceLength },
            set: { newValue in
                guard availableCounts.contains(newValue), newValue != sequenceLength else { return }
                onSelectSequenceLength(newValue)
            }
        )
    }
}

/// Groups note-reading options that shape each Practice Cue.
struct PracticeCueSettingsView: View {
    let selectedClef: ClefMode
    let includeSharps: Bool
    let includeFlats: Bool
    let sequenceLength: Int
    let availableOctaves: [Int]
    let selectedOctaves: Set<Int>
    let onSelectClefMode: (ClefMode) -> Void
    let onToggleAccidentals: () -> Void
    let onSelectSequenceLength: (Int) -> Void
    let onToggleOctave: (Int) -> Void

    var body: some View {
        Form {
            Section {
                HStack {
                    Toggle(isOn: accidentalBinding) {
                        SettingsRowLabel(
                            title: "Sharps and Flats",
                            systemImage: "arrow.up.and.down.text.horizontal"
                        )
                    }

                    SettingHelpButton(
                        title: "Sharps and Flats",
                        text: "Adds Sharp and Flat Notes to Cues. When off, Cues use Natural Notes only."
                    )
                }

                SequenceLengthSelectorView(
                    sequenceLength: sequenceLength,
                    onSelectSequenceLength: onSelectSequenceLength
                )
            }

            Section("Clefs") {
                ForEach(Clef.allCases, id: \.self) { clef in
                    GuardedSettingsToggle(
                        title: "\(clef.rawValue) Clef",
                        systemImage: selectedClef.includes(clef) ? "checkmark.circle.fill" : "circle",
                        isOn: selectedClef.includes(clef),
                        helpText: "\(clef.rawValue) Clef Notes can appear in Cues. At least one Clef must stay selected, and Cues longer than one Note use one Clef at a time.",
                        blockedHelpText: clefToggleBlockedHelpText(for: clef),
                        onToggle: { updateClefSelection(for: clef) }
                    )
                }
            }

            Section {
                ForEach(availableOctaves, id: \.self) { octave in
                    GuardedSettingsToggle(
                        title: "Octave \(octave)",
                        systemImage: selectedOctaves.contains(octave) ? "checkmark.circle.fill" : "circle",
                        isOn: selectedOctaves.contains(octave),
                        helpText: "Allows Notes from Octave \(octave) in Cues. At least one Octave must stay selected.",
                        blockedHelpText: octaveToggleBlockedHelpText(for: octave),
                        onToggle: { onToggleOctave(octave) }
                    )
                }
            } header: {
                Text("Octaves")
            } footer: {
                Text("Recommended: Octaves 3 and 4.")
            }
        }
        .navigationTitle("Practice Cue")
        .scrollContentBackground(.hidden)
        .background(TabPageBackgroundView())
        .tint(Theme.selectedControlTint)
    }

    private var accidentalBinding: Binding<Bool> {
        Binding(
            get: { includeSharps && includeFlats },
            set: { newValue in
                guard newValue != (includeSharps && includeFlats) else { return }
                onToggleAccidentals()
            }
        )
    }

    private func updateClefSelection(for clef: Clef) {
        let newValue = !selectedClef.includes(clef)

        if sequenceLength > 1, newValue {
            onSelectClefMode(clef == .treble ? .treble : .bass)
            return
        }

        guard let clefMode = selectedClef.toggled(clef) else { return }
        onSelectClefMode(clefMode)
    }

    private func isOnlySelectedClef(_ clef: Clef) -> Bool {
        selectedClef.allowedClefs == [clef]
    }

    private func clefToggleBlockedHelpText(for clef: Clef) -> String? {
        guard isOnlySelectedClef(clef) else { return nil }
        return "At least one Clef must stay selected."
    }

    private func octaveToggleBlockedHelpText(for octave: Int) -> String? {
        guard selectedOctaves == [octave] else { return nil }
        return "At least one Octave must stay selected."
    }
}

/// Toggles prompt and keyboard settings for practice.
struct PracticeTogglesView: View {
    let selectedClef: ClefMode
    let includeSharps: Bool
    let includeFlats: Bool
    let sequenceLength: Int
    let availableOctaves: [Int]
    let selectedOctaves: Set<Int>
    let isStaffVisible: Bool
    let isToneEnabled: Bool
    let isPreparingAudioCache: Bool
    let isKeyboardEffectEnabled: Bool
    let isNoteBounceEffectEnabled: Bool
    let isHelperGlowEnabled: Bool
    let isTempoMeterEnabled: Bool
    let usesNativeDarkPracticeColors: Bool
    let onSelectClefMode: (ClefMode) -> Void
    let onToggleAccidentals: () -> Void
    let onSelectSequenceLength: (Int) -> Void
    let onToggleOctave: (Int) -> Void
    let onToggleStaff: () -> Void
    let onToggleTone: () -> Void
    let onToggleKeyboardEffect: () -> Void
    let onToggleNoteBounceEffect: () -> Void
    let onToggleHelperGlow: () -> Void
    let onToggleTempoMeter: () -> Void
    let onToggleNativeDarkPracticeColors: () -> Void

    var body: some View {
        Section {
            GuardedSettingsToggle(
                title: "Cue Staff",
                systemImage: "eye",
                isOn: isStaffVisible,
                helpText: "Shows Staff notation for each Cue. At least one Cue Mode—Cue Staff or Cue Sounds—must stay enabled.",
                blockedHelpText: practiceModeToggleBlockedHelpText(for: .staff),
                onToggle: onToggleStaff
            )

            GuardedSettingsToggle(
                title: "Cue Sounds",
                systemImage: "ear",
                isOn: isToneEnabled,
                helpText: "Plays the Notes in each Cue during Practice. It is unavailable while sounds are getting ready, and at least one Cue Mode must stay enabled.",
                blockedHelpText: practiceModeToggleBlockedHelpText(for: .tone),
                onToggle: onToggleTone
            )

            GuardedSettingsToggle(
                title: "Keyboard Sounds",
                systemImage: "speaker.wave.2",
                isOn: isKeyboardEffectEnabled,
                helpText: "Plays a sound when you tap the piano keys. It is unavailable while sounds are getting ready.",
                blockedHelpText: keyboardEffectToggleBlockedHelpText,
                onToggle: onToggleKeyboardEffect
            )

            HStack {
                NavigationLink {
                    PracticeDisplaySettingsView(
                        isNoteBounceEffectEnabled: isNoteBounceEffectEnabled,
                        isHelperGlowEnabled: isHelperGlowEnabled,
                        isTempoMeterEnabled: isTempoMeterEnabled,
                        usesNativeDarkPracticeColors: usesNativeDarkPracticeColors,
                        onToggleNoteBounceEffect: onToggleNoteBounceEffect,
                        onToggleHelperGlow: onToggleHelperGlow,
                        onToggleTempoMeter: onToggleTempoMeter,
                        onToggleNativeDarkPracticeColors: onToggleNativeDarkPracticeColors
                    )
                } label: {
                    SettingsRowLabel(
                        title: "Practice Display",
                        systemImage: "slider.horizontal.3"
                    )
                }

                SettingHelpButton(
                    title: "Practice Display",
                    text: "Controls Helper Glow, Tempo Meter, Reduce Motion, and Darker Practice Mode settings."
                )
            }

            HStack {
                NavigationLink {
                    PracticeCueSettingsView(
                        selectedClef: selectedClef,
                        includeSharps: includeSharps,
                        includeFlats: includeFlats,
                        sequenceLength: sequenceLength,
                        availableOctaves: availableOctaves,
                        selectedOctaves: selectedOctaves,
                        onSelectClefMode: onSelectClefMode,
                        onToggleAccidentals: onToggleAccidentals,
                        onSelectSequenceLength: onSelectSequenceLength,
                        onToggleOctave: onToggleOctave
                    )
                } label: {
                    SettingsRowLabel(
                        title: "Practice Cue",
                        systemImage: "music.note.list"
                    )
                }

                SettingHelpButton(
                    title: "Practice Cue",
                    text: "Controls Clefs, Octaves, Sharps and Flats, and Cue Length."
                )
            }
        } footer: {
            if isPreparingAudioCache {
                Label("Sounds are getting ready...", systemImage: "hourglass")
            }
        }
    }

    private func isOnlyEnabledPracticeMode(_ practiceMode: PracticeMode) -> Bool {
        switch practiceMode {
        case .staff:
            return isStaffVisible && !isToneEnabled
        case .tone:
            return isToneEnabled && !isStaffVisible
        }
    }

    private func practiceModeToggleBlockedHelpText(for practiceMode: PracticeMode) -> String? {
        if practiceMode == .tone, isPreparingAudioCache {
            return "Cue Sounds are unavailable while sounds are getting ready."
        }

        guard isOnlyEnabledPracticeMode(practiceMode) else { return nil }
        return "At least one Cue Mode—Cue Staff or Cue Sounds—must stay enabled."
    }

    private var keyboardEffectToggleBlockedHelpText: String? {
        isPreparingAudioCache ? "Keyboard Sounds are unavailable while sounds are getting ready." : nil
    }
}

/// Presents secondary practice display and feedback settings.
struct PracticeDisplaySettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let isNoteBounceEffectEnabled: Bool
    let isHelperGlowEnabled: Bool
    let isTempoMeterEnabled: Bool
    let usesNativeDarkPracticeColors: Bool
    let onToggleNoteBounceEffect: () -> Void
    let onToggleHelperGlow: () -> Void
    let onToggleTempoMeter: () -> Void
    let onToggleNativeDarkPracticeColors: () -> Void

    var body: some View {
        Form {
            Section {
                HStack {
                    Toggle(isOn: helperGlowBinding) {
                        SettingsRowLabel(
                            title: "Helper Glow",
                            systemImage: "lightbulb"
                        )
                    }

                    SettingHelpButton(
                        title: "Helper Glow",
                        text: "Highlights the current Note in multi-Note Cues and shows a Keyboard hint when an answer takes longer."
                    )
                }

                HStack {
                    Toggle(isOn: tempoMeterBinding) {
                        SettingsRowLabel(
                            title: "Tempo Meter",
                            systemImage: "metronome"
                        )
                    }

                    SettingHelpButton(
                        title: "Tempo Meter",
                        text: "Shows a meter that rises with quick correct answers, falls after misses, and drains over time."
                    )
                }

                HStack {
                    Toggle(isOn: motionBinding) {
                        SettingsRowLabel(
                            title: "Reduce Motion",
                            systemImage: "wand.and.sparkles.inverse"
                        )
                    }

                    SettingHelpButton(
                        title: "Reduce Motion",
                        text: "Reduces motion in Practice, including Note bounce, replay pulses, and helper prompt effects."
                    )
                }

                GuardedSettingsToggle(
                    title: "Darker Practice Mode",
                    systemImage: "circle.lefthalf.filled",
                    isOn: usesNativeDarkPracticeColors,
                    helpText: "Darker Practice Mode uses system dark surfaces on the practice screen. It is available only when the device is in Dark Mode; in Light Mode the toggle is disabled.",
                    blockedHelpText: nativeDarkPracticeModeBlockedHelpText,
                    onToggle: onToggleNativeDarkPracticeColors
                )
            }
        }
        .navigationTitle("Practice Display")
        .scrollContentBackground(.hidden)
        .background(TabPageBackgroundView())
        .tint(Theme.selectedControlTint)
    }

    private var motionBinding: Binding<Bool> {
        Binding(
            get: { !isNoteBounceEffectEnabled },
            set: { newValue in
                guard newValue == isNoteBounceEffectEnabled else { return }
                onToggleNoteBounceEffect()
            }
        )
    }

    private var helperGlowBinding: Binding<Bool> {
        Binding(
            get: { isHelperGlowEnabled },
            set: { newValue in
                guard newValue != isHelperGlowEnabled else { return }
                onToggleHelperGlow()
            }
        )
    }

    private var tempoMeterBinding: Binding<Bool> {
        Binding(
            get: { isTempoMeterEnabled },
            set: { newValue in
                guard newValue != isTempoMeterEnabled else { return }
                onToggleTempoMeter()
            }
        )
    }

    private var isNativeDarkPracticeModeUnavailable: Bool {
        colorScheme == .light
    }

    private var nativeDarkPracticeModeBlockedHelpText: String? {
        isNativeDarkPracticeModeUnavailable ? "Darker Practice Mode is available only when the device is in Dark Mode." : nil
    }
}

/// Identifies the mutually constrained prompt modes on the settings screen.
private enum PracticeMode {
    case staff
    case tone
}

/// Shows whether guesses come from the on-screen keyboard or a connected MIDI device.
struct InputModeSelectorView: View {
    let isMIDIDeviceConnected: Bool
    @State private var midiHelpPresentationID = 0

    var body: some View {
        Section {
            HStack {
                LabeledContent {
                    Text(isMIDIDeviceConnected ? "MIDI" : "On-Screen")
                        .foregroundStyle(.secondary)
                } label: {
                    SettingsRowLabel(
                        title: "Current Input Source",
                        systemImage: isMIDIDeviceConnected ? "cable.connector" : "pianokeys"
                    )
                }

                SettingHelpButton(
                    title: "Current Input Source",
                    text: "Shows whether answers are coming from a connected MIDI keyboard or the on-screen Piano Keyboard."
                )
            }

            HStack {
                Button {
                    midiHelpPresentationID += 1
                } label: {
                    SettingsRowLabel(
                        title: "How to Connect MIDI",
                        systemImage: "questionmark.circle"
                    )
                }

                Spacer()

                SettingHelpButton(
                    title: "How to Connect MIDI",
                    text: "Connect a USB MIDI keyboard or digital piano. During regular Practice, answers switch to MIDI automatically when Piano Notes Practice detects a compatible device. Tutorials continue to use the on-screen Piano Keyboard. If you use a digital piano, make sure USB MIDI is enabled on the instrument.",
                    presentationID: midiHelpPresentationID
                )
            }
        }
    }
}

/// Labels a native settings row with a title and icon.
private struct SettingsRowLabel: View {
    let title: String
    let systemImage: String

    init(
        title: String,
        systemImage: String
    ) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
            .tint(Theme.selectedControlTint)
    }
}

/// Keeps constrained setting toggles interactive while explaining blocked changes.
private struct GuardedSettingsToggle: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let helpText: String
    let blockedHelpText: String?
    let onToggle: () -> Void

    @State private var helpPresentationID = 0
    @State private var displayedHelpText: String
    @State private var toggleOffset: CGFloat = 0
    @State private var pendingOffsetTasks: [Task<Void, Never>] = []

    init(
        title: String,
        systemImage: String,
        isOn: Bool,
        helpText: String,
        blockedHelpText: String? = nil,
        onToggle: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.helpText = helpText
        self.blockedHelpText = blockedHelpText
        self.onToggle = onToggle
        _displayedHelpText = State(initialValue: helpText)
    }

    var body: some View {
        HStack {
            Toggle(isOn: toggleBinding) {
                SettingsRowLabel(
                    title: title,
                    systemImage: systemImage
                )
            }
            .offset(x: toggleOffset)
            .animation(.easeOutCubic(duration: 0.08), value: toggleOffset)

            SettingHelpButton(
                title: title,
                text: displayedHelpText,
                presentationID: helpPresentationID
            )
        }
        .onChange(of: helpText) { _, newValue in
            guard displayedHelpText != newValue else { return }
            displayedHelpText = newValue
        }
        .onChange(of: blockedHelpText) { _, newValue in
            guard newValue == nil, displayedHelpText != helpText else { return }
            displayedHelpText = helpText
        }
        .onDisappear(perform: cancelPendingOffsetWorkItems)
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                guard newValue != isOn else { return }

                if let blockedHelpText {
                    presentBlockedAttempt(blockedHelpText)
                    return
                }

                displayedHelpText = helpText
                onToggle()
            }
        )
    }

    private func presentBlockedAttempt(_ text: String) {
        cancelPendingOffsetWorkItems()
        displayedHelpText = text
        helpPresentationID += 1

        withAnimation(.easeOutCubic(duration: 0.08)) {
            toggleOffset = 7
        }

        scheduleOffset(-5, after: 0.08)
        scheduleOffset(0, after: 0.16)
    }

    private func scheduleOffset(_ offset: CGFloat, after delay: TimeInterval) {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOutCubic(duration: 0.08)) {
                toggleOffset = offset
            }
        }

        pendingOffsetTasks.append(task)
    }

    private func cancelPendingOffsetWorkItems() {
        pendingOffsetTasks.forEach { $0.cancel() }
        pendingOffsetTasks.removeAll()
    }
}

/// Presents brief setting explanations using the native popover presentation.
private struct SettingHelpButton: View {
    let title: String
    let text: String
    let presentationID: Int

    init(
        title: String,
        text: String,
        presentationID: Int = 0
    ) {
        self.title = title
        self.text = text
        self.presentationID = presentationID
    }

    var body: some View {
        HelpPopoverButton(
            title: title,
            text: text,
            presentationID: presentationID
        )
    }
}
