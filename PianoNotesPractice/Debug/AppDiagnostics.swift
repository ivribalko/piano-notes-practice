import Foundation
import OSLog

/// Centralizes app log categories used for device diagnostics.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.local.PianoNotesPractice"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let input = Logger(subsystem: subsystem, category: "Input")
    static let learning = Logger(subsystem: subsystem, category: "Learning")
    static let midi = Logger(subsystem: subsystem, category: "MIDI")
    static let practice = Logger(subsystem: subsystem, category: "Practice")
    static let tutorial = Logger(subsystem: subsystem, category: "Tutorial")

    static var appVersionSummary: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }
}
