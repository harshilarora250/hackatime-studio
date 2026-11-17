import Foundation
import Testing
@testable import Hackatime_Studio

@Suite("INIDocument parsing")
struct INIDocumentParsingTests {

    let sample = """
    # put this in your ~/.wakatime.cfg file

    [settings]
    api_url = https://hackatime.hackclub.com/api/hackatime/v1
    api_key = waka_00000000-1111-2222-3333-444444444444
    heartbeat_rate_limit_seconds = 30
    exclude =
        ^COMMIT_EDITMSG$
        ^/var/(?!www/).*
    debug = false ; inline comment
    unknown_future_key = keep me

    [projectmap]
    ^/Users/me/Desktop/Hack Club/([^/]+)/ = {0}

    [custom_section]
    whatever = 1

    """

    @Test func readsValues() {
        let doc = INIDocument(text: sample)
        #expect(doc.value(section: "settings", key: "api_url") == "https://hackatime.hackclub.com/api/hackatime/v1")
        #expect(doc.value(section: "settings", key: "heartbeat_rate_limit_seconds") == "30")
        #expect(doc.value(section: "SETTINGS", key: "API_URL") != nil, "lookups are case-insensitive like viper")
        #expect(doc.value(section: "settings", key: "unknown_future_key") == "keep me")
    }

    @Test func readsMultilineValues() {
        let doc = INIDocument(text: sample)
        let entry = doc.entry(section: "settings", key: "exclude")
        #expect(entry?.isMultiline == true)
        #expect(entry?.value == "^COMMIT_EDITMSG$\n^/var/(?!www/).*")
    }

    @Test func stripsInlineCommentsLikeGoINI() {
        let doc = INIDocument(text: sample)
        #expect(doc.value(section: "settings", key: "debug") == "false")
        #expect(doc.entry(section: "settings", key: "debug")?.inlineComment == "; inline comment")
    }

    @Test func roundTripsByteForByte() {
        let doc = INIDocument(text: sample)
        #expect(doc.serialized() == sample)
    }

    @Test func roundTripsCRLFAndMissingTrailingNewline() {
        let text = "[settings]\r\napi_key = abc\r\ndebug = true"
        #expect(INIDocument(text: text).serialized() == text)
    }

    @Test func projectMapKeysWithSpacesAndRegex() {
        let doc = INIDocument(text: sample)
        let entries = doc.effectiveEntries(in: "projectmap")
        #expect(entries.count == 1)
        #expect(entries.first?.key == "^/Users/me/Desktop/Hack Club/([^/]+)/")
        #expect(entries.first?.value == "{0}")
    }

    @Test func colonIsAlsoADelimiter() {
        let doc = INIDocument(text: "[settings]\nhostname: my-mac\n")
        #expect(doc.value(section: "settings", key: "hostname") == "my-mac")
    }

    @Test func duplicateKeysLastWinsAndIsReported() {
        let doc = INIDocument(text: "[settings]\ndebug = true\ndebug = false\n")
        #expect(doc.value(section: "settings", key: "debug") == "false")
        #expect(doc.issues.contains { $0.message.contains("more than once") })
    }

    @Test func invalidLinesArePreservedAndReported() {
        let text = "[settings]\nthis line has no delimiter\n[broken\napi_key = x\n"
        let doc = INIDocument(text: text)
        #expect(doc.serialized() == text)
        #expect(doc.issues.filter { $0.severity == .error }.count == 1)
        #expect(doc.issues.filter { $0.severity == .warning }.count == 1)
    }

    @Test func issuesNeverContainAPIKeys() {
        let text = "[settings]\nwaka_00000000-1111-2222-3333-444444444444\n"
        let doc = INIDocument(text: text)
        #expect(!doc.issues.contains { $0.message.contains("444444444444") })
    }

    @Test func emptyDocument() {
        let doc = INIDocument(text: "")
        #expect(doc.lines.isEmpty)
        #expect(doc.serialized() == "")
    }
}

@Suite("INIDocument editing")
struct INIDocumentEditingTests {

    @Test func replacingAValueOnlyTouchesThatLine() {
        let text = "# header\n[settings]\napi_key = old\n\n# keep\ndebug = false\n"
        var doc = INIDocument(text: text)
        doc.set("new", section: "settings", key: "api_key")
        #expect(doc.serialized() == "# header\n[settings]\napi_key = new\n\n# keep\ndebug = false\n")
    }

    @Test func preservesOriginalKeySpelling() {
        var doc = INIDocument(text: "[Settings]\nAPI_URL=old\n")
        doc.set("https://x", section: "settings", key: "api_url")
        #expect(doc.serialized() == "[Settings]\nAPI_URL = https://x\n")
    }

    @Test func appendsNewKeyToEndOfExistingSectionBeforeBlankLines() {
        var doc = INIDocument(text: "[settings]\napi_key = k\n\n[git]\nsubmodules_disabled = false\n")
        doc.set("true", section: "settings", key: "debug")
        #expect(doc.serialized() == "[settings]\napi_key = k\ndebug = true\n\n[git]\nsubmodules_disabled = false\n")
    }

    @Test func createsMissingSection() {
        var doc = INIDocument(text: "[settings]\napi_key = k\n")
        doc.set("true", section: "git", key: "project_from_git_remote")
        #expect(doc.serialized() == "[settings]\napi_key = k\n\n[git]\nproject_from_git_remote = true\n")
    }

    @Test func createsFileFromScratch() {
        var doc = INIDocument()
        doc.set("https://hackatime.hackclub.com/api/hackatime/v1", section: "settings", key: "api_url")
        doc.set("abc", section: "settings", key: "api_key")
        #expect(doc.serialized() == "[settings]\napi_url = https://hackatime.hackclub.com/api/hackatime/v1\napi_key = abc\n")
    }

    @Test func writesMultilineLists() {
        var doc = INIDocument(text: "[settings]\nexclude = ^/tmp/\ndebug = false\n")
        doc.set("^/tmp/\n^/private/", section: "settings", key: "exclude")
        #expect(doc.serialized() == "[settings]\nexclude =\n    ^/tmp/\n    ^/private/\ndebug = false\n")
        let reparsed = INIDocument(text: doc.serialized())
        #expect(reparsed.value(section: "settings", key: "exclude") == "^/tmp/\n^/private/")
        #expect(reparsed.value(section: "settings", key: "debug") == "false")
    }

    @Test func removingAKeyRemovesContinuationLines() {
        var doc = INIDocument(text: "[settings]\nexclude =\n    a\n    b\ndebug = true\n")
        doc.remove(section: "settings", key: "exclude")
        #expect(doc.serialized() == "[settings]\ndebug = true\n")
    }

    @Test func unknownKeysAndSectionsSurviveEdits() {
        let text = "[settings]\nfuture_option = 42\n[weird]\nx = y\n"
        var doc = INIDocument(text: text)
        doc.set("true", section: "settings", key: "debug")
        let out = doc.serialized()
        #expect(out.contains("future_option = 42"))
        #expect(out.contains("[weird]\nx = y"))
    }

    @Test func settingSameValueIsANoOp() {
        let text = "[settings]\napi_key=abc\n"
        var doc = INIDocument(text: text)
        doc.set("abc", section: "settings", key: "api_key")
        #expect(doc.serialized() == text)
    }
}
