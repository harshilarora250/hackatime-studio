import Foundation
import Testing
@testable import desktop_atime

@Suite("ConfigStore file safety")
struct ConfigStoreTests {

    final class Sandbox {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "studio-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        var backups: URL { root.appending(path: "Backups") }
        func location(_ name: String = ".wakatime.cfg") -> ConfigLocation {
            let url = root.appending(path: name)
            return ConfigLocation(url: url, source: .home, exists: FileManager.default.fileExists(atPath: url.path),
                                  editorPluginURL: url, shadowed: [])
        }
    }

    @Test func createsNewFileWithPrivatePermissions() throws {
        let box = try Sandbox()
        let loc = box.location()
        try ConfigStore.apply([.settings("api_key", "abc")], to: loc, backupsDirectory: box.backups)
        let text = try String(contentsOf: loc.url, encoding: .utf8)
        #expect(text == "[settings]\napi_key = abc\n")
        let perms = try FileManager.default.attributesOfItem(atPath: loc.url.path)[.posixPermissions] as? NSNumber
        #expect(perms?.int16Value == 0o600)
        #expect(ConfigStore.backups(in: box.backups).isEmpty, "no backup for a brand-new file")
    }

    @Test func backsUpBeforeModifyingAndPreservesUnknownContent() throws {
        let box = try Sandbox()
        let loc = box.location()
        let original = "; my notes\n[settings]\napi_key = abc\nmystery = 1\n\n[other]\nfoo = bar\n"
        try original.write(to: loc.url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: loc.url.path)

        try ConfigStore.apply([.settings("debug", "true")], to: loc, backupsDirectory: box.backups)

        let text = try String(contentsOf: loc.url, encoding: .utf8)
        #expect(text == "; my notes\n[settings]\napi_key = abc\nmystery = 1\ndebug = true\n\n[other]\nfoo = bar\n")
        let backups = ConfigStore.backups(in: box.backups)
        #expect(backups.count == 1)
        #expect(try String(contentsOf: backups[0].url, encoding: .utf8) == original)
        let perms = try FileManager.default.attributesOfItem(atPath: loc.url.path)[.posixPermissions] as? NSNumber
        #expect(perms?.int16Value == 0o640, "existing permissions are preserved")
    }

    @Test func noWriteWhenNothingChanges() throws {
        let box = try Sandbox()
        let loc = box.location()
        try "[settings]\ndebug = true\n".write(to: loc.url, atomically: true, encoding: .utf8)
        try ConfigStore.apply([.settings("debug", "true")], to: loc, backupsDirectory: box.backups)
        #expect(ConfigStore.backups(in: box.backups).isEmpty)
    }

    @Test func appliesEditsToLatestDiskContent() throws {
        let box = try Sandbox()
        let loc = box.location()
        try "[settings]\napi_key = abc\n".write(to: loc.url, atomically: true, encoding: .utf8)
        _ = try ConfigStore.read(loc)
        // Another tool edits the file after Studio loaded it.
        try "[settings]\napi_key = abc\nhostname = laptop\n".write(to: loc.url, atomically: true, encoding: .utf8)
        try ConfigStore.apply([.settings("debug", "true")], to: loc, backupsDirectory: box.backups)
        let text = try String(contentsOf: loc.url, encoding: .utf8)
        #expect(text.contains("hostname = laptop"))
        #expect(text.contains("debug = true"))
    }

    @Test func writesThroughSymlinks() throws {
        let box = try Sandbox()
        let real = box.root.appending(path: "dotfiles-wakatime.cfg")
        try "[settings]\napi_key = abc\n".write(to: real, atomically: true, encoding: .utf8)
        let link = box.root.appending(path: ".wakatime.cfg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        try ConfigStore.apply([.settings("debug", "true")], to: box.location(), backupsDirectory: box.backups)

        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink, "symlink is kept")
        #expect(try String(contentsOf: real, encoding: .utf8).contains("debug = true"))
    }

