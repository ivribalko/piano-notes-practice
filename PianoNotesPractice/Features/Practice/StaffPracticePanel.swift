import SwiftUI

/// Presents the active practice prompt as staff notation or a replay cue.
struct StaffPracticePanel: View {
    @State private var replayPulseScale = 1.0
    @State private var replayPulseOpacity = 1.0
    @State private var celebrationPopScale = CGSize(width: 1.0, height: 1.0)
    @State private var pendingReplayPulseResetTask: Task<Void, Never>?
    @State private var pendingCelebrationPopTasks: [Task<Void, Never>] = []
    @State private var feedbackPulseID = 0
    @State private var showsAudioCacheLoadingText = false

    let notes: [QuizNote]
    let octaveIntroductionNotes: [QuizNote]
    let currentGuessIndex: Int
    let isStaffVisible: Bool
    let isToneEnabled: Bool
    let isAudioCacheLoading: Bool
    let flashColor: Color
    let celebrationReasonText: String?
    let tutorialHelperText: String?
    let isTutorialCelebratory: Bool
    let noteScale: Double
    let isNoteBounceEffectEnabled: Bool
    let isHelperGlowEnabled: Bool
    let usesNativeDarkPracticeColors: Bool
    let noteAppearanceID: Int
    let noteDisappearanceID: Int
    let onReplay: () -> Void
    let onAcknowledgeCelebration: () -> Void
    let onAcknowledgeTutorial: () -> Void

    var body: some View {
        GlassSection(tint: cardTint) {
            ZStack(alignment: .bottom) {
                if let celebrationReasonText {
                    celebrationPrompt(text: celebrationReasonText)
                } else if !octaveIntroductionNotes.isEmpty {
                    staffPrompt(
                        notes: octaveIntroductionNotes,
                        currentGuessIndex: -1,
                        isHelperGlowEnabled: false
                    )
                } else if let tutorialHelperText {
                    tutorialPrompt(text: tutorialHelperText)
                } else if isStaffVisible {
                    staffPrompt(
                        notes: notes,
                        currentGuessIndex: currentGuessIndex,
                        isHelperGlowEnabled: isHelperGlowEnabled
                    )
                } else if isToneEnabled {
                    tonePrompt
                } else {
                    disabledPrompt
                }

                if showsAudioCacheLoadingText && isRealStaffPrompt {
                    audioCacheLoadingText
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.panelHeight)
        }
        .overlay {
            CelebrationConfettiBurstView(
                triggerKey: isNoteBounceEffectEnabled ? celebrationReasonText : nil
            )
        }
        .overlay(
            KeyPressPulseView(
                trigger: feedbackPulseID,
                tint: flashColor,
                cornerRadius: Theme.panelCornerRadius,
                expansionAmount: 8,
                includesInnerPulse: true,
                allowsMotion: isNoteBounceEffectEnabled
            )
        )
        .promptPanelBehavior(
            promptKey: messagePromptKey,
            isActive: isMessagePromptActive,
            allowsMotion: isNoteBounceEffectEnabled,
            onAcknowledge: acknowledgeActiveMessage,
            onInactiveTap: replayIfAvailable
        )
        .scaleEffect(
            x: effectiveReplayPanelScale * celebrationPopScale.width,
            y: effectiveReplayPanelScale * celebrationPopScale.height
        )
        .opacity(effectiveReplayPanelOpacity)
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeOutCubic(duration: 0.2), value: flashColor)
        .animation(.easeOutCubic(duration: 0.18), value: isStaffVisible)
        .animation(.easeOutCubic(duration: 0.18), value: isToneEnabled)
        .animation(.easeOutCubic(duration: 0.18), value: showsAudioCacheLoadingText)
        .practiceSurfaceColorScheme(usesNativeDarkPracticeColors: usesNativeDarkPracticeColors)
        .onChange(of: flashColor) { _, newValue in
            guard newValue != .clear else { return }
            feedbackPulseID += 1
        }
        .task(id: celebrationReasonText) {
            guard celebrationReasonText != nil else { return }
            guard isNoteBounceEffectEnabled else {
                celebrationPopScale = CGSize(width: 1.0, height: 1.0)
                return
            }
            animateCelebrationPop()
        }
        .task(id: isAudioCacheLoading) {
            if isAudioCacheLoading {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                showsAudioCacheLoadingText = true
            } else {
                showsAudioCacheLoadingText = false
            }
        }
        .onDisappear {
            pendingReplayPulseResetTask?.cancel()
            pendingCelebrationPopTasks.forEach { $0.cancel() }
            pendingCelebrationPopTasks.removeAll()
        }
    }

