import Foundation
import Testing
@testable import Hackatime_Studio

/// Fixtures mirror the JSON produced by hackclub/hackatime controllers
/// (hackatime_controller.rb, stats_controller.rb, my/heartbeats_controller.rb).
@Suite("Hackatime API decoding")
struct APIModelTests {

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func statusBarTodayWithGoal() throws {
        let json = """
        {"data":{"grand_total":{"text":"2 hrs 5 mins","total_seconds":7512.0},
         "goal":{"target_seconds":7200,"tracked_seconds":7512,"completion_percent":100,"complete":true}}}
        """
        let today = try decode(DataEnvelope<StatusBarToday>.self, json).data
        #expect(today.todaySeconds == 7512)
        #expect(today.goal?.targetSeconds?.value == 7200)
        #expect(today.goal?.complete == true)
    }

    @Test func statusBarTodayWithoutGoal() throws {
        let today = try decode(DataEnvelope<StatusBarToday>.self, #"{"data":{"grand_total":{"text":"0 mins","total_seconds":0}}}"#).data
        #expect(today.goal == nil)
        #expect(today.todaySeconds == 0)
    }

    @Test func summaries() throws {
        let json = """
        {"data":[{"grand_total":{"hours":1,"minutes":0,"total_seconds":3600,"digital":"1:00","text":"1 hr"},
          "branches":[],"categories":[],"dependencies":[],"editors":[],"entities":[],"languages":[],"machines":[],"operating_systems":[],
          "projects":[{"name":"hackatime","total_seconds":3600,"percent":100.0,"text":"1 hr"}],
          "range":{"date":"2026-11-16","start":"2026-11-16T05:00:00Z","end":"2026-11-17T04:59:59Z","text":"Mon Nov 16th 2026","timezone":"America/New_York"}},
          {"grand_total":{"total_seconds":0},"projects":[],"range":{"date":"2026-11-17"}}],
         "cumulative_total":{"seconds":3600},"daily_average":{"seconds":1800},"start":"2026-11-16","end":"2026-11-17"}
        """
        let days = try decode(SummariesResponse.self, json).data
        #expect(days.count == 2)
        #expect(days[0].seconds == 3600)
        #expect(days[0].projects?.first?.name == "hackatime")
        #expect(days[1].id == "2026-11-17")
    }

    @Test func userStats() throws {
        let json = """
        {"data":{"username":"me","user_id":"1","total_seconds":5400,"daily_average":100,
          "languages":[{"name":"Swift","total_seconds":3600,"text":"1h","hours":1,"minutes":0,"percent":66.67,"digital":"1:00","color":"#F05138"}],
          "projects":[{"name":"studio","total_seconds":5400,"percent":100}],
          "streak":12},
         "trust_factor":{"trust_level":"green","trust_value":1}}
        """
        let stats = try decode(DataEnvelope<UserStats>.self, json).data
        #expect(stats.streak == 12)
        #expect(stats.languages.first?.color == "#F05138")
        #expect(stats.projects.first?.totalSeconds == 5400)
    }

    @Test func userStatsWithMissingFeatures() throws {
        let stats = try decode(DataEnvelope<UserStats>.self, #"{"data":{"total_seconds":0}}"#).data
        #expect(stats.languages.isEmpty)
        #expect(stats.streak == nil)
    }

    @Test func mostRecentHeartbeat() throws {
        let json = """
        {"has_heartbeat":true,"heartbeat":{"id":5,"time":1763400000.5,"project":"studio","language":"Swift","editor":"vscode","entity":"/x.swift"},
         "editor":"vscode","time_ago":"3 minutes ago"}
        """
        let r = try decode(MostRecentHeartbeatResponse.self, json)
        #expect(r.hasHeartbeat)
        #expect(r.heartbeat?.project == "studio")
        #expect(r.heartbeat?.time == Date(timeIntervalSince1970: 1763400000.5))
    }

    @Test func noHeartbeat() throws {
        let r = try decode(MostRecentHeartbeatResponse.self, #"{"has_heartbeat":false,"heartbeat":null,"editor":null,"time_ago":null}"#)
        #expect(!r.hasHeartbeat)
        #expect(r.heartbeat == nil)
    }

    @Test func spans() throws {
        let r = try decode(SpansResponse.self, #"{"spans":[{"start_time":1763400000.0,"end_time":1763401800.0,"duration":1800.0}]}"#)
        #expect(r.spans.first?.duration == 1800)
    }

    @Test func endpointsDeriveFromAPIURL() throws {
        let e = try #require(HackatimeEndpoints(apiURL: "https://hackatime.hackclub.com/api/hackatime/v1/"))
        #expect(e.root.absoluteString == "https://hackatime.hackclub.com")
        #expect(e.compatBase.absoluteString == "https://hackatime.hackclub.com/api/hackatime/v1")
        #expect(e.isOfficialHackatime)
        let selfHosted = try #require(HackatimeEndpoints(apiURL: "http://localhost:3000/api/hackatime/v1"))
        #expect(selfHosted.root.absoluteString == "http://localhost:3000")
        #expect(HackatimeEndpoints(apiURL: "not a url") == nil)
        #expect(HackatimeEndpoints(apiURL: "https://api.wakatime.com/api/v1")?.looksLikeWakaTime == true)
    }

    @Test func clientRejectsEmptyKey() {
        #expect(throws: HackatimeAPIError.noAPIKey) {
            _ = try HackatimeClient(apiURL: ConfigSchema.hackatimeAPIURL, apiKey: "  ")
        }
    }

    @Test func errorMessagesNeverIncludeKeys() {
        let all: [HackatimeAPIError] = [.unauthorized, .forbidden("x"), .notFound("/a"), .server(500), .network("boom"), .decoding("T")]
        for e in all { #expect(!(e.errorDescription ?? "").contains("waka_")) }
    }
}

@Suite("Redaction")
struct RedactionTests {
    @Test func masks() {
        #expect(Redaction.mask("waka_12345678-aaaa-bbbb-cccc-1234567890ab") == "waka_••••••••90ab")
        #expect(Redaction.mask("abc") == "••••")
        #expect(Redaction.mask("") == "")
    }

    @Test func redactsSecretsInText() {
        let line = "api_key = 12345678-aaaa-bbbb-cccc-1234567890ab and Bearer xyz123 and https://w.example/api|secretkey"
        let out = Redaction.redactSecrets(in: line)
        #expect(!out.contains("1234567890ab"))
        #expect(!out.contains("xyz123"))
        #expect(!out.contains("secretkey"))
    }
}
