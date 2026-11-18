import Foundation

/// A text-only view of one experience: the only data the Ask agent can send to Claude.
/// No photo IDs, image data, file paths or coordinates. IDs are short ("e1") and only mean something in this app.
nonisolated struct ExperienceRecord: Sendable, Equatable {
    struct Stop: Sendable, Equatable {
        let name: String
        let description: String?
        let city: String?
        let duration: String
    }

    enum Source: Sendable, Equatable {
        /// Experience.id of a photo experience.
        case photos(String)
        /// VerifiedExperience.id of an Earn check-in.
        case verified(UUID)
    }

    let id: String
    let source: Source
    let kind: String
    let title: String
    let place: String
    let country: String?
    let start: Date
    let end: Date
    let categories: [String]
    let landmarks: [String]
    let photoCount: Int
    let score: Double
    let rarity: Double
    let stops: [Stop]
}

/// Something the user could do next, from Earn or Connect. Text only.
nonisolated struct SuggestionRecord: Sendable, Equatable {
    enum Target: Sendable, Equatable {
        /// Offer.id
        case offer(String)
        /// ConnectCatalog.connectID ("<friend>/<experience>")
        case connect(String)
    }

    let id: String
    let target: Target
    let title: String
    let place: String
    let category: String
    /// "Earn · JAL" or "Connect · Lina"
    let from: String
    let reward: String?
    let stops: [String]
}

