import Foundation
import Testing
@testable import Avida

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private let english = Locale(identifier: "en_US")
private let april2026 = Date(timeIntervalSince1970: 1_775_001_600)  // 2026-04-01 00:00 UTC

private func record(
    _ id: String, title: String, place: String, country: String?, year: Int = 2026, categories: [String],
    landmarks: [String] = [], score: Double, rarity: Double, stops: [ExperienceRecord.Stop] = []
) -> ExperienceRecord {
    let start = utc.date(from: DateComponents(year: year, month: 4, day: 3))!
    return ExperienceRecord(id: id, source: .photos("trip-\(id)"), kind: "trip", title: title, place: place, country: country,
                            start: start, end: start.addingTimeInterval(2 * 86_400), categories: categories,
                            landmarks: landmarks, photoCount: 12, score: score, rarity: rarity, stops: stops)
}

private let records = [
    record("e1", title: "Exploring Kyoto", place: "Kyoto", country: "Japan", categories: ["Culture", "Nature"],
           landmarks: ["Kiyomizu-dera"], score: 0.9, rarity: 185,
           stops: [.init(name: "Kiyomizu-dera", description: "Buddhist temple in Kyoto", city: "Kyoto", duration: "~2 hrs")]),
    record("e2", title: "Vessel & Central Park", place: "Manhattan", country: "United States", year: 2025,
           categories: ["City", "Nature"], landmarks: ["Vessel", "Central Park"], score: 0.4, rarity: 87),
    record("e3", title: "Exploring Goa", place: "Panaji", country: "India", year: 2025, categories: ["Coast"],
           landmarks: ["Basilica of Bom Jesus"], score: 0.7, rarity: 150),
]

private let tools = ExperienceTools(records: records, calendar: utc, locale: english)

