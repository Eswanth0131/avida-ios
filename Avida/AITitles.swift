import Foundation

/// Claude's title and memorability for one experience, saved on the device.
nonisolated struct AITitle: Codable, Sendable, Hashable {
    let title: String
    /// 1–10.
    let memorability: Int
    let date: Date
}

/// Pure request building and response validation for Claude titles. No network, no storage.
nonisolated enum AITitles {
    static let systemPrompt = """
    You write short titles for someone's own life experiences, found on their phone from photo dates and places. \
    You only get facts: places, month and year, categories, landmark names, duration and photo count.
    For each experience, return:
    - title: one memorable sentence of 25–45 characters, in Title Case, specific to what happened there. \
    Write it like these examples:
      "Slept Under the Northern Lights"
      "Dinner with a New York Legend"
      "Swam Beside Whale Sharks"
    Use only the given facts. Never invent people, events or details. Never use people's names.
    - memorability: an integer from 1 to 10 for how memorable it likely was (a first visit to a famous place far away \
    scores high; a short local outing scores low).
    Return JSON only, with every id you were given exactly once.
    """

    /// The JSON shape Claude must return (structured outputs). Range and length are checked on the phone,
    /// since the schema can't carry min/max constraints.
    static let schema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "experiences": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string")]),
                        "title": .object(["type": .string("string")]),
                        "memorability": .object(["type": .string("integer")]),
                    ]),
                    "required": .array([.string("id"), .string("title"), .string("memorability")]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
        ]),
        "required": .array([.string("experiences")]),
        "additionalProperties": .bool(false),
    ])

    /// One request for all given experiences. Claude sees short ids (e1, e2…), never the app's experience ids
    /// (which contain photo identifiers). Returns the body and the short id → experience id map.
    static func request(
        for experiences: [Experience],
        maxTokens: Int = ClusterConfig.standard.aiTitlesMaxTokens,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> (body: JSONValue, keys: [String: String]) {
        var keys: [String: String] = [:]
        let items: [JSONValue] = experiences.enumerated().map { index, experience in
            let id = "e\(index + 1)"
            keys[id] = experience.id
            var cities: [String] = []
            for name in experience.moments.compactMap(\.city?.name) where !cities.contains(name) { cities.append(name) }
            var landmarks: [String] = []
            for name in experience.moments.compactMap(\.landmark?.name) where !landmarks.contains(name) { landmarks.append(name) }
            var item: [String: JSONValue] = [
                "id": .string(id),
                "kind": .string(experience.kind == .trip ? "trip" : "outing"),
                "places": .array(cities.prefix(6).map(JSONValue.string)),
                "when": .string(experience.start.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.wide).year())),
                "categories": .array(experience.categories.map { .string($0.rawValue) }),
                "duration": .string(Experiences.durationText(from: experience.start, to: experience.end, calendar: calendar)),
                "photos": .number(Double(experience.photoCount)),
            ]
            if let code = experience.countryCode {
                item["country"] = .string(locale.localizedString(forRegionCode: code) ?? code)
            }
            if !landmarks.isEmpty { item["landmarks"] = .array(landmarks.prefix(6).map(JSONValue.string)) }
            return .object(item)
        }
        let body: JSONValue = .object([
            "model": .string(LLMClient.model),
            "max_tokens": .number(Double(maxTokens)),
            "system": .string(systemPrompt),
            "output_config": .object([
                "effort": .string("low"),
                "format": .object(["type": .string("json_schema"), "schema": schema]),
            ]),
            "messages": .array([.object([
                "role": .string("user"),
                "content": .string("Experiences:\n" + JSONValue.array(items).compactJSON),
            ])]),
        ])
        return (body, keys)
    }

    /// What came back from one reply, and why anything was dropped.
    struct ParseResult: Equatable {
        var titles: [String: AITitle] = [:]
        /// Set when the whole reply was unusable (cut off, not JSON, wrong shape).
        var problem: String?
        /// Dropped entries by reason, e.g. ["over 45 characters": 3].
        var rejected: [String: Int] = [:]
    }

    /// Validates Claude's reply. Returns titles keyed by experience id; anything invalid is dropped, so that
    /// experience keeps its template title. An unusable reply (cut off, not JSON, wrong shape) returns [:].
    static func parse(reply: JSONValue, keys: [String: String], date: Date, config: ClusterConfig = .standard) -> [String: AITitle] {
        parseDetailed(reply: reply, keys: keys, date: date, config: config).titles
    }

    static func parseDetailed(
        reply: JSONValue,
        keys: [String: String],
        date: Date,
        config: ClusterConfig = .standard
    ) -> ParseResult {
        var result = ParseResult()
        if reply["stop_reason"]?.stringValue == "max_tokens" {
            result.problem = "Reply was cut off (max_tokens)."
            return result
        }
        guard let text = try? LLMClient.text(of: reply) else {
            result.problem = "Reply had no text."
            return result
        }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(Self.stripFences(text).utf8)) else {
            result.problem = "Reply wasn't JSON: \(text.prefix(80))"
            return result
        }
        guard let items = json["experiences"]?.arrayValue else {
            result.problem = "Reply JSON had no \"experiences\" list."
            return result
        }

        func reject(_ reason: String) { result.rejected[reason, default: 0] += 1 }
        for item in items {
            guard let shortID = item["id"]?.stringValue, let experienceID = keys[shortID] else { reject("unknown id"); continue }
            guard result.titles[experienceID] == nil else { reject("duplicate id"); continue }
            guard let memorability = item["memorability"]?.intValue, (1...10).contains(memorability) else {
                reject("memorability not 1–10"); continue
            }
            let title = (item["title"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !title.contains("\n") else { reject("empty or multi-line title"); continue }
            guard title.count <= config.aiTitleMaxCharacters else {
                reject("over \(config.aiTitleMaxCharacters) characters"); continue
            }
            result.titles[experienceID] = AITitle(title: title, memorability: memorability, date: date)
        }
        return result
    }

    /// Splits experiences into requests small enough for the proxy (≤ 64 KB body, max_tokens ≤ 4096):
    /// at most `size` experiences each, so each reply fits comfortably in max_tokens.
    static func batches(_ experiences: [Experience], size: Int) -> [[Experience]] {
        let size = max(1, size)
        return stride(from: 0, to: experiences.count, by: size).map { Array(experiences[$0..<min($0 + size, experiences.count)]) }
    }

    /// Tolerates a ```json fence around the object, in case one slips through.
    static func stripFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed.drop(while: { $0 != "\n" }).dropFirst().description
            if trimmed.hasSuffix("```") { trimmed = String(trimmed.dropLast(3)) }
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Claude titles saved in Documents/ai-titles.json, keyed by experience id.
@Observable
final class AITitleStore {
    private(set) var entries: [String: AITitle]
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = URL.documentsDirectory.appending(path: "ai-titles.json")) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        entries = data.flatMap { try? EarnStore.decoder.decode([String: AITitle].self, from: $0) } ?? [:]
    }

    func merge(_ new: [String: AITitle]) {
        guard !new.isEmpty else { return }
        entries.merge(new) { _, newer in newer }
        if let data = try? EarnStore.encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func reset() {
        entries = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// The outcome of one titles run, for the Developer screen.
nonisolated struct AITitleRun: Sendable, Equatable {
    var date: Date
    /// Experiences that needed a title.
    var requested = 0
    var requests = 0
    var accepted = 0
    var rejected: [String: Int] = [:]
    /// The first thing that went wrong, if anything did.
    var error: String?

    var summary: String {
        if requested == 0 && error == nil { return "Nothing to title: every experience already has one." }
        var parts = ["\(accepted) of \(requested) titled in \(requests) request\(requests == 1 ? "" : "s")"]
        if !rejected.isEmpty {
            parts.append("kept templates: " + rejected.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", "))
        }
        if let error { parts.append("error: \(error)") }
        return parts.joined(separator: " · ")
    }
}

/// Asks Claude for titles for the top experiences by worthiness that don't have a saved one yet,
/// in batches the proxy accepts.
final class AITitleWriter {
    private let client: LLMClient
    private let batchSize: Int
    private let maxExperiences: Int

    init(
        client: LLMClient = LLMClient(),
        batchSize: Int = ClusterConfig.standard.aiTitlesPerRequest,
        maxExperiences: Int = ClusterConfig.standard.aiTitlesMaxExperiences
    ) {
        self.client = client
        self.batchSize = batchSize
        self.maxExperiences = maxExperiences
    }

    /// New titles for the top `maxExperiences` (by worthiness) missing from `existing`. Failures never throw: the run records the error,
    /// titles from batches that worked are kept, and everything else keeps its template title.
    func titles(
        for experiences: [Experience],
        existing: [String: AITitle],
        now: Date = .now,
        progress: ((Double) -> Void)? = nil
    ) async -> (titles: [String: AITitle], run: AITitleRun) {
        // Top N by worthiness; anything below keeps its template title.
        let top = experiences.sorted { $0.worthiness != $1.worthiness ? $0.worthiness > $1.worthiness : $0.start > $1.start }
            .prefix(maxExperiences)
        let missing = top.filter { existing[$0.id] == nil }
        var run = AITitleRun(date: now, requested: missing.count)
        guard !missing.isEmpty else { return ([:], run) }
        var titles: [String: AITitle] = [:]
        let batches = AITitles.batches(missing, size: batchSize)
        defer { progress?(1) }
        for (index, batch) in batches.enumerated() {
            progress?(Double(index) / Double(batches.count))
            let request = AITitles.request(for: batch)
            run.requests += 1
            do {
                let reply = try await client.createMessage(request.body)
                let parsed = AITitles.parseDetailed(reply: reply, keys: request.keys, date: now)
                titles.merge(parsed.titles) { first, _ in first }
                run.rejected.merge(parsed.rejected, uniquingKeysWith: +)
                if let problem = parsed.problem, run.error == nil { run.error = problem }
            } catch {
                run.error = error.localizedDescription
                break  // proxy/API errors would repeat for every batch
            }
        }
        run.accepted = titles.count
        return (titles, run)
    }
}