    private var cardTint: Color {
        if isMessagePromptActive {
            return Theme.selectedControlTint
        }

        if isStaffNotationPrompt {
            return usesNativeDarkPracticeColors ? Theme.nativePracticePanelSurface : Theme.practicePanelSurface
        }

        return usesNativeDarkPracticeColors ? Theme.nativePracticePanelSurface : Theme.practicePanelSurface
    }

    private var isMessagePromptActive: Bool {
        celebrationReasonText != nil || displayedTutorialHelperText != nil
    }

    private var isStaffNotationPrompt: Bool {
        !octaveIntroductionNotes.isEmpty || isStaffVisible
    }

    private var messagePromptKey: String {
        celebrationReasonText ?? displayedTutorialHelperText ?? ""
    }

    private var displayedTutorialHelperText: String? {
        octaveIntroductionNotes.isEmpty ? tutorialHelperText : nil
    }

    private var isRealStaffPrompt: Bool {
        celebrationReasonText == nil && displayedTutorialHelperText == nil && (isStaffVisible || !octaveIntroductionNotes.isEmpty)
    }

    private var audioCacheLoadingText: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass")
            Text("Sounds are getting ready...")
        }
        .font(.footnote.weight(.semibold))
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.practicePanelSecondaryTextColor)
    }

    private func staffPrompt(
        notes: [QuizNote],
        currentGuessIndex: Int,
        isHelperGlowEnabled: Bool
    ) -> some View {
        StaffView(
            notes: notes,
            currentGuessIndex: currentGuessIndex,
            isNoteBounceEffectEnabled: isNoteBounceEffectEnabled,
            isHelperGlowEnabled: isHelperGlowEnabled,
            usesNativeDarkPracticeColors: usesNativeDarkPracticeColors,
            appearanceTrigger: noteAppearanceID,
            disappearanceTrigger: noteDisappearanceID
        )
        .transition(.opacity)
    }

    private func tutorialPrompt(text: String) -> some View {
        messagePrompt(
            systemImage: isTutorialCelebratory ? "party.popper.fill" : "questionmark.circle.fill",
            text: text
        )
    }

    private var tonePrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Theme.practicePanelSecondaryTextColor)

            Text("Tap to replay")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.practicePanelSecondaryTextColor)
        }
        .transition(.opacity)
    }

    private var disabledPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.slash")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Theme.practicePanelSecondaryTextColor)

            Text("Enable Cue Staff or Cue Sounds")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.practicePanelSecondaryTextColor)
        }
        .transition(.opacity)
    }

    private func celebrationPrompt(text: String) -> some View {
        messagePrompt(
            systemImage: "party.popper.fill",
            text: text
        )
    }

    private func messagePrompt(
        systemImage: String,
        text: String
    ) -> some View {
        PromptOverlayView(
            systemImage: systemImage,
            text: text,
            allowsMotion: isNoteBounceEffectEnabled
        )
        .transition(.opacity)
    }

    private var accessibilityLabel: String {
        if let celebrationReasonText {
            return celebrationReasonText
        }

        if let displayedTutorialHelperText {
            return "\(displayedTutorialHelperText) Continue"
        }

        if isStaffVisible {
            return "Staff"
        }

        if isToneEnabled {
            return "Replay Cue"
        }

        return "Practice disabled"
    }

    private var canReplay: Bool {
        guard celebrationReasonText == nil else { return false }
        guard octaveIntroductionNotes.isEmpty else { return false }
        guard tutorialHelperText == nil else { return false }
        return isStaffVisible || isToneEnabled
    }

    private var effectiveReplayPanelScale: Double {
        isNoteBounceEffectEnabled ? noteScale * replayPulseScale : 1.0
    }

    private var effectiveReplayPanelOpacity: Double {
        isNoteBounceEffectEnabled ? replayPulseOpacity : 1.0
    }

    private func acknowledgeActiveMessage() {
        if celebrationReasonText != nil {
            AppLog.input.info("Prompt panel celebration acknowledged")
            onAcknowledgeCelebration()
            return
        }

        if tutorialHelperText != nil {
            AppLog.input.info("Prompt panel tutorial prompt acknowledged")
            onAcknowledgeTutorial()
        }
    }

    private func replayIfAvailable() {
        guard canReplay else { return }
        AppLog.input.info("Prompt panel replay requested")
        if isNoteBounceEffectEnabled {
            animateReplayPulse()
        }
        onReplay()
    }

    private func animateReplayPulse() {
        pendingReplayPulseResetTask?.cancel()

        withAnimation(.spring(response: 0.14, dampingFraction: 0.78)) {
            replayPulseScale = 0.94
            replayPulseOpacity = 0.84
        }

        let resetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                replayPulseScale = 1.0
                replayPulseOpacity = 1.0
            }
        }

        pendingReplayPulseResetTask = resetTask
    }

    private func animateCelebrationPop() {
        pendingCelebrationPopTasks.forEach { $0.cancel() }
        pendingCelebrationPopTasks.removeAll()

        celebrationPopScale = CGSize(width: 1.0, height: 1.0)

        withAnimation(.spring(response: 0.1, dampingFraction: 0.58)) {
            celebrationPopScale = CGSize(width: 0.96, height: 1.035)
        }

        let popTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.14, dampingFraction: 0.52)) {
                celebrationPopScale = CGSize(width: 1.04, height: 0.98)
            }
        }

        let settleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.74)) {
                celebrationPopScale = CGSize(width: 1.0, height: 1.0)
            }
        }

        pendingCelebrationPopTasks = [popTask, settleTask]
    }
}