/// The tools the Ask agent can call. Pure: runs on a snapshot, returns compact JSON text.
nonisolated struct ExperienceTools: Sendable {
    let records: [ExperienceRecord]
    let calendar: Calendar
    let locale: Locale

    /// Earn offers and Connect experiences, for "What should I do next?" (ids o1…, c1…).
    let suggestions: [SuggestionRecord]

    init(records: [ExperienceRecord], suggestions: [SuggestionRecord] = [], calendar: Calendar = .current, locale: Locale = .current) {
        self.records = records
        self.suggestions = suggestions
        self.calendar = calendar
        self.locale = locale
    }

    // MARK: Snapshot

    /// Photo experiences (ranked, so e1 is the best) followed by verified check-ins.
    static func snapshot(
        experiences: [Experience],
        verified: [VerifiedExperience],
        rarity: [String: Double]? = nil,
        home: HomePlace? = nil,
        config: ClusterConfig = .standard,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [ExperienceRecord] {
        var records: [ExperienceRecord] = []
        let rarity = rarity ?? Rarity.scores(experiences, home: home, config: config)
        for experience in experiences {
            records.append(ExperienceRecord(
                id: "e\(records.count + 1)",
                source: .photos(experience.id),
                kind: experience.kind == .trip ? "trip" : "outing",
                title: experience.title,
                place: experience.place,
                country: experience.countryCode.map { PlaceLookup.countryName($0, locale: locale) },
                start: experience.start,
                end: experience.end,
                categories: experience.categories.map(\.rawValue),
                landmarks: uniqued(experience.moments.compactMap(\.landmark?.name)),
                photoCount: experience.photoCount,
                score: experience.score,
                rarity: rarity[experience.id] ?? 0,
                stops: experience.moments.map { moment in
                    ExperienceRecord.Stop(
                        name: moment.landmark?.name ?? moment.city?.name ?? "Somewhere",
                        description: moment.landmark?.description.isEmpty == false ? moment.landmark?.description : nil,
                        city: moment.city?.name,
                        duration: Experiences.durationText(from: moment.start, to: moment.end, calendar: calendar)
                    )
                }
            ))
        }
        for check in verified {
            records.append(ExperienceRecord(
                id: "e\(records.count + 1)",
                source: .verified(check.id),
                kind: "verified check-in",
                title: check.title,
                place: check.place,
                country: nil,
                start: check.date,
                end: check.date,
                categories: [check.category.rawValue],
                landmarks: [],
                photoCount: 1,
                score: 0,
                rarity: 0,
                stops: []
            ))
        }
        return records
    }

    /// Earn offers first (o1…), then Connect friends' experiences (c1…).
    static func suggestions(offers: [Offer], friends: [ConnectFriend]) -> [SuggestionRecord] {
        let fromEarn = offers.enumerated().map { index, offer in
            SuggestionRecord(id: "o\(index + 1)", target: .offer(offer.id), title: offer.title, place: offer.place,
                             category: offer.category.rawValue, from: "Earn · \(offer.partner)", reward: offer.rewardText,
                             stops: offer.stops.map(\.name))
        }
        var fromConnect: [SuggestionRecord] = []
        for friend in friends {
            for experience in friend.experiences {
                fromConnect.append(SuggestionRecord(
                    id: "c\(fromConnect.count + 1)",
                    target: .connect(ConnectCatalog.connectID(friend: friend, experience: experience)),
                    title: experience.title, place: "\(experience.place), \(experience.country)",
                    category: experience.category.rawValue, from: "Connect · \(friend.name)", reward: nil,
                    stops: experience.stops.map(\.name)))
            }
        }
        return fromEarn + fromConnect
    }

    // MARK: Tool definitions (Messages API `tools`)

    static var definitions: JSONValue {
        let categories = JSONValue.array(ExperienceCategory.allCases.map { .string($0.rawValue) })
        func string(_ description: String) -> JSONValue {
            .object(["type": .string("string"), "description": .string(description)])
        }
        func tool(_ name: String, _ description: String, _ properties: [String: JSONValue], required: [String]) -> JSONValue {
            .object([
                "name": .string(name),
                "description": .string(description),
                "input_schema": .object([
                    "type": .string("object"),
                    "properties": .object(properties),
                    "required": .array(required.map(JSONValue.string)),
                    "additionalProperties": .bool(false),
                ]),
            ])
        }
        return .array([
            tool("search_experiences",
                 "Find the user's experiences. All filters are optional and combine with AND. Returns id, title, place, country, when (month year), categories, landmarks, photos and score, best score first.",
                 [
                    "text": string("Words to look for in titles, places, landmarks, stop names and descriptions."),
                    "category": .object(["type": .string("string"), "enum": categories]),
                    "city": string("City name, e.g. Kyoto."),
                    "country": string("Country name or ISO code, e.g. Japan or JP."),
                    "year": .object(["type": .string("integer"), "description": .string("Year the experience started.")]),
                 ], required: []),
            tool("get_experience",
                 "Full detail for one experience by id, including its stops in order (landmark or city name, description, city, duration).",
                 ["id": string("Experience id, e.g. e3.")], required: ["id"]),
            tool("stats",
                 "Count the user's experiences grouped by country, city, year or category (primary category).",
                 ["group_by": .object(["type": .string("string"), "enum": .array(["country", "city", "year", "category"].map(JSONValue.string))])],
                 required: ["group_by"]),
            tool("top_experiences",
                 "The user's top experiences. by=score: overall rank (0–100: worthiness, plus memorability when available). by=rarity: places visited only once, distance from home, how small and unusual the place is, and memorability.",
                 [
                    "n": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(10)]),
                    "by": .object(["type": .string("string"), "enum": .array([.string("score"), .string("rarity")])]),
                 ], required: ["n", "by"]),
            tool("list_suggestions",
                 "Experiences the user could do next: sponsored Earn experiences (ids o1…, with partner and reward) and friends' experiences from Connect (ids c1…). Use for \"what should I do next\".",
                 ["category": .object(["type": .string("string"), "enum": categories])],
                 required: []),
        ])
    }

    // MARK: Running tools

    struct Result: Equatable {
        let json: String
        let isError: Bool
    }

    func run(name: String, input: JSONValue) -> Result {
        switch name {
        case "search_experiences": return search(input)
        case "get_experience": return getExperience(input)
        case "stats": return stats(input)
        case "top_experiences": return top(input)
        case "list_suggestions": return listSuggestions(input)
        default: return error("Unknown tool: \(name)")
        }
    }

    private func search(_ input: JSONValue) -> Result {
        var matches = records
        if let text = input["text"]?.stringValue?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
            matches = matches.filter { Self.searchableText($0).contains { $0.localizedCaseInsensitiveContains(text) } }
        }
        if let category = input["category"]?.stringValue {
            matches = matches.filter { $0.categories.contains { $0.caseInsensitiveCompare(category) == .orderedSame } }
        }
        if let city = input["city"]?.stringValue {
            matches = matches.filter { record in
                record.place.localizedCaseInsensitiveContains(city)
                    || record.stops.contains { $0.city?.localizedCaseInsensitiveContains(city) == true }
            }
        }
        if let country = input["country"]?.stringValue {
            let name = locale.localizedString(forRegionCode: country.uppercased())
            matches = matches.filter { record in
                guard let recordCountry = record.country else { return false }
                return recordCountry.caseInsensitiveCompare(country) == .orderedSame
                    || recordCountry.caseInsensitiveCompare(name ?? "") == .orderedSame
            }
        }
        if let year = input["year"]?.intValue {
            matches = matches.filter { calendar.component(.year, from: $0.start) == year }
        }
        let ranked = matches.sorted { $0.score > $1.score }
        return ok(.object([
            "total": .number(Double(ranked.count)),
            "experiences": .array(ranked.prefix(20).map(summary)),
        ]))
    }

    private func getExperience(_ input: JSONValue) -> Result {
        guard let id = input["id"]?.stringValue else { return error("id is required.") }
        guard let record = records.first(where: { $0.id == id }) else { return error("No experience with id \(id).") }
        var object = summaryObject(record)
        object["kind"] = .string(record.kind)
        object["dates"] = .string(dateRange(record))
        object["duration"] = .string(Experiences.durationText(from: record.start, to: record.end, calendar: calendar))
        object["stops"] = .array(record.stops.map { stop in
            var item: [String: JSONValue] = ["name": .string(stop.name), "duration": .string(stop.duration)]
            if let description = stop.description { item["description"] = .string(description) }
            if let city = stop.city { item["city"] = .string(city) }
            return .object(item)
        })
        return ok(.object(object))
    }

    private func stats(_ input: JSONValue) -> Result {
        let key: (ExperienceRecord) -> String
        switch input["group_by"]?.stringValue {
        case "country": key = { $0.country ?? "Unknown" }
        case "city": key = { $0.place }
        case "year": key = { String(calendar.component(.year, from: $0.start)) }
        case "category": key = { $0.categories.first ?? "Unknown" }
        default: return error("group_by must be one of country, city, year, category.")
        }
        let counts = Dictionary(grouping: records, by: key).map { (key: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.key < $1.key }
        return ok(.object([
            "group_by": input["group_by"] ?? .null,
            "total": .number(Double(records.count)),
            "counts": .array(counts.map { .object(["key": .string($0.key), "count": .number(Double($0.count))]) }),
        ]))
    }

    private func top(_ input: JSONValue) -> Result {
        let n = min(max(input["n"]?.intValue ?? 5, 1), 10)
        let ranked: [ExperienceRecord]
        switch input["by"]?.stringValue {
        case "score", nil: ranked = records.sorted { $0.score > $1.score }
        case "rarity": ranked = records.sorted { $0.rarity > $1.rarity }
        default: return error("by must be score or rarity.")
        }
        return ok(.object(["experiences": .array(ranked.prefix(n).map { record in
            var object = summaryObject(record)
            object["rarity"] = .number(record.rarity.rounded())
            return .object(object)
        })]))
    }

    private func listSuggestions(_ input: JSONValue) -> Result {
        var matches = suggestions
        if let category = input["category"]?.stringValue {
            matches = matches.filter { $0.category.caseInsensitiveCompare(category) == .orderedSame }
        }
        return ok(.object(["suggestions": .array(matches.map { suggestion in
            var object: [String: JSONValue] = [
                "id": .string(suggestion.id),
                "title": .string(suggestion.title),
                "place": .string(suggestion.place),
                "category": .string(suggestion.category),
                "from": .string(suggestion.from),
                "stops": .array(suggestion.stops.map(JSONValue.string)),
            ]
            if let reward = suggestion.reward { object["reward"] = .string(reward) }
            return .object(object)
        })]))
    }

    // MARK: Encoding

    private func summary(_ record: ExperienceRecord) -> JSONValue { .object(summaryObject(record)) }

    private func summaryObject(_ record: ExperienceRecord) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "id": .string(record.id),
            "title": .string(record.title),
            "place": .string(record.place),
            "when": .string(record.start.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).year())),
            "categories": .array(record.categories.map(JSONValue.string)),
            "photos": .number(Double(record.photoCount)),
            "score": .number((record.score * 100).rounded()),
        ]
        if let country = record.country { object["country"] = .string(country) }
        if !record.landmarks.isEmpty { object["landmarks"] = .array(record.landmarks.map(JSONValue.string)) }
        if record.kind == "verified check-in" { object["verified"] = .bool(true) }
        return object
    }

    private func dateRange(_ record: ExperienceRecord) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let start = record.start.formatted(style)
        let end = record.end.formatted(style)
        return start == end ? start : "\(start) – \(end)"
    }

    private func ok(_ value: JSONValue) -> Result { Result(json: value.compactJSON, isError: false) }
    private func error(_ message: String) -> Result { Result(json: JSONValue.object(["error": .string(message)]).compactJSON, isError: true) }

    private static func searchableText(_ record: ExperienceRecord) -> [String] {
        var fields: [String] = [record.title, record.place, record.country ?? ""]
        fields += record.landmarks
        fields += record.categories
        for stop in record.stops {
            fields.append(stop.name)
            if let description = stop.description { fields.append(description) }
            if let city = stop.city { fields.append(city) }
        }
        return fields
    }

    private static func uniqued(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
