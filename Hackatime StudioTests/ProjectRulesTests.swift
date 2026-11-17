import Foundation
import Testing
@testable import Hackatime_Studio

@Suite("Folder & project rules")
struct ProjectRulesTests {

    @Test func escapingRoundTrips() {
        let path = "/Users/me/Desktop/Hack Club (2025)/v1.0+beta"
        let escaped = ProjectRules.escape(path)
        #expect(escaped == #"/Users/me/Desktop/Hack Club \(2025\)/v1\.0\+beta"#)
        #expect(ProjectRules.unescape(escaped) == path)
        #expect(ProjectRules.unescape("/a/(.*)") == nil, "real regex syntax is not a plain path")
    }

    @Test func eachSubfolderGeneratesCaptureRule() throws {
        let doc = INIDocument(text: "[settings]\napi_key = k\n")
        let edits = try ProjectRules.edits(from: doc, to: [FolderRule(path: "/Users/me/Hack Club", mode: .eachSubfolder)])
        #expect(edits == [.set(section: "projectmap", key: "^/Users/me/Hack Club/([^/]+)/", value: "{0}")])
    }

    @Test func nestedRulesUseLookaheadSoPatternsNeverOverlap() throws {
        let rules = [
            FolderRule(path: "/Users/me/Hack Club", mode: .eachSubfolder),
            FolderRule(path: "/Users/me/Hack Club/Public", mode: .singleProject("public-stuff")),
        ]
        var doc = INIDocument()
        for case let .set(section, key, value) in try ProjectRules.edits(from: doc, to: rules) {
            doc.set(value, section: section, key: key)
        }
        let keys = doc.effectiveEntries(in: "projectmap").map(\.key)
        #expect(keys.contains("^/Users/me/Hack Club/(?!Public/)([^/]+)/"))
        #expect(keys.contains("^/Users/me/Hack Club/Public/"))

        // Behaviour check with the same matching semantics wakatime-cli uses.
        let first = ProjectResolver.apply(pattern: "^/Users/me/Hack Club/(?!Public/)([^/]+)/", template: "{0}",
                                          to: "/Users/me/Hack Club/FirstCommit/src/main.swift")
        #expect(first == "FirstCommit")
        let blocked = ProjectResolver.apply(pattern: "^/Users/me/Hack Club/(?!Public/)([^/]+)/", template: "{0}",
                                            to: "/Users/me/Hack Club/Public/readme.md")
        #expect(blocked == nil)
    }

    @Test func generatedKeysSurviveTheINIParser() throws {
        let rules = [
            FolderRule(path: "/Users/me/Hack Club", mode: .eachSubfolder),
            FolderRule(path: "/Users/me/Hack Club/Public", mode: .singleProject("p")),
            FolderRule(path: "/Users/me/Hack Club/Other (old)", mode: .singleProject("o")),
        ]
        var doc = INIDocument()
        for case let .set(section, key, value) in try ProjectRules.edits(from: doc, to: rules) {
            doc.set(value, section: section, key: key)
        }
        let reparsed = INIDocument(text: doc.serialized())
        for entry in reparsed.effectiveEntries(in: "projectmap") {
            #expect(!entry.key.contains(":"), "go-ini would split the key at ':'")
        }
        #expect(Set(ProjectRules.parse(reparsed).rules) == Set(rules))
    }

    @Test func parsingRecognisesGeneratedRulesAndKeepsCustomOnes() {
        let text = """
        [settings]
        exclude =
            ^COMMIT_EDITMSG$
            ^/Users/me/Secret/
        [projectmap]
        ^/Users/me/Hack Club/(?!Public/)([^/]+)/ = {0}
        ^/Users/me/Hack Club/Public/ = public-stuff
        projects/foo = renamed
        """
        let parsed = ProjectRules.parse(INIDocument(text: text))
        #expect(parsed.rules.contains(FolderRule(path: "/Users/me/Hack Club", mode: .eachSubfolder)))
        #expect(parsed.rules.contains(FolderRule(path: "/Users/me/Hack Club/Public", mode: .singleProject("public-stuff"))))
        #expect(parsed.rules.contains(FolderRule(path: "/Users/me/Secret", mode: .excluded)))
        #expect(parsed.customMapEntries == [RawMapEntry(key: "projects/foo", value: "renamed")])
        #expect(parsed.customExcludes == ["^COMMIT_EDITMSG$"])
    }

