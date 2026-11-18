import Foundation
import Testing
@testable import Avida

private let day0 = Date(timeIntervalSince1970: 1_780_272_000)  // 2026-06-01 UTC
private let kyoto = City(name: "Kyoto", countryCode: "JP", latitude: 35.01, longitude: 135.77, population: 1)
private let temple = Landmark(qid: "Q1", name: "Kiyomizu-dera", description: "Buddhist temple", type: "Buddhist temple",
                              latitude: 34.99, longitude: 135.78, sitelinks: 77)

private func experience(_ id: String, hours: Double = 0, landmark: Landmark? = temple) -> Experience {
    let start = day0.addingTimeInterval(hours * 3600)
    let moment = Moment(id: "PHOTO-\(id)/L0/001", photoIDs: ["PHOTO-\(id)/L0/001", "PHOTO-\(id)/L0/002"],
                        representativeIDs: ["PHOTO-\(id)/L0/001"], start: start, end: start.addingTimeInterval(7200),
                        latitude: 34.99, longitude: 135.78, distanceFromHomeMeters: 10_800_000, city: kyoto, landmark: landmark)
    return Experiences.make(id: "trip-PHOTO-\(id)", kind: .trip, moments: [moment], tags: { _ in .empty })
}

/// Claude's reply in Messages API shape, with `json` as the text.
private func reply(_ json: String, stop: String = "end_turn") -> String {
    let text = String(data: try! JSONEncoder().encode(json), encoding: .utf8)!
    return #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"# + text + #"}],"stop_reason":""# + stop + #""}"#
}