private func object(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private func ids(_ result: ExperienceTools.Result, key: String = "experiences") throws -> [String] {
    try object(result.json)[key]?.arrayValue?.compactMap { $0["id"]?.stringValue } ?? []
}

struct ExperienceToolsTests {
    @Test func searchFiltersCombineAndRankByScore() throws {
        #expect(try ids(tools.run(name: "search_experiences", input: .object([:]))) == ["e1", "e3", "e2"])
        #expect(try ids(tools.run(name: "search_experiences", input: .object(["city": .string("kyoto")]))) == ["e1"])
        #expect(try ids(tools.run(name: "search_experiences", input: .object(["country": .string("JP")]))) == ["e1"])
        #expect(try ids(tools.run(name: "search_experiences", input: .object(["country": .string("india")]))) == ["e3"])
        #expect(try ids(tools.run(name: "search_experiences", input: .object(["year": .number(2025)]))) == ["e3", "e2"])
        #expect(try ids(tools.run(name: "search_experiences", input: .object(["category": .string("nature")]))) == ["e1", "e2"])
        #expect(try ids(tools.run(name: "search_experiences", input: .object(["text": .string("temple")]))) == ["e1"])
        #expect(try ids(tools.run(name: "search_experiences",
                                  input: .object(["category": .string("Nature"), "year": .number(2025)]))) == ["e2"])
    }

    @Test func searchReturnsTheAgreedFields() throws {
        let result = tools.run(name: "search_experiences", input: .object(["city": .string("Kyoto")]))
        let first = try #require(try object(result.json)["experiences"]?.arrayValue?.first)
        #expect(first["title"]?.stringValue == "Exploring Kyoto")
        #expect(first["place"]?.stringValue == "Kyoto")
        #expect(first["country"]?.stringValue == "Japan")
        #expect(first["when"]?.stringValue == "Apr 2026")
        #expect(first["categories"] == .array([.string("Culture"), .string("Nature")]))
        #expect(first["landmarks"] == .array([.string("Kiyomizu-dera")]))
        #expect(first["photos"]?.intValue == 12)
        #expect(first["score"]?.intValue == 90)  // rank score 0.9, reported 0–100
    }

    @Test func getExperienceIncludesStops() throws {
        let result = tools.run(name: "get_experience", input: .object(["id": .string("e1")]))
        #expect(!result.isError)
        let stop = try #require(try object(result.json)["stops"]?.arrayValue?.first)
        #expect(stop == .object(["name": .string("Kiyomizu-dera"), "description": .string("Buddhist temple in Kyoto"),
                                 "city": .string("Kyoto"), "duration": .string("~2 hrs")]))
        #expect(try object(result.json)["dates"]?.stringValue == "Apr 3, 2026 – Apr 5, 2026")

        let missing = tools.run(name: "get_experience", input: .object(["id": .string("e99")]))
        #expect(missing.isError)
    }

    @Test func statsCountByGroup() throws {
        let byYear = try object(tools.run(name: "stats", input: .object(["group_by": .string("year")])).json)
        #expect(byYear["counts"] == .array([
            .object(["key": .string("2025"), "count": .number(2)]),
            .object(["key": .string("2026"), "count": .number(1)]),
        ]))
        let byCategory = try object(tools.run(name: "stats", input: .object(["group_by": .string("category")])).json)
        #expect(byCategory["total"]?.intValue == 3)
        #expect(tools.run(name: "stats", input: .object(["group_by": .string("people")])).isError)
    }

    @Test func topByScoreAndRarityDiffer() throws {
        #expect(try ids(tools.run(name: "top_experiences", input: .object(["n": .number(2), "by": .string("score")]))) == ["e1", "e3"])
        #expect(try ids(tools.run(name: "top_experiences", input: .object(["n": .number(3), "by": .string("rarity")]))) == ["e1", "e3", "e2"])
        #expect(try ids(tools.run(name: "top_experiences", input: .object(["n": .number(50), "by": .string("score")]))).count == 3)
    }

    @Test func unknownToolIsAnError() {
        #expect(tools.run(name: "delete_everything", input: .object([:])).isError)
    }

    @Test func snapshotUsesShortIdsAndNoPhotoData() throws {
        let city = City(name: "Kyoto", countryCode: "JP", latitude: 35, longitude: 135.7, population: 1)
        let temple = Landmark(qid: "Q1", name: "Kiyomizu-dera", description: "Buddhist temple", type: "Buddhist temple",
                              latitude: 34.99, longitude: 135.78, sitelinks: 77)
        let moment = Moment(id: "PHOTO-ABC/L0/001", photoIDs: ["PHOTO-ABC/L0/001", "PHOTO-DEF/L0/001"],
                            representativeIDs: ["PHOTO-ABC/L0/001"], start: april2026, end: april2026.addingTimeInterval(3600),
                            latitude: 34.99, longitude: 135.78, distanceFromHomeMeters: 10_800_000, city: city, landmark: temple)
        let experience = Experiences.make(id: "trip-PHOTO-ABC/L0/001", kind: .trip, moments: [moment], tags: { _ in .empty })
        let verified = VerifiedExperience(id: UUID(), offerID: "kiyomizu-climb", title: "Climb to Kiyomizu-dera",
                                          partner: "Kansai Rail Club", rewardAmount: 500, rewardUnit: "Rail Points",
                                          category: .culture, place: "Kyoto", date: april2026, latitude: 34.99,
                                          longitude: 135.78, distanceMeters: 20, photoFileName: "SECRET-PHOTO.jpg")
        let snapshot = ExperienceTools.snapshot(experiences: [experience], verified: [verified], calendar: utc, locale: english)
        #expect(snapshot.map(\.id) == ["e1", "e2"])
        #expect(snapshot[0].country == "Japan")
        // Only experience in Japan (+2) + 0.5 × ln(1 + 10,800 km) + 0.5 × (log10(10M) − log10(population 1))
        #expect(abs(snapshot[0].rarity - (2 + 0.5 * log1p(10_800) + 0.5 * 7)) < 1e-9)

        let snapshotTools = ExperienceTools(records: snapshot, calendar: utc, locale: english)
        let outputs = [
            snapshotTools.run(name: "search_experiences", input: .object([:])).json,
            snapshotTools.run(name: "get_experience", input: .object(["id": .string("e1")])).json,
            snapshotTools.run(name: "get_experience", input: .object(["id": .string("e2")])).json,
            snapshotTools.run(name: "top_experiences", input: .object(["n": .number(5), "by": .string("rarity")])).json,
        ].joined()
        for forbidden in ["PHOTO-", ".jpg", "34.99", "135.78", "file:"] {
            #expect(!outputs.contains(forbidden), "tool output leaked \(forbidden)")
        }
    }
}

// MARK: Agent loop

