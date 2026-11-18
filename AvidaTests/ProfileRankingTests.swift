import Foundation
import Testing
@testable import Avida

private let day0 = Date(timeIntervalSince1970: 1_780_272_000)  // 2026-06-01 UTC

private let nyc = City(name: "New York City", countryCode: "US", latitude: 40.7143, longitude: -74.0060, population: 8_804_190)
private let manhattan = City(name: "Manhattan", countryCode: "US", latitude: 40.7834, longitude: -73.9663, population: 1_487_536)
private let brooklyn = City(name: "Brooklyn", countryCode: "US", latitude: 40.6501, longitude: -73.9496, population: 2_736_074)
private let hoboken = City(name: "Hoboken", countryCode: "US", latitude: 40.7440, longitude: -74.0324, population: 53_635)
private let jerseyCity = City(name: "Jersey City", countryCode: "US", latitude: 40.7282, longitude: -74.0776, population: 264_290)
private let kyoto = City(name: "Kyoto", countryCode: "JP", latitude: 35.0211, longitude: 135.7538, population: 1_463_723)
private let osaka = City(name: "Osaka", countryCode: "JP", latitude: 34.6938, longitude: 135.5011, population: 2_753_862)
private let beacon = City(name: "Beacon", countryCode: "US", latitude: 41.5048, longitude: -73.9696, population: 13_800)
private let bigCities = [nyc, manhattan, brooklyn, kyoto, osaka]
private let home = HomePlace(city: "Jersey City", countryCode: "US")

private func experience(_ id: String, days: Double, city: City, kmFromHome: Double = 5, photos: Int = 10,
                        memorability: Int? = nil) -> Experience {
    let start = day0.addingTimeInterval(days * 86_400)
    let ids = (0..<photos).map { "\(id)-\($0)" }
    let moment = Moment(id: id, photoIDs: ids, representativeIDs: Array(ids.prefix(3)), start: start,
                        end: start.addingTimeInterval(3600), latitude: city.latitude, longitude: city.longitude,
                        distanceFromHomeMeters: kmFromHome * 1_000, city: city, landmark: nil)
    var made = Experiences.make(id: id, kind: .outing, moments: [moment], tags: { _ in .empty })
    made.memorability = memorability
    return made
}

struct RarityTests {
    @Test func scoreAddsWeightedTerms() {
        // one-time country (2) + 0.5·ln(1+10,800) + 0.5·(7 − log10(1,463,723)) + 0.3·8
        let expected = 2 + 0.5 * log1p(10_800) + 0.5 * (7 - log10(1_463_723)) + 0.3 * 8
        let score = Rarity.score(oneTimeCountry: true, oneTimeCity: true, kilometers: 10_800, population: 1_463_723, memorability: 8)
        #expect(abs(score - expected) < 1e-9)
        // City bonus only applies without the country bonus; big cities aren't "uncommon"; no memorability → 0.
        let plain = Rarity.score(oneTimeCountry: false, oneTimeCity: true, kilometers: 0, population: 20_000_000, memorability: nil)
        #expect(plain == 1)
    }

    @Test func oneTimePlacesExcludeHomeAndRepeats() {
        let experiences = [
            experience("home-1", days: 0, city: jerseyCity),
            experience("home-2", days: 1, city: jerseyCity),
            experience("nyc-1", days: 2, city: manhattan),
            experience("nyc-2", days: 3, city: manhattan),
            experience("beacon", days: 4, city: beacon, kmFromHome: 90),
            experience("kyoto", days: 5, city: kyoto, kmFromHome: 10_800),
        ]
        let scores = Rarity.scores(experiences, home: home)
        let config = ClusterConfig.standard
        func uncommon(_ population: Int) -> Double { config.rarityUncommonWeight * (7 - log10(Double(population))) }
        func distance(_ km: Double) -> Double { config.rarityDistanceWeight * log1p(km) }

        #expect(abs(scores["home-1"]! - (distance(5) + uncommon(264_290))) < 1e-9)           // home: no bonus
        #expect(abs(scores["nyc-1"]! - (distance(5) + uncommon(1_487_536))) < 1e-9)          // visited twice: no bonus
        #expect(abs(scores["beacon"]! - (1 + distance(90) + uncommon(13_800))) < 1e-9)       // only time in Beacon
        #expect(abs(scores["kyoto"]! - (2 + distance(10_800) + uncommon(1_463_723))) < 1e-9) // only time in Japan
    }

    @Test func highlightsAreTheRarestAndMemorabilityCounts() {
        let experiences = [
            experience("a", days: 0, city: manhattan),
            experience("b", days: 1, city: beacon, kmFromHome: 90),
            experience("c", days: 2, city: kyoto, kmFromHome: 10_800),
            experience("d", days: 3, city: manhattan, memorability: 10),
        ]
        let scores = Rarity.scores(experiences, home: home)
        #expect(Rarity.highlights(experiences, scores: scores, count: 2).map(\.id) == ["c", "b"])
        #expect(scores["d"]! - scores["a"]! == 3)  // 0.3 × memorability 10; same place otherwise
        #expect(Rarity.highlights(experiences, scores: scores, count: 10).count == 4)
    }
}

struct MetroGroupingTests {
    @Test func nycBoroughsAndHobokenAllGoUnderNewYork() {
        for city in [manhattan, brooklyn, hoboken, jerseyCity] {
            #expect(MetroGrouping.metro(for: city, bigCities: bigCities) == nyc, "\(city.name)")
        }
        #expect(MetroGrouping.displayName(nyc) == "New York")
    }

    @Test func farFromBigCitiesKeepsItsOwnName() {
        #expect(MetroGrouping.metro(for: beacon, bigCities: bigCities) == beacon)  // ~88 km from NYC
        #expect(MetroGrouping.metro(for: kyoto, bigCities: bigCities) == kyoto)    // Osaka is ~43 km away
    }

    @Test func thresholdsComeFromConfig() {
        var config = ClusterConfig()
        config.metroRadiusMeters = 100_000
        #expect(MetroGrouping.metro(for: beacon, bigCities: bigCities, config: config) == nyc)
        #expect(MetroGrouping.metro(for: kyoto, bigCities: bigCities, config: config) == osaka)
        config.metroMinPopulation = 10_000_000
        #expect(MetroGrouping.metro(for: hoboken, bigCities: bigCities, config: config) == hoboken)
    }

    @Test func groupsSortByCountAndListNewestFirst() {
        let experiences = [
            experience("m", days: 0, city: manhattan),
            experience("h", days: 5, city: hoboken),
            experience("b", days: 2, city: brooklyn),
            experience("k", days: 1, city: kyoto),
        ]
        let groups = MetroGrouping.groups(experiences, bigCities: bigCities)
        #expect(groups.map(\.name) == ["New York", "Kyoto"])
        #expect(groups.map(\.countryCode) == ["US", "JP"])
        #expect(groups[0].experiences.map(\.id) == ["h", "b", "m"])
        #expect(groups[0].coverID != nil)
    }

    @Test func bundledDataHasTheBigCities() {
        let big = PlaceLookup.bigCities
        #expect(big.contains { $0.name == "New York City" && $0.countryCode == "US" })
        #expect(big.allSatisfy { $0.population > 1_000_000 })
    }
}