/// Returns scripted replies and keeps every request body.
private actor TitleTransport: LLMTransport {
    private var replies: [String]
    private(set) var bodies: [JSONValue] = []

    init(_ replies: [String]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        bodies.append(try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data()))
        let body = replies.isEmpty ? reply("{}") : replies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

struct AITitlesParsingTests {
    private let keys = ["e1": "trip-a", "e2": "trip-b", "e3": "trip-c"]

    private func parse(_ json: String, stop: String = "end_turn") throws -> [String: AITitle] {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(reply(json, stop: stop).utf8))
        return AITitles.parse(reply: value, keys: keys, date: day0)
    }

    @Test func validReplyMapsBackToExperienceIDs() throws {
        let titles = try parse(#"{"experiences":[{"id":"e1","title":"Dawn on Kiyomizu-dera's wooden stage","memorability":9},{"id":"e2","title":"A slow lap of Central Park","memorability":4}]}"#)
        #expect(titles["trip-a"]?.title == "Dawn on Kiyomizu-dera's wooden stage")
        #expect(titles["trip-a"]?.memorability == 9)
        #expect(titles["trip-b"]?.memorability == 4)
        #expect(titles["trip-c"] == nil)  // not returned → keeps the template
    }

    @Test func invalidEntriesAreDroppedOneByOne() throws {
        let tooLong = String(repeating: "x", count: 46)
        let titles = try parse("""
        {"experiences":[
          {"id":"e1","title":"Fine title","memorability":11},
          {"id":"e2","title":"\(tooLong)","memorability":5},
          {"id":"e9","title":"Unknown id","memorability":5},
          {"id":"e3","title":"  Kept, trimmed  ","memorability":1},
          {"id":"e3","title":"Duplicate is ignored","memorability":2}
        ]}
        """)
        #expect(titles.keys.sorted() == ["trip-c"])
        #expect(titles["trip-c"]?.title == "Kept, trimmed")
    }

    @Test func titlesOver45CharactersKeepTheTemplate() throws {
        let fortyFive = "Climbed to Kiyomizu-dera Before the Crowds Ca"  // exactly 45
        #expect(fortyFive.count == 45)
        let titles = try parse("""
        {"experiences":[
          {"id":"e1","title":"\(fortyFive)","memorability":7},
          {"id":"e2","title":"Walked the Lantern-Lit Lanes of Old Kyoto at Night","memorability":7},
          {"id":"e3","title":"Swam Beside Whale Sharks","memorability":9}
        ]}
        """)
        #expect(titles["trip-a"]?.title == fortyFive)
        #expect(titles["trip-b"] == nil)  // over 45 characters → template kept
        #expect(titles["trip-c"]?.title == "Swam Beside Whale Sharks")
    }

    @Test func promptAsksForShortTitleCaseWithExamples() {
        let prompt = AITitles.systemPrompt
        #expect(prompt.contains("25–45 characters"))
        #expect(prompt.contains("Title Case"))
        for example in ["Slept Under the Northern Lights", "Dinner with a New York Legend", "Swam Beside Whale Sharks"] {
            #expect(prompt.contains(example))
            // Only the upper bound is enforced; "Swam Beside Whale Sharks" is 24, just under the 25 asked for.
            #expect(example.count <= 45, "example \(example) is \(example.count) characters")
        }
    }

    @Test func unusableRepliesKeepAllTemplates() throws {
        #expect(try parse("not json at all").isEmpty)
        #expect(try parse(#"{"titles":[]}"#).isEmpty)
        #expect(try parse(#"{"experiences":[{"id":"e1","title":"Cut off","memorability":5}]}"#, stop: "max_tokens").isEmpty)
    }

    @Test func detailedParseExplainsRejections() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(reply(#"{"experiences":[{"id":"e1","title":"Fine Title Here","memorability":0},{"id":"e7","title":"Unknown","memorability":5}]}"#).utf8))
        let parsed = AITitles.parseDetailed(reply: value, keys: keys, date: day0)
        #expect(parsed.titles.isEmpty)
        #expect(parsed.problem == nil)
        #expect(parsed.rejected == ["memorability not 1–10": 1, "unknown id": 1])

        let cut = try JSONDecoder().decode(JSONValue.self, from: Data(reply("{", stop: "max_tokens").utf8))
        #expect(AITitles.parseDetailed(reply: cut, keys: keys, date: day0).problem == "Reply was cut off (max_tokens).")
    }

    @Test func codeFencesAreTolerated() throws {
        let titles = try parse("```json\n{\"experiences\":[{\"id\":\"e1\",\"title\":\"Fenced\",\"memorability\":6}]}\n```")
        #expect(titles["trip-a"]?.title == "Fenced")
    }

    @Test func requestIsOneTextOnlyMessageWithASchema() throws {
        let request = AITitles.request(for: [experience("a"), experience("b", hours: 48)])
        #expect(request.keys == ["e1": "trip-PHOTO-a", "e2": "trip-PHOTO-b"])
        let body = request.body
        #expect(body["model"]?.stringValue == "claude-haiku-5-5")
        #expect(body["output_config"]?["format"]?["type"]?.stringValue == "json_schema")
        #expect(body["messages"]?.arrayValue?.count == 1)
        let text = body.compactJSON
        #expect(text.contains("Kiyomizu-dera"))
        #expect(text.contains("Kyoto"))
        for forbidden in ["PHOTO-", "34.99", "135.78", ".jpg"] {
            #expect(!text.contains(forbidden), "request leaked \(forbidden)")
        }
    }
}

@MainActor
struct AITitleWriterTests {
    private let config = LLMConfig(proxyURL: URL(string: "https://proxy.example/v1/messages")!, appToken: "t")

    private func writer(transport: TitleTransport, batchSize: Int = 40) -> AITitleWriter {
        AITitleWriter(client: LLMClient(config: config, transport: transport, log: LLMRequestLog()), batchSize: batchSize)
    }

    @Test func largeAlbumsAreSentInBatchesThatFitTheProxy() async throws {
        let experiences = (0..<5).map { experience("x\($0)", hours: Double($0) * 48) }
        let transport = TitleTransport([
            reply(#"{"experiences":[{"id":"e1","title":"First Light at Kiyomizu-dera","memorability":8},{"id":"e2","title":"Lanterns on the Old Stone Lanes","memorability":6}]}"#),
            reply(#"{"experiences":[{"id":"e1","title":"Climbed to the Wooden Stage","memorability":7}]}"#),
            reply(#"{"experiences":[{"id":"e1","title":"A Very Long Title That Goes On and On and On Forever","memorability":5}]}"#),
        ])
        let result = await writer(transport: transport, batchSize: 2).titles(for: experiences, existing: [:], now: day0)
        let bodies = await transport.bodies
        #expect(bodies.count == 3)  // 2 + 2 + 1
        for body in bodies {
            #expect((body["max_tokens"]?.intValue ?? 0) <= 4096)
            #expect(body["stream"] == nil)
            #expect(body["model"]?.stringValue == "claude-haiku-5-5")
            #expect(try JSONEncoder().encode(body).count < 64 * 1024)
        }
        #expect(result.titles.count == 3)
        #expect(result.titles["trip-PHOTO-x2"]?.title == "Climbed to the Wooden Stage")  // e1 of the 2nd batch
        #expect(result.run.requested == 5)
        #expect(result.run.requests == 3)
        #expect(result.run.rejected == ["over 45 characters": 1])
        #expect(result.run.error == nil)
        #expect(result.run.summary.contains("3 of 5 titled in 3 requests"))
    }

    @Test func onlyTheTop60ByWorthinessAreTitledInBatchesOf20() async throws {
        // 100 experiences with rising worthiness (more photos each), realistic place and landmark text.
        let experiences: [Experience] = (0..<100).map { index in
            let start = day0.addingTimeInterval(Double(index) * 86_400)
            let ids = (0...index).map { "PHOTO-\(index)-\($0)" }
            let moment = Moment(id: "m\(index)", photoIDs: ids, representativeIDs: Array(ids.prefix(5)), start: start,
                                end: start.addingTimeInterval(7200), latitude: 34.99, longitude: 135.78,
                                distanceFromHomeMeters: 10_800_000, city: kyoto, landmark: temple)
            return Experiences.make(id: "x\(index)", kind: .trip, moments: [moment], tags: { _ in .empty })
        }
        let transport = TitleTransport((0..<3).map { _ in
            reply(#"{"experiences":[{"id":"e1","title":"First Light at Kiyomizu-dera","memorability":8}]}"#)
        })
        let result = await AITitleWriter(client: LLMClient(config: config, transport: transport, log: LLMRequestLog()))
            .titles(for: experiences.shuffled(), existing: ["x99": AITitle(title: "Saved", memorability: 9, date: day0)], now: day0)

        let bodies = await transport.bodies
        #expect(bodies.count == 3)               // 59 missing among the top 60 → 20 + 20 + 19
        #expect(result.run.requested == 59)      // x99 already had a title
        var sentKeys = 0
        for body in bodies {
            #expect(body["max_tokens"]?.intValue == 2000)
            #expect(try JSONEncoder().encode(body).count < 16 * 1024)  // far under the proxy's 64 KB
            let content = try #require(body["messages"]?.arrayValue?.first?["content"]?.stringValue)
            sentKeys += content.components(separatedBy: "\"id\":").count - 1
        }
        #expect(sentKeys == 59)
        // Each batch's e1 is that batch's most worthy experience: x98, x78, x58. x0…x39 are never sent.
        #expect(Set(result.titles.keys) == ["x98", "x78", "x58"])
    }

    @Test func proxyErrorsAreReportedAndStopTheRun() async {
        let error = #"{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens must be between 1 and 4096."}}"#
        let transport = ErrorTransport(body: error, status: 400)
        let writer = AITitleWriter(client: LLMClient(config: config, transport: transport, log: LLMRequestLog()), batchSize: 1)
        let result = await writer.titles(for: [experience("a"), experience("b", hours: 48)], existing: [:])
        #expect(result.titles.isEmpty)
        #expect(await transport.count == 1)  // didn't hammer the proxy with the same failing request
        #expect(result.run.error?.contains("max_tokens must be between 1 and 4096") == true)
    }

    @Test func asksOnceForOnlyTheNewExperiences() async throws {
        let transport = TitleTransport([reply(#"{"experiences":[{"id":"e1","title":"First light at Kiyomizu-dera","memorability":8}]}"#)])
        let saved = ["trip-PHOTO-a": AITitle(title: "Old", memorability: 5, date: day0)]
        let result = await writer(transport: transport)
            .titles(for: [experience("a"), experience("b", hours: 48)], existing: saved, now: day0)
        let new = result.titles

        let bodies = await transport.bodies
        #expect(bodies.count == 1)
        let content = try #require(bodies[0]["messages"]?.arrayValue?.first?["content"]?.stringValue)
        #expect(content.contains("\"e1\""))
        #expect(!content.contains("\"e2\""))  // only b was sent, as e1
        #expect(new == ["trip-PHOTO-b": AITitle(title: "First light at Kiyomizu-dera", memorability: 8, date: day0)])
    }

    @Test func nothingIsSentWhenAllHaveTitles() async {
        let transport = TitleTransport([])
        let saved = ["trip-PHOTO-a": AITitle(title: "Old", memorability: 5, date: day0)]
        let result = await writer(transport: transport).titles(for: [experience("a")], existing: saved)
        #expect(result.titles.isEmpty)
        #expect(result.run.requested == 0)
        #expect(await transport.bodies.isEmpty)
    }

    @Test func badReplyKeepsTemplates() async {
        let transport = TitleTransport([reply("Sorry, here you go: titles!")])
        let result = await writer(transport: transport).titles(for: [experience("a")], existing: [:])
        #expect(result.titles.isEmpty)
        #expect(result.run.error?.hasPrefix("Reply wasn't JSON") == true)
        #expect(await transport.bodies.count == 1)
    }

    @Test func storeSavesAndReloads() throws {
        let url = URL.temporaryDirectory.appending(path: "ai-titles-\(UUID().uuidString).json")
        let store = AITitleStore(fileURL: url)
        store.merge(["trip-x": AITitle(title: "Saved", memorability: 7, date: day0)])
        #expect(AITitleStore(fileURL: url).entries["trip-x"]?.title == "Saved")
        store.reset()
        #expect(AITitleStore(fileURL: url).entries.isEmpty)
    }
}

/// Always answers with the same HTTP error.
private actor ErrorTransport: LLMTransport {
    let body: String
    let status: Int
    private(set) var count = 0

    init(body: String, status: Int) {
        self.body = body
        self.status = status
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        count += 1
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
