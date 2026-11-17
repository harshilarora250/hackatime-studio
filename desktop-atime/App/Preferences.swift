import AppKit
import Foundation

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case off = 0, two = 2, five = 5, fifteen = 15, thirty = 30
    var id: Int { rawValue }
    var title: String { self == .off ? "Manually only" : "Every \(rawValue) minutes" }
    var seconds: TimeInterval? { self == .off ? nil : TimeInterval(rawValue * 60) }
}

/// Small typed wrapper over UserDefaults for Studio's own (non-WakaTime) preferences.
enum StudioDefaults {
    static let appearance = "studio.appearance"
    static let refresh = "studio.refreshInterval"
    static let workingFolders = "studio.workingFolders"
    static let setupCompleted = "studio.setupCompleted"
}