/// Returns scripted replies in order and keeps every request body.
private actor ScriptedTransport: LLMTransport {
    private var replies: [String]
    private(set) var bodies: [JSONValue] = []

    init(_ replies: [String]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        bodies.append(try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data()))
        let reply = replies.isEmpty ? #"{"content":[{"type":"text","text":"(script ended)"}],"stop_reason":"end_turn"}"# : replies.removeFirst()
        return (Data(reply.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private let toolUseReply = #"""
{"content":[{"type":"thinking","thinking":"","signature":"sig-123"},{"type":"tool_use","id":"toolu_1","name":"search_experiences","input":{"city":"Kyoto"}}],"stop_reason":"tool_use"}
"""#
private let finalReply = #"{"content":[{"type":"text","text":"Your trip [e1] was your most memorable."}],"stop_reason":"end_turn"}"#

@MainActor
struct AskAgentTests {
    private let config = LLMConfig(proxyURL: URL(string: "https://proxy.example/v1/messages")!, appToken: "t")

    private func client(transport: ScriptedTransport, log: LLMRequestLog? = nil) -> LLMClient {
        LLMClient(config: config, transport: transport, log: log ?? LLMRequestLog())
    }

    @Test func runsToolLocallyAndReturnsFinalAnswer() async throws {
        let transport = ScriptedTransport([toolUseReply, finalReply])
        let answer = try await AskAgent(client: client(transport: transport), tools: tools).ask("What was my best trip?")
        #expect(answer.text == "Your trip [e1] was your most memorable.")
        #expect(answer.toolsUsed == ["search_experiences"])
        #expect(answer.hitRoundLimit == false)

        let bodies = await transport.bodies
        #expect(bodies.count == 2)
        let first = bodies[0]
        #expect(first["model"]?.stringValue == "claude-haiku-5-5")
        #expect(first["system"]?.stringValue == AskAgent.systemPrompt)
        #expect(first["tools"] == ExperienceTools.definitions)
        #expect(first["tool_choice"] == nil)

        let messages = try #require(bodies[1]["messages"]?.arrayValue)
        #expect(messages.count == 3)
        // The assistant turn is echoed exactly, thinking block and signature included.
        let original = try object(toolUseReply)["content"]
        #expect(messages[1] == .object(["role": .string("assistant"), "content": original!]))
        let result = try #require(messages[2]["content"]?.arrayValue?.first)
        #expect(result["type"]?.stringValue == "tool_result")
        #expect(result["tool_use_id"]?.stringValue == "toolu_1")
        #expect(result["content"]?.stringValue?.contains("Exploring Kyoto") == true)
        #expect(result["is_error"] == nil)
    }

    @Test func stopsAfterFiveToolRoundsAndForcesAnAnswer() async throws {
        let transport = ScriptedTransport(Array(repeating: toolUseReply, count: 5) + [finalReply])
        let answer = try await AskAgent(client: client(transport: transport), tools: tools).ask("Tell me everything")
        #expect(answer.hitRoundLimit)
        #expect(answer.toolsUsed.count == 5)

        let bodies = await transport.bodies
        #expect(bodies.count == 6)
        #expect(bodies[4]["tool_choice"] == nil)
        #expect(bodies[5]["tool_choice"] == .object(["type": .string("none")]))
        let lastUserTurn = try #require(bodies[5]["messages"]?.arrayValue?.last?["content"]?.arrayValue)
        #expect(lastUserTurn.last?["type"]?.stringValue == "text")
    }

    @Test func unknownToolCallComesBackAsError() async throws {
        let badCall = #"{"content":[{"type":"tool_use","id":"toolu_9","name":"read_photos","input":{}}],"stop_reason":"tool_use"}"#
        let transport = ScriptedTransport([badCall, finalReply])
        _ = try await AskAgent(client: client(transport: transport), tools: tools).ask("Show me my photos")
        let result = try #require(await transport.bodies[1]["messages"]?.arrayValue?.last?["content"]?.arrayValue?.first)
        #expect(result["is_error"] == .bool(true))
    }

    @Test func requestLogHoldsTheExactLastBody() async throws {
        let log = LLMRequestLog()
        let transport = ScriptedTransport([toolUseReply, finalReply])
        _ = try await AskAgent(client: client(transport: transport, log: log), tools: tools).ask("Hi")
        let logged = try #require(log.lastBody)
        #expect(try object(logged) == (await transport.bodies.last))
    }

    @Test func listSuggestionsCoversEarnAndConnect() throws {
        let offer = try #require(OfferCatalog.bundled.first)
        let lina = try #require(ConnectCatalog.bundled.first)
        let suggestions = ExperienceTools.suggestions(offers: [offer], friends: [lina])
        #expect(suggestions.map(\.id) == ["o1"] + (1...lina.experiences.count).map { "c\($0)" })
        #expect(suggestions[0].target == .offer(offer.id))
        #expect(suggestions[1].target == .connect("lina/\(lina.experiences[0].id)"))

        let tools = ExperienceTools(records: records, suggestions: suggestions, calendar: utc, locale: english)
        let all = try object(tools.run(name: "list_suggestions", input: .object([:])).json)["suggestions"]?.arrayValue ?? []
        #expect(all.count == suggestions.count)
        let first = try #require(all.first)
        #expect(first["title"]?.stringValue == offer.title)
        #expect(first["from"]?.stringValue == "Earn · \(offer.partner)")
        #expect(first["reward"]?.stringValue == offer.rewardText)
        #expect(first["stops"]?.arrayValue?.count == 3)
        #expect(all[1]["from"]?.stringValue == "Connect · Lina")
        #expect(all[1]["reward"] == nil)

        let coast = try object(tools.run(name: "list_suggestions", input: .object(["category": .string("coast")])).json)
        #expect(coast["suggestions"]?.arrayValue?.allSatisfy { $0["category"]?.stringValue == "Coast" } == true)
        #expect(ExperienceTools.definitions.arrayValue?.contains { $0["name"]?.stringValue == "list_suggestions" } == true)
    }

    @Test func suggestionAndExperienceIdsBecomeLinks() {
        #expect(AskAnswerText.parts("Try [o2] or Lina's [c5], like your [e1].") == [
            .text("Try "), .experience("o2"), .text(" or Lina's "), .experience("c5"),
            .text(", like your "), .experience("e1"), .text("."),
        ])
        #expect(AskAnswerText.parts("[x1] stays text") == [.text("[x1] stays text")])
    }

    @Test func answerIdsBecomeLinkParts() {
        #expect(AskAnswerText.parts("Your trip [e1] and [e12].") == [
            .text("Your trip "), .experience("e1"), .text(" and "), .experience("e12"), .text("."),
        ])
        #expect(AskAnswerText.parts("No links here") == [.text("No links here")])
    }
}
