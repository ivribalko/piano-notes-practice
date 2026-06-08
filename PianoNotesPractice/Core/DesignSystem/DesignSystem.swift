import Foundation
import SwiftUI

/// Provides shared visual constants and colors for all app features.
enum Theme {
    static let selectedControlTint = Color.accentColor
    static let highlightGlowScaleRange: ClosedRange<CGFloat> = 0.97...0.99
    static let primaryTextColor = Color(red: 0.08, green: 0.12, blue: 0.19)
    static let secondaryTextColor = Color(red: 0.31, green: 0.38, blue: 0.48)
    static let pageHorizontalPadding: CGFloat = 18
    static let pageTopPadding: CGFloat = 0
    static let pageBottomPadding: CGFloat = 28
    static let panelSpacing: CGFloat = 16
    static let settingsSectionSpacing: CGFloat = 36
    static let panelCornerRadius: CGFloat = 26
    static let panelContentPadding: CGFloat = 18
    static let panelHeight: CGFloat = 220
    static let centeredPhoneLayoutMaxWidth: CGFloat = 460
    static let debugControlVisualSize: CGFloat = 38
    static let debugControlHitSize: CGFloat = 44
    static let notationColor = Color.black
    static let nativeNotationColor = Color(uiColor: .label)
    static let panelSurface = Color(red: 0.94, green: 0.97, blue: 0.99)
    static let nativePracticePanelSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let nativePianoKeySurface = Color(uiColor: .tertiarySystemGroupedBackground)
    static let nativeBlackPianoKeySurface = Color.black
    static let practicePanelSurface = Color.white
    static let practicePanelPrimaryTextColor = Color(uiColor: .label)
    static let practicePanelSecondaryTextColor = Color(uiColor: .secondaryLabel)
    static let panelInsetSurface = Color.white.opacity(0.88)
    static let unselectedControlSurface = panelSurface
    static let failedAnswerFeedbackTint = Color.red
}

/// Applies the shared large-title navigation presentation.
struct AppNavigationChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(.large)
    }
}

/// Resolves practice surfaces in the selected color scheme.
struct PracticeSurfaceColorSchemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let usesNativeDarkPracticeColors: Bool

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, usesNativeDarkPracticeColors ? colorScheme : .light)
    }
}

extension View {
    /// Uses the app's consistent navigation title appearance.
    func appNavigationChrome() -> some View { modifier(AppNavigationChromeModifier()) }

    /// Resolves dynamic colors inside practice panels using the selected mode.
    func practiceSurfaceColorScheme(usesNativeDarkPracticeColors: Bool) -> some View {
        modifier(PracticeSurfaceColorSchemeModifier(usesNativeDarkPracticeColors: usesNativeDarkPracticeColors))
    }
}

extension Animation {
    /// Uses cubic ease-out timing for non-physics UI motion.
    static func easeOutCubic(duration: TimeInterval) -> Animation {
        .timingCurve(0.215, 0.61, 0.355, 1, duration: duration)
    }
}
