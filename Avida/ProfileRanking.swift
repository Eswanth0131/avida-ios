import Foundation

/// Rarity for Profile → Highlights (and Ask's "rarest"). Pure; weights in ClusterConfig.rarity*.
nonisolated enum Rarity {
    /// Rarity of every experience, keyed by experience id. "One-time" is judged across all of them.
    static func scores(_ experiences: [Experience], home: HomePlace?, config: ClusterConfig = .standard) -> [String: Double] {
        let countryCounts = counts(experiences.map { Set($0.moments.compactMap(\.city?.countryCode)) })
        let cityCounts = counts(experiences.map { Set($0.moments.compactMap(\.city?.name)) })
        var result: [String: Double] = [:]
        for experience in experiences {
            let countries = Set(experience.moments.compactMap(\.city?.countryCode)).subtracting([home?.countryCode].compactMap { $0 })
            let cities = Set(experience.moments.compactMap(\.city?.name)).subtracting([home?.city].compactMap { $0 })
            result[experience.id] = score(
                oneTimeCountry: countries.contains { countryCounts[$0] == 1 },
                oneTimeCity: cities.contains { cityCounts[$0] == 1 },
                kilometers: experience.kilometersFromHome,
                population: experience.moments.compactMap(\.city?.population).filter { $0 > 0 }.min(),
                memorability: experience.memorability,
                config: config
            )
        }
        return result
    }

    static func score(
        oneTimeCountry: Bool,
        oneTimeCity: Bool,
        kilometers: Double,
        population: Int?,
        memorability: Int?,
        config: ClusterConfig = .standard
    ) -> Double {
        let bonus = oneTimeCountry ? config.rarityOneTimeCountryBonus : (oneTimeCity ? config.rarityOneTimeCityBonus : 0)
        let uncommon = population.map { max(0, log10(config.rarityPopulationReference) - log10(Double(max($0, 1)))) } ?? 0
        let memory = memorability.map { Double(min(max($0, 1), 10)) } ?? 0
        return bonus
            + config.rarityDistanceWeight * log1p(max(0, kilometers))
            + config.rarityUncommonWeight * uncommon
            + config.rarityMemorabilityWeight * memory
    }

    /// Top `count` experiences by rarity; ties go to the more recent one.
    static func highlights(_ experiences: [Experience], scores: [String: Double], count: Int) -> [Experience] {
        Array(experiences.sorted {
            let a = scores[$0.id] ?? 0, b = scores[$1.id] ?? 0
            return a != b ? a > b : $0.start > $1.start
        }.prefix(count))
    }

    private static func counts(_ sets: [Set<String>]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for set in sets { for item in set { counts[item, default: 0] += 1 } }
        return counts
    }
}

/// One row on Profile → Places.
nonisolated struct PlaceGroup: Sendable, Identifiable, Hashable {
    var id: String { "\(name)|\(countryCode ?? "")" }
    let name: String
    let countryCode: String?
    /// Newest first.
    let experiences: [Experience]
    /// Hero photo of the group's best experience.
    var coverID: String? { experiences.max { $0.score < $1.score }?.heroID }
}

/// Groups experiences by metro area for Profile → Places. Pure; thresholds in ClusterConfig.metro*.
nonisolated enum MetroGrouping {
    /// The most populous city over `metroMinPopulation` within `metroRadiusMeters`, else the city itself.
    static func metro(for city: City, bigCities: [City], config: ClusterConfig = .standard) -> City {
        bigCities
            .filter { $0.population > config.metroMinPopulation }
            .filter { Clustering.distanceMeters((city.latitude, city.longitude), ($0.latitude, $0.longitude)) <= config.metroRadiusMeters }
            .max { $0.population < $1.population }
            ?? city
    }

    static func displayName(_ city: City, config: ClusterConfig = .standard) -> String {
        config.metroDisplayNames[city.name] ?? city.name
    }

    /// Groups by each experience's main city's metro. Groups with more experiences first, then by name.
    static func groups(_ experiences: [Experience], bigCities: [City], config: ClusterConfig = .standard) -> [PlaceGroup] {
        var buckets: [String: (name: String, country: String?, items: [Experience])] = [:]
        for experience in experiences {
            let main = PlaceNaming.mainCities(experience.moments, config: config).first
            let metroCity = main.map { metro(for: $0, bigCities: bigCities, config: config) }
            let name = metroCity.map { displayName($0, config: config) } ?? experience.place
            let country = metroCity?.countryCode ?? experience.countryCode
            let key = "\(name)|\(country ?? "")"
            buckets[key, default: (name, country, [])].items.append(experience)
        }
        return buckets.values
            .map { PlaceGroup(name: $0.name, countryCode: $0.country, experiences: $0.items.sorted { $0.start > $1.start }) }
            .sorted { $0.experiences.count != $1.experiences.count ? $0.experiences.count > $1.experiences.count : $0.name < $1.name }
    }
}

extension PlaceLookup {
    /// Cities over the metro threshold, computed once (≈560 of the bundled 31k).
    nonisolated static let bigCities: [City] = {
        (shared?.cities ?? []).filter { $0.population > ClusterConfig.standard.metroMinPopulation }
    }()
}
