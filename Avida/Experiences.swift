import Foundation

nonisolated enum ExperienceCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case nature = "Nature"
    case city = "City"
    case culinary = "Culinary"
    case culture = "Culture"
    case coast = "Coast"
    case nightlife = "Nightlife"
}

/// Something worth remembering: a whole trip, or an outing (non-trip moments less than `outingMaxGap` apart).
nonisolated struct Experience: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case trip
        /// Consecutive non-trip moments, possibly across cities ("Hoboken & Manhattan" in one evening).
        case outing
    }

    let id: String
    let kind: Kind
    /// Shown title: Claude's when AI suggestions is on and it wrote one, else the template.
    var title: String
    /// Deterministic, e.g. "Exploring Manhattan", "Vessel & Central Park", "An evening in Hoboken & Manhattan".
    let templateTitle: String
    /// Up to 2 main places, "City A & City B".
    let place: String
    let countryCode: String?
    let start: Date
    let end: Date
    /// Chronological; shown as numbered stops.
    let moments: [Moment]
    /// Strongest first; never empty.
    let categories: [ExperienceCategory]
    let tags: TagSummary
    /// Raw deterministic worthiness (see ClusterConfig.worthiness*).
    let worthiness: Double
    let novelty: Novelty
    /// Claude's 1–10, when AI suggestions is on and it rated this experience.
    var memorability: Int?
    /// Final rank score, 0…1 (see Ranking). Highest first.
    var score: Double
    let coverIDs: [String]
    let heroID: String?

    var category: ExperienceCategory { categories[0] }
    var photoCount: Int { moments.reduce(0) { $0 + $1.photoIDs.count } }
    var photoIDs: [String] { moments.flatMap(\.photoIDs) }
    var topSitelinks: Int { moments.compactMap(\.landmark?.sitelinks).max() ?? 0 }
    var kilometersFromHome: Double { (moments.map(\.distanceFromHomeMeters).max() ?? 0) / 1_000 }
}

/// First-ever visit to a country or city (home doesn't count).
nonisolated enum Novelty: Sendable, Hashable {
    case none
    case newCity
    case newCountry
}

/// The user's home city and country, so being at home is never "new".
nonisolated struct HomePlace: Sendable, Hashable {
    let city: String?
    let countryCode: String?
}

