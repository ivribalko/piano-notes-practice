import SwiftUI
import UIKit

@main
/// Launches Piano Notes Practice and hosts the root scene.
struct PianoNotesPracticeApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootContainerView()
                .onAppear {
                    AppLog.app.info(
                        "Piano Notes Practice appeared; version \(AppLog.appVersionSummary, privacy: .public), iOS \(UIDevice.current.systemVersion, privacy: .public), device model \(UIDevice.current.model, privacy: .public)"
                    )
                    updateIdleTimer(for: scenePhase)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            AppLog.app.info("Scene phase changed to \(String(describing: phase), privacy: .public)")
            updateIdleTimer(for: phase)
        }
    }

    private func updateIdleTimer(for phase: ScenePhase) {
        #if DEBUG
        UIApplication.shared.isIdleTimerDisabled = phase == .active
        #endif
    }
}
