import Foundation

/// Records what Studio itself created, so "Remove Studio-managed components" only undoes
/// Studio's own work and leaves pre-existing installations alone.
nonisolated struct StudioLedger: Codable, Equatable, Sendable {
    /// Path of a config file Studio created from scratch (nil if it already existed).
    var createdConfigPath: String?
    /// The config file `addedKeys` refers to. Keys recorded for another file are discarded.
    var configPath: String?
    /// `section.key` entries that did not exist before Studio wrote them.
    var addedKeys: Set<String> = []
    /// Editor extension ids Studio installed.
    var installedExtensions: Set<String> = []

    private static let defaultsKey = "studio.ledger.v1"

    static func load(_ defaults: UserDefaults = .standard) -> StudioLedger {
        guard let data = defaults.data(forKey: defaultsKey),
              let ledger = try? JSONDecoder().decode(StudioLedger.self, from: data) else { return StudioLedger() }
        return ledger
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    /// Switches the ledger to a config file, forgetting keys recorded for a different one.
    mutating func scope(to path: String) {
        if configPath != path { configPath = path; addedKeys = [] }
    }

    func addedKeys(for path: String) -> Set<String> { configPath == path ? addedKeys : [] }

    /// Notes which keys an edit batch is about to *create*.
    mutating func recordAdditions(_ edits: [ConfigEdit], before document: INIDocument?) {
        for case let .set(section, key, value) in edits where value != nil {
            if document?.entry(section: section, key: key) == nil {
                addedKeys.insert("\(section.lowercased()).\(key)")
            }
        }
    }

    mutating func forgetRemovals(_ edits: [ConfigEdit]) {
        for case let .set(section, key, nil) in edits {
            addedKeys.remove("\(section.lowercased()).\(key)")
        }
    }
}