    @Test func removingARuleLeavesCustomEntriesAlone() throws {
        let text = """
        [settings]
        exclude =
            ^COMMIT_EDITMSG$
            ^/Users/me/Secret/
        [projectmap]
        ^/Users/me/Work/ = work
        projects/foo = renamed
        """
        let doc = INIDocument(text: text)
        let edits = try ProjectRules.edits(from: doc, to: [])
        #expect(edits.contains(.set(section: "projectmap", key: "^/Users/me/Work/", value: nil)))
        #expect(edits.contains(.settings("exclude", "^COMMIT_EDITMSG$\n")))
        #expect(!edits.contains { if case .set(_, "projects/foo", _) = $0 { return true }; return false })
    }

    @Test func addingAnExclusionAppendsToExistingList() throws {
        let doc = INIDocument(text: "[settings]\nexclude = ^COMMIT_EDITMSG$\n")
        let edits = try ProjectRules.edits(from: doc, to: [FolderRule(path: "/Users/me/Private", mode: .excluded)])
        #expect(edits == [.settings("exclude", "^COMMIT_EDITMSG$\n^/Users/me/Private/")])
    }

    @Test func refusesExcludeTrue() {
        let doc = INIDocument(text: "[settings]\nexclude = true\n")
        #expect(throws: ProjectRulesError.excludeIsTrue) {
            try ProjectRules.edits(from: doc, to: [FolderRule(path: "/x", mode: .excluded)])
        }
    }

    @Test func rejectsPathsTheINIFormatCannotRepresent() {
        #expect(throws: ProjectRulesError.self) {
            try ProjectRules.edits(from: INIDocument(), to: [FolderRule(path: "/a=b", mode: .eachSubfolder)])
        }
        #expect(throws: ProjectRulesError.self) {
            try ProjectRules.edits(from: INIDocument(), to: [FolderRule(path: "/a", mode: .singleProject("x#y"))])
        }
    }
}

@Suite("Project detection preview")
struct ProjectResolverTests {

    func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "tree-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "Container/RepoA/.git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "Container/Plain"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "Container/Named"), withIntermediateDirectories: true)
        try "custom-{project}\n".write(to: root.appending(path: "Container/Named/.wakatime-project"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func priorityOrderMatchesCLI() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appending(path: "Container")
        let doc = INIDocument()

        let repo = ProjectResolver.insight(for: container.appending(path: "RepoA"), document: doc)
        #expect(repo.projectName == "RepoA")
        #expect(repo.isGitRepository)

        let named = ProjectResolver.insight(for: container.appending(path: "Named"), document: doc)
        #expect(named.projectName == "custom-Named", "{project} placeholder is expanded")

        let plain = ProjectResolver.insight(for: container.appending(path: "Plain"), document: doc)
        #expect(plain.projectName == nil)
        #expect(plain.source == .editorWorkspace)
    }

    @Test func projectMapBeatsGitButNotProjectFile() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appending(path: "Container")
        var doc = INIDocument()
        doc.set("{0}-mapped", section: "projectmap", key: "^" + ProjectRules.escape(container.path) + "/([^/]+)/")

        #expect(ProjectResolver.insight(for: container.appending(path: "RepoA"), document: doc).projectName == "RepoA-mapped")
        #expect(ProjectResolver.insight(for: container.appending(path: "Named"), document: doc).projectName == "custom-Named")
    }

    @Test func exclusionsApply() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var doc = INIDocument()
        doc.set(ProjectRules.excludePattern(for: root.appending(path: "Container/Plain").path) + "\n", section: "settings", key: "exclude")
        let insight = ProjectResolver.insight(for: root.appending(path: "Container/Plain"), document: doc)
        if case .excluded = insight.source {} else { Issue.record("expected excluded, got \(insight.source)") }
    }
}
