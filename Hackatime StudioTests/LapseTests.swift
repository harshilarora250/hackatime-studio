import Foundation
import Testing
@testable import Hackatime_Studio

/// Fixtures mirror responses from api.lapse.hackclub.com (hackclub/lapse `packages/api` contracts).
@Suite("Lapse API decoding")
struct LapseTests {

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func userQueryFound() throws {
        let json = """
        {"ok":true,"data":{"user":{"id":"XNSGm_S9_PdL","createdAt":1786943927636,"handle":"frog","displayName":"Frog",
          "profilePictureUrl":"https://example.com/p.png","bio":"","urls":[],"hackatimeId":"54762","slackId":"U0"}}}
        """
        let user = try #require(try decode(LapseEnvelope<LapseUserQuery>.self, json).data?.user)
        #expect(user.id == "XNSGm_S9_PdL")
        #expect(user.hackatimeId == "54762")
        #expect(user.profileURL?.absoluteString == "https://lapse.hackclub.com/user/XNSGm_S9_PdL")
    }

    @Test func userQueryMissing() throws {
        let envelope = try decode(LapseEnvelope<LapseUserQuery>.self, #"{"ok":true,"data":{"user":null}}"#)
        #expect(envelope.ok)
        #expect(envelope.data?.user == nil)
    }

    @Test func errorEnvelope() throws {
        let envelope = try decode(LapseEnvelope<LapseUserQuery>.self, #"{"ok":false,"error":"MISSING_PARAMS","message":"No handle specified"}"#)
        #expect(!envelope.ok)
        #expect(envelope.error == "MISSING_PARAMS")
        #expect(envelope.message == "No handle specified")
    }

    @Test func timelapses() throws {
        let json = """
        {"ok":true,"data":{"timelapses":[
          {"name":"Hud: Framework/v2","description":"d","visibility":"PUBLIC","id":"CVrIeumH-N2y","createdAt":1794985295106,
           "owner":{"id":"x","handle":"h","displayName":"H"},"comments":[],
           "playbackUrl":"https://lookout.hackclub.com/api/media/abc/video.mp4","blocker":null,
           "thumbnailUrl":"https://lookout.hackclub.com/api/media/abc/thumbnail.jpg","duration":202,"isDraft":false},
          {"name":"Processing","visibility":"PUBLIC","id":"p1","createdAt":1794000000000,"playbackUrl":null,"thumbnailUrl":null,
           "duration":0,"blocker":"Shows a password"}
        ]}}
        """
        let list = try #require(try decode(LapseEnvelope<LapseTimelapseList>.self, json).data?.timelapses)
        #expect(list.count == 2)
        let first = list[0]
        #expect(first.createdAt == Date(timeIntervalSince1970: 1794985295.106))
        #expect(first.duration == 202)
        #expect(!first.isProcessing)
        #expect(first.visibility == .public)
        #expect(first.suggestedFilename == "Hud- Framework-v2.mp4")
        #expect(list[1].isProcessing)
        #expect(list[1].blocker == "Shows a password")
        #expect(list[1].description == "")
    }

    @Test @MainActor func recentKeepsOnlyThePastSevenDays() async throws {
        // `recent` filters relative to the fetch time; exercise the same cutoff the store uses.
        let now = Date()
        let items = [0.5, 6.9, 7.1, 30].map { days in
            LapseTimelapse(id: "\(days)", name: "t", createdAt: now.addingTimeInterval(-days * 86_400),
                           duration: 60, playbackURL: nil, thumbnailURL: nil)
        }
        let cutoff = now.addingTimeInterval(-LapseStore.window)
        #expect(items.filter { $0.createdAt >= cutoff }.map(\.id) == ["0.5", "6.9"])
    }
}
