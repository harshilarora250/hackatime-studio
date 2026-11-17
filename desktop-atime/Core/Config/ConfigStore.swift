import Foundation

/// One targeted change to the config. Studio never rewrites the file wholesale — it re-reads
/// the current file, applies these operations, and writes the result atomically.
nonisolated enum ConfigEdit: Equatable, Sendable {
    case set(section: String, key: String, value: String?)

    static func settings(_ key: String, _ value: String?) -> ConfigEdit {
        .set(section: "settings", key: key, value: value)
    }
}

nonisolated enum ConfigStoreError: LocalizedError, Equatable {
    case notUTF8(String)
    case unreadable(String)
    case writeFailed(String)
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .notUTF8(let p): "\(p) isn’t valid UTF-8 text. Studio won’t modify it to avoid corrupting it — please fix the file manually."
        case .unreadable(let why): "Couldn’t read the config file: \(why)"
        case .writeFailed(let why): "Couldn’t save the config file: \(why)"
        case .backupFailed(let why): "Couldn’t create a backup before saving, so nothing was changed: \(why)"
        }
    }
}

nonisolated struct ConfigFingerprint: Equatable, Sendable {
    var exists: Bool
    var modified: Date?
    var size: Int?
}

nonisolated struct ConfigBackup: Identifiable, Hashable, Sendable {
    var url: URL
    var created: Date
    var id: URL { url }
}

nonisolated enum ConfigStore {

    static let maxBackups = 30

    // MARK: Reading

    static func read(_ location: ConfigLocation) throws -> INIDocument? {
        let target = location.url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let data: Data
        do { data = try Data(contentsOf: target) } catch {
            throw ConfigStoreError.unreadable(error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigStoreError.notUTF8(location.displayPath)
        }
        return INIDocument(text: text)
    }

    static func fingerprint(_ location: ConfigLocation) -> ConfigFingerprint {
        let path = location.url.resolvingSymlinksInPath().path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return ConfigFingerprint(exists: false)
        }
        return ConfigFingerprint(exists: true, modified: attrs[.modificationDate] as? Date,
                                 size: (attrs[.size] as? NSNumber)?.intValue)
    }

    // MARK: Writing

    /// Applies `edits` to the file currently on disk and writes it atomically.
    /// Returns the resulting document. When nothing changes, nothing is written.
    @discardableResult
    static func apply(_ edits: [ConfigEdit], to location: ConfigLocation,
                      backupsDirectory: URL = StudioPaths.backupsDirectory) throws -> INIDocument {
        let fm = FileManager.default
        let target = location.url.resolvingSymlinksInPath()
        let existed = fm.fileExists(atPath: target.path)

        var document = try read(location) ?? INIDocument()
        let before = document.serialized()
        for case let .set(section, key, value) in edits {
            document.set(value, section: section, key: key)
        }
        let after = document.serialized()
        guard after != before || !existed else { return document }

        if existed {
            do { try backup(target, into: backupsDirectory) } catch {
                throw ConfigStoreError.backupFailed(error.localizedDescription)
            }
        }
        try atomicWrite(after, to: target)
        return document
    }

    static func atomicWrite(_ text: String, to target: URL) throws {
        let fm = FileManager.default
        let directory = target.deletingLastPathComponent()
        do {
            if !fm.fileExists(atPath: directory.path) {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
            }
            let permissions = (try? fm.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.int16Value ?? 0o600
            let temp = directory.appending(path: ".\(target.lastPathComponent).studio-\(UUID().uuidString.prefix(8)).tmp")
            guard fm.createFile(atPath: temp.path, contents: Data(text.utf8),
                                attributes: [.posixPermissions: permissions]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            if rename(temp.path, target.path) != 0 {
                let code = errno
                try? fm.removeItem(at: temp)
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
        } catch let error as ConfigStoreError {
            throw error
        } catch {
            throw ConfigStoreError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: Backups

    @discardableResult
    static func backup(_ file: URL, into directory: URL, label: String = "wakatime.cfg") throws -> URL {
        try StudioPaths.ensurePrivateDirectory(directory)
        let stamp = backupFormatter.string(from: Date())
        var destination = directory.appending(path: "\(label)-\(stamp).bak")
        var n = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            n += 1
            destination = directory.appending(path: "\(label)-\(stamp)-\(n).bak")
        }
        try FileManager.default.copyItem(at: file, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        prune(directory, label: label)
        return destination
    }

    static func backups(in directory: URL = StudioPaths.backupsDirectory, label: String = "wakatime.cfg") -> [ConfigBackup] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix(label + "-") && $0.pathExtension == "bak" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return ConfigBackup(url: url, created: date)
            }
            .sorted { $0.created > $1.created }
    }

    /// Restores a backup over the live file (the current file is backed up first).
    static func restore(_ item: ConfigBackup, to location: ConfigLocation,
                        backupsDirectory: URL = StudioPaths.backupsDirectory) throws {
        let target = location.url.resolvingSymlinksInPath()
        guard let data = FileManager.default.contents(atPath: item.url.path),
              let text = String(data: data, encoding: .utf8) else {
            throw ConfigStoreError.unreadable("backup is missing or not text")
        }
        if FileManager.default.fileExists(atPath: target.path) {
            try backup(target, into: backupsDirectory)
        }
        try atomicWrite(text, to: target)
    }

    private static func prune(_ directory: URL, label: String) {
        for old in backups(in: directory, label: label).dropFirst(maxBackups) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    private static let backupFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return f
    }()
}