/// Carries the shared prompt overlay animation phase.
private struct PromptAnimationPhaseKey: EnvironmentKey {
    static let defaultValue = PromptAnimationPhase()
}

extension EnvironmentValues {
    /// Indicates how far the shared prompt overlay has advanced through its reveal.
    fileprivate var promptAnimationPhase: PromptAnimationPhase {
        get { self[PromptAnimationPhaseKey.self] }
        set { self[PromptAnimationPhaseKey.self] = newValue }
    }
}

/// Describes the staged reveal state for a shared prompt overlay.
private struct PromptAnimationPhase: Equatable {
    var textRevealProgress: CGFloat = 0
    var isContinueVisible = false
}

/// Adds the shared active-tint glow, Continue delay, and tap response for prompt panels.
private struct PromptPanelBehaviorModifier: ViewModifier {
    @State private var animationPhase = PromptAnimationPhase()
    @State private var glowScale: CGFloat = 1.0
    @State private var tapScale = 1.0
    @State private var tapOpacity = 1.0
    @State private var pendingTapTask: Task<Void, Never>?

    let promptKey: String
    let isActive: Bool
    let allowsMotion: Bool
    let onAcknowledge: () -> Void
    let onInactiveTap: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .environment(\.promptAnimationPhase, animationPhase)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous)
                    .stroke(Theme.selectedControlTint.opacity(isActive ? 0.26 : 0), lineWidth: 17)
                    .padding(-4)
                    .blur(radius: 8)
                    .scaleEffect(glowScale)
                .allowsHitTesting(false)
            }
            .scaleEffect(allowsMotion ? tapScale : 1.0)
            .opacity(allowsMotion ? tapOpacity : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous))
            .onTapGesture(perform: handleTap)
            .task(id: isActive) {
                guard isActive else {
                    glowScale = 1.0
                    return
                }

                glowScale = Theme.highlightGlowScaleRange.lowerBound
                withAnimation(.easeOutCubic(duration: 1.2).repeatForever(autoreverses: true)) {
                    glowScale = Theme.highlightGlowScaleRange.upperBound
                }
            }
            .task(id: promptKey) {
                animationPhase = PromptAnimationPhase()
                guard isActive else { return }

                guard allowsMotion else {
                    animationPhase.textRevealProgress = 1
                    animationPhase.isContinueVisible = true
                    return
                }

                withAnimation(.easeOutCubic(duration: 0.46)) {
                    animationPhase.textRevealProgress = 1
                }

                try? await Task.sleep(for: .seconds(NoteTutorial.promptContinueDelay))
                guard !Task.isCancelled else { return }

                withAnimation(.easeOutCubic(duration: 0.22)) {
                    animationPhase.isContinueVisible = true
                }

            }
            .onDisappear {
                pendingTapTask?.cancel()
            }
    }

    private func handleTap() {
        guard isActive else {
            onInactiveTap?()
            return
        }

        guard animationPhase.isContinueVisible else { return }
        animateTap(then: onAcknowledge)
    }

    private func animateTap(then completion: @escaping () -> Void) {
        pendingTapTask?.cancel()

        guard allowsMotion else {
            completion()
            return
        }

        withAnimation(.spring(response: 0.12, dampingFraction: 0.82)) {
            tapScale = 0.96
            tapOpacity = 0.86
        }

        let completionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            completion()

            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                tapScale = 1.0
                tapOpacity = 1.0
            }
        }

        pendingTapTask = completionTask
    }
}

extension View {
    /// Applies the shared blue prompt behavior to celebration and tutorial panels.
    func promptPanelBehavior(
        promptKey: String,
        isActive: Bool,
        allowsMotion: Bool = true,
        onAcknowledge: @escaping () -> Void,
        onInactiveTap: (() -> Void)? = nil
    ) -> some View {
        modifier(
            PromptPanelBehaviorModifier(
                promptKey: promptKey,
                isActive: isActive,
                allowsMotion: allowsMotion,
                onAcknowledge: onAcknowledge,
                onInactiveTap: onInactiveTap
            )
        )
    }
}

