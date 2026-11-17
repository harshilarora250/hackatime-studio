import Foundation

/// A tracking extension Studio knows about for a given editor.
nonisolated struct KnownExtension: Identifiable, Hashable, Sendable {
    enum Role: Hashable, Sendable {
        /// Recommended by Hackatime's docs.
        case recommended
        /// Works with Hackatime (reads the same config).
        case compatible
        /// Not supported; Hackatime docs warn against it.
        case unofficial
    }
    var id: String          // marketplace identifier, e.g. hackatime.hackatime-time-tracker
    var name: String
    var publisher: String
    var role: Role
    var marketplaceURL: URL
}

nonisolated struct InstalledExtension: Identifiable, Hashable, Sendable {
    var id: String          // lowercased identifier
    var version: String?
    var location: URL?
}

nonisolated struct EditorStatus: Equatable, Sendable {
    var appURL: URL?
    var appVersion: String?
    var cliURL: URL?
    var isRunning: Bool
    /// Tracking-related extensions found (only ids from `knownExtensions`).
    var installed: [InstalledExtension]
    /// Where the installed-extension list came from, for honest messaging.
    var detectionSource: String
    var detectionError: String?

    var isAppInstalled: Bool { appURL != nil }
    func isInstalled(_ id: String) -> Bool { installed.contains { $0.id == id.lowercased() } }
    func version(of id: String) -> String? { installed.first { $0.id == id.lowercased() }?.version }
}

/// Everything Studio needs from an editor. V1 ships VS Code only; other editors (Cursor,
/// Windsurf, Zed, JetBrains…) can conform to this without changes elsewhere.
@MainActor
protocol EditorIntegration: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// The `editor` value Hackatime stores for heartbeats from this editor (used to verify tracking).
    var heartbeatEditorName: String { get }
    var knownExtensions: [KnownExtension] { get }
    var setupDocsURL: URL { get }

    func detect() async -> EditorStatus
    func install(_ ext: KnownExtension) async throws
    func uninstall(_ ext: KnownExtension) async throws
    func openExtensionPage(_ ext: KnownExtension)
}

extension EditorIntegration {
    var recommendedExtension: KnownExtension? { knownExtensions.first { $0.role == .recommended } }
    func known(_ id: String) -> KnownExtension? { knownExtensions.first { $0.id.lowercased() == id.lowercased() } }
}

nonisolated enum EditorIntegrationError: LocalizedError {
    case editorNotInstalled(String)
    case cliMissing(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .editorNotInstalled(let e): "\(e) isn’t installed."
        case .cliMissing(let e): "Couldn’t find \(e)’s command-line tool inside the app bundle."
        case .commandFailed(let why): why
        }
    }
}