    @Test func refusesNonUTF8Files() throws {
        let box = try Sandbox()
        let loc = box.location()
        try Data([0x5B, 0xFF, 0xFE, 0x5D]).write(to: loc.url)
        #expect(throws: ConfigStoreError.self) {
            try ConfigStore.apply([.settings("debug", "true")], to: loc, backupsDirectory: box.backups)
        }
        #expect(try Data(contentsOf: loc.url) == Data([0x5B, 0xFF, 0xFE, 0x5D]), "file untouched")
    }

    @Test func restoreBringsBackPreviousVersion() throws {
        let box = try Sandbox()
        let loc = box.location()
        try "[settings]\napi_key = one\n".write(to: loc.url, atomically: true, encoding: .utf8)
        try ConfigStore.apply([.settings("api_key", "two")], to: loc, backupsDirectory: box.backups)
        let backup = try #require(ConfigStore.backups(in: box.backups).first)
        try ConfigStore.restore(backup, to: loc, backupsDirectory: box.backups)
        #expect(try String(contentsOf: loc.url, encoding: .utf8) == "[settings]\napi_key = one\n")
    }

    @Test func prunesOldBackups() throws {
        let box = try Sandbox()
        let file = box.root.appending(path: "x.cfg")
        try "a".write(to: file, atomically: true, encoding: .utf8)
        for _ in 0..<(ConfigStore.maxBackups + 5) {
            try ConfigStore.backup(file, into: box.backups)
        }
        #expect(ConfigStore.backups(in: box.backups).count == ConfigStore.maxBackups)
    }
}

@Suite("ConfigLocator")
struct ConfigLocatorTests {

    func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    let noEnv = ShellEnvironment(wakatimeHome: nil, xdgConfigHome: nil, hasAPIKeyVariable: false,
                                 hasAPIURLVariable: false, resolvedFromShell: false)

    @Test func defaultsToHomeFileWhenNothingExists() throws {
        let home = try makeHome()
        let loc = ConfigLocator.locate(environment: noEnv, home: home)
        #expect(loc.url == home.appending(path: ".wakatime.cfg"))
        #expect(!loc.exists)
        #expect(loc.editorsReadSameFile)
    }

    @Test func prefersHomeFileOverXDG() throws {
        let home = try makeHome()
        try "".write(to: home.appending(path: ".wakatime.cfg"), atomically: true, encoding: .utf8)
        let xdg = home.appending(path: ".config/wakatime")
        try FileManager.default.createDirectory(at: xdg, withIntermediateDirectories: true)
        try "".write(to: xdg.appending(path: "wakatime.cfg"), atomically: true, encoding: .utf8)
        let loc = ConfigLocator.locate(environment: noEnv, home: home)
        #expect(loc.source == .home)
        #expect(loc.shadowed.count == 1)
    }

    @Test func usesXDGWhenOnlyXDGExistsAndFlagsEditorMismatch() throws {
        let home = try makeHome()
        let xdg = home.appending(path: ".config/wakatime")
        try FileManager.default.createDirectory(at: xdg, withIntermediateDirectories: true)
        try "".write(to: xdg.appending(path: "wakatime.cfg"), atomically: true, encoding: .utf8)
        let loc = ConfigLocator.locate(environment: noEnv, home: home)
        #expect(loc.source == .xdg)
        #expect(!loc.editorsReadSameFile)
    }

    @Test func honoursWakatimeHome() throws {
        let home = try makeHome()
        let custom = home.appending(path: "custom")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        var env = noEnv
        env.wakatimeHome = custom.path
        let loc = ConfigLocator.locate(environment: env, home: home)
        #expect(loc.source == .wakatimeHome)
        #expect(loc.url == custom.appending(path: ".wakatime.cfg"))
        #expect(loc.editorsReadSameFile)
    }
}