/// Displays the shared blue prompt overlay used by practice panels.
struct PromptOverlayView: View {
    @Environment(\.promptAnimationPhase) private var animationPhase
    @State private var iconHorizontalScale = 1.12
    @State private var iconVerticalScale = 0.82
    @State private var iconHorizontalOffset: CGFloat = 0
    @State private var iconRotationDegrees = 0.0
    @State private var promptRowHeight: CGFloat = 0
    @State private var continueHeight: CGFloat = 0

    let systemImage: String
    let text: String
    let allowsMotion: Bool

    private let continueBottomInset: CGFloat = 4
    private let continuePromptSpacing: CGFloat = 22
    private let visiblePromptLift: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                revealedTextRow
                    .frame(width: proxy.size.width)
                    .opacity(textRevealProgress)
                    .scaleEffect(revealedTextScale)
                    .position(
                        x: proxy.size.width / 2,
                        y: revealedTextCenterY(in: proxy.size.height)
                    )

                continueLabel
                    .opacity(animationPhase.isContinueVisible ? 1 : 0)
                    .scaleEffect(continueScale)
                    .offset(y: continueVerticalOffset)
                    .position(
                        x: proxy.size.width / 2,
                        y: continueCenterY(in: proxy.size.height)
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: text) {
            guard allowsMotion else {
                resetIconMotion()
                return
            }

            await animateIconReveal()
        }
    }

    private var continueLabel: some View {
        Label("Continue", systemImage: "hand.tap.fill")
            .font(.footnote.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 14)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            continueHeight = proxy.size.height
                        }
                        .onChange(of: proxy.size.height) { _, newValue in
                            continueHeight = newValue
                        }
                }
            }
    }

    private var revealedTextRow: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(
                    x: iconHorizontalScale,
                    y: iconVerticalScale,
                    anchor: .bottomLeading
                )
                .offset(x: iconHorizontalOffset)
                .rotationEffect(.degrees(iconRotationDegrees))

            Text(text)
        }
        .font(.headline.weight(.semibold))
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        promptRowHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size.height) { _, newValue in
                        promptRowHeight = newValue
                    }
            }
        }
    }

    private var textRevealProgress: Double {
        Double(animationPhase.textRevealProgress)
    }

    private var revealedTextScale: Double {
        guard allowsMotion else { return 1.0 }

        if animationPhase.isContinueVisible {
            return 1.0
        }

        return 1.08 + (0.04 * (1 - textRevealProgress))
    }

    private var continueScale: Double {
        guard allowsMotion else { return 1.0 }
        return animationPhase.isContinueVisible ? 1 : 0.96
    }

    private var continueVerticalOffset: CGFloat {
        guard allowsMotion else { return 0 }
        return animationPhase.isContinueVisible ? 0 : 8
    }

    private func revealedTextCenterY(in containerHeight: CGFloat) -> CGFloat {
        guard animationPhase.isContinueVisible else {
            let motionOffset = allowsMotion ? 18 * (1 - animationPhase.textRevealProgress) : 0
            return (containerHeight / 2) + motionOffset
        }

        let centeredPromptY = containerHeight / 2
        let centeredPromptBottom = centeredPromptY + (promptRowHeight / 2)
        let targetPromptBottom = continueTop(in: containerHeight) - continuePromptSpacing
        let neededLift = max(0, centeredPromptBottom - targetPromptBottom)
        return centeredPromptY - max(visiblePromptLift, neededLift)
    }

    private func continueCenterY(in containerHeight: CGFloat) -> CGFloat {
        containerHeight - continueBottomInset - (continueHeight / 2)
    }

    private func continueTop(in containerHeight: CGFloat) -> CGFloat {
        containerHeight - continueBottomInset - continueHeight
    }

    @MainActor
    private func animateIconReveal() async {
        iconHorizontalScale = 1.08
        iconVerticalScale = 0.88
        iconHorizontalOffset = -1
        iconRotationDegrees = -4

        guard !Task.isCancelled else { return }

        try? await Task.sleep(nanoseconds: 90_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.spring(response: 0.38, dampingFraction: 0.56)) {
            iconHorizontalScale = 1.16
            iconVerticalScale = 1.18
            iconHorizontalOffset = 4
            iconRotationDegrees = 4
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) {
            iconHorizontalScale = 0.98
            iconVerticalScale = 0.98
            iconHorizontalOffset = -1
            iconRotationDegrees = -1
        }

        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            resetIconMotion()
        }
    }

    @MainActor
    private func resetIconMotion() {
        iconHorizontalScale = 1.0
        iconVerticalScale = 1.0
        iconHorizontalOffset = 0
        iconRotationDegrees = 0.0
    }
}