/// Pure rules for turning clusters into ranked experiences. Unit tested without PhotoKit or Vision.
nonisolated enum Experiences {
    /// Every trip, plus every outing that has a matched landmark or at least `outingMinPhotos` photos.
    /// Ranked by worthiness alone; `Ranking.rank` can blend in memorability afterwards.
    static func build(
        trips: [Trip],
        otherMoments: [Moment],
        tags: (Moment) -> TagSummary,
        home: HomePlace? = nil,
        config: ClusterConfig = .standard,
        calendar: Calendar = .current
    ) -> [Experience] {
        var groups: [(id: String, kind: Experience.Kind, moments: [Moment])] = trips.map {
            (id: "trip-\($0.id)", kind: .trip, moments: $0.moments.sorted { $0.start < $1.start })
        }
        for outing in outings(otherMoments, config: config) where qualifies(outing, config: config) {
            groups.append((id: "outing-\(outing[0].id)", kind: .outing, moments: outing))
        }

        let firsts = novelty(groups.map { (id: $0.id, start: $0.moments[0].start, cities: $0.moments.compactMap(\.city)) }, home: home)
        let experiences = groups.map { group in
            make(id: group.id, kind: group.kind, moments: group.moments, tags: tags,
                 novelty: firsts[group.id] ?? .none, config: config, calendar: calendar)
        }
        return Ranking.rank(experiences, memorability: [:], config: config)
    }

    /// Non-trip moments in time order, split wherever the gap from one moment's end to the next one's start
    /// is `outingMaxGap` or more. Cities don't matter: Hoboken → Manhattan in one evening is one outing.
    static func outings(_ moments: [Moment], config: ClusterConfig = .standard) -> [[Moment]] {
        var groups: [[Moment]] = []
        for moment in moments.sorted(by: { $0.start < $1.start }) {
            if let last = groups.last?.last, moment.start.timeIntervalSince(last.end) < config.outingMaxGap {
                groups[groups.count - 1].append(moment)
            } else {
                groups.append([moment])
            }
        }
        return groups
    }

    static func qualifies(_ outing: [Moment], config: ClusterConfig = .standard) -> Bool {
        outing.contains { $0.landmark != nil } || outing.reduce(0) { $0 + $1.photoIDs.count } >= config.outingMinPhotos
    }

    /// Walks experiences in time order; each one that reaches a country (or else a city) not seen before,
    /// and not home, gets that novelty.
    static func novelty(_ items: [(id: String, start: Date, cities: [City])], home: HomePlace?) -> [String: Novelty] {
        var seenCountries = Set([home?.countryCode].compactMap { $0 })
        var seenCities = Set([home?.city].compactMap { $0 })
        var result: [String: Novelty] = [:]
        for item in items.sorted(by: { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id }) {
            let countries = Set(item.cities.map(\.countryCode))
            let cities = Set(item.cities.map(\.name))
            if !countries.isSubset(of: seenCountries) {
                result[item.id] = .newCountry
            } else if !cities.isSubset(of: seenCities) {
                result[item.id] = .newCity
            } else {
                result[item.id] = Novelty.none
            }
            seenCountries.formUnion(countries)
            seenCities.formUnion(cities)
        }
        return result
    }

    static func make(
        id: String,
        kind: Experience.Kind,
        moments: [Moment],
        tags: (Moment) -> TagSummary,
        novelty: Novelty = .none,
        config: ClusterConfig = .standard,
        calendar: Calendar = .current
    ) -> Experience {
        let moments = moments.sorted { $0.start < $1.start }
        let cities = PlaceNaming.mainCities(moments, config: config)
        let place = cities.isEmpty ? "Somewhere new" : cities.map(\.name).joined(separator: " & ")
        let tagSummary = TagAggregation.trip(moments.map(tags), config: config)
        let covers = coverIDs(moments, count: config.coverPhotosPerExperience)
        let template = title(kind: kind, moments: moments, place: cities.isEmpty ? nil : place, config: config, calendar: calendar)
        let worth = worthiness(moments, novelty: novelty, config: config)
        return Experience(
            id: id,
            kind: kind,
            title: template,
            templateTitle: template,
            place: place,
            countryCode: cities.first?.countryCode,
            start: moments.first!.start,
            end: moments.map(\.end).max()!,
            moments: moments,
            categories: categories(tags: tagSummary, landmarks: moments.compactMap(\.landmark), config: config),
            tags: tagSummary,
            worthiness: worth,
            novelty: novelty,
            memorability: nil,
            score: worth,
            coverIDs: covers,
            heroID: heroID(moments) ?? covers.first
        )
    }

    /// Trips: "Exploring Kyoto". Outings: the most famous landmarks in visit order ("Vessel & Central Park"),
    /// else "An evening in Hoboken & Manhattan" / "A day in Jersey City".
    static func title(
        kind: Experience.Kind, moments: [Moment], place: String?,
        config: ClusterConfig = .standard, calendar: Calendar = .current
    ) -> String {
        switch kind {
        case .trip:
            return place.map { "Exploring \($0)" } ?? "A trip away"
        case .outing:
            let names = PlaceNaming.famousLandmarks(moments, count: config.tripLandmarksInLabel).map(\.name)
            if !names.isEmpty { return names.joined(separator: " & ") }
            let evening = moments.first.map { calendar.component(.hour, from: $0.start) >= 17 } ?? false
            guard let place else { return evening ? "An evening out" : "A day out" }
            return evening ? "An evening in \(place)" : "A day in \(place)"
        }
    }

    /// Deterministic worthiness. Every term is logarithmic except the novelty bonus.
    static func worthiness(_ moments: [Moment], novelty: Novelty, config: ClusterConfig = .standard) -> Double {
        let sitelinks = Double(moments.compactMap(\.landmark?.sitelinks).max() ?? 0)
        let kilometers = (moments.map(\.distanceFromHomeMeters).max() ?? 0) / 1_000
        let photos = Double(moments.reduce(0) { $0 + $1.photoIDs.count })
        let hours = max(0, (moments.map(\.end).max() ?? .distantPast).timeIntervalSince(moments.map(\.start).min() ?? .distantPast)) / 3600
        let bonus: Double = switch novelty {
        case .newCountry: config.worthinessNewCountryBonus
        case .newCity: config.worthinessNewCityBonus
        case .none: 0
        }
        return config.worthinessFameWeight * log1p(sitelinks)
            + bonus
            + config.worthinessDistanceWeight * log1p(kilometers)
            + config.worthinessPhotoWeight * log1p(photos)
            + config.worthinessDurationWeight * log1p(hours)
    }

    /// Categories voted for by the experience's top tags and its landmarks' types, strongest first.
    static func categories(tags: TagSummary, landmarks: [Landmark], config: ClusterConfig = .standard) -> [ExperienceCategory] {
        var scores: [ExperienceCategory: Double] = [:]
        for tag in tags.tags {
            for (category, labels) in config.categoryTagLabels where labels.contains(tag.name) {
                scores[category, default: 0] += Double(tag.score)
            }
        }
        for landmark in landmarks {
            let words = LandmarkMatching.typeWords(landmark)
            for (category, typeWords) in config.categoryLandmarkTypeWords where !typeWords.isDisjoint(with: words) {
                scores[category, default: 0] += config.categoryLandmarkWeight
            }
        }
        let order = ExperienceCategory.allCases
        let ranked = scores
            .filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : order.firstIndex(of: $0.key)! < order.firstIndex(of: $1.key)! }
            .prefix(config.categoriesPerExperience)
            .map(\.key)
        return ranked.isEmpty ? [config.defaultCategory] : ranked
    }

    /// Up to `count` representative photos spread evenly across the experience's moments.
    static func coverIDs(_ moments: [Moment], count: Int) -> [String] {
        let all = moments.flatMap(\.representativeIDs)
        guard all.count > count, count > 1 else { return Array(all.prefix(count)) }
        return (0..<count).map { all[Int((Double($0) * Double(all.count - 1) / Double(count - 1)).rounded())] }
    }

    /// Middle representative of the moment with the most famous landmark, if any.
    static func heroID(_ moments: [Moment]) -> String? {
        guard let best = moments.filter({ $0.landmark != nil }).max(by: { $0.landmark!.sitelinks < $1.landmark!.sitelinks }),
              !best.representativeIDs.isEmpty else { return nil }
        return best.representativeIDs[best.representativeIDs.count / 2]
    }

    /// "~35 min", "~2 hrs", "3 days". Same calendar day uses minutes/hours; otherwise whole days, inclusive.
    static func durationText(from start: Date, to end: Date, calendar: Calendar = .current) -> String {
        if !calendar.isDate(start, inSameDayAs: end) {
            let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0) + 1
            return "\(days) days"
        }
        let minutes = end.timeIntervalSince(start) / 60
        if minutes < 1 { return "Quick stop" }
        if minutes < 55 { return "~\(max(5, Int((minutes / 5).rounded()) * 5)) min" }
        let hours = max(1, Int((minutes / 60).rounded()))
        return hours == 1 ? "~1 hr" : "~\(hours) hrs"
    }
}

/// Final order: normalized worthiness, blended with Claude's memorability when there is one.
nonisolated enum Ranking {
    /// score = rankWorthinessWeight × normalized worthiness + rankMemorabilityWeight × (memorability − 1) / 9.
    /// Experiences without a memorability rating use normalized worthiness alone, so they aren't penalised.
    /// Worthiness is min–max normalized across the given experiences (all equal → 1).
    static func rank(_ experiences: [Experience], memorability: [String: Int], config: ClusterConfig = .standard) -> [Experience] {
        let values = experiences.map(\.worthiness)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let totalWeight = config.rankWorthinessWeight + config.rankMemorabilityWeight
        return experiences.map { experience in
            var ranked = experience
            let normalized = high > low ? (experience.worthiness - low) / (high - low) : 1
            if let rating = memorability[experience.id], totalWeight > 0 {
                let memory = Double(min(max(rating, 1), 10) - 1) / 9
                ranked.memorability = rating
                ranked.score = (config.rankWorthinessWeight * normalized + config.rankMemorabilityWeight * memory) / totalWeight
            } else {
                ranked.memorability = nil
                ranked.score = normalized
            }
            return ranked
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.start > $1.start }
    }
}
