import Foundation
import Testing
@testable import Avida

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 2026-06-01 00:00 UTC.
private let day0 = Date(timeIntervalSince1970: 1_780_272_000)

private let manhattan = City(name: "Manhattan", countryCode: "US", latitude: 40.78, longitude: -73.97, population: 1)
private let jerseyCity = City(name: "Jersey City", countryCode: "US", latitude: 40.72, longitude: -74.07, population: 1)
private let kyoto = City(name: "Kyoto", countryCode: "JP", latitude: 35.01, longitude: 135.77, population: 1)

private func landmark(_ name: String, type: String = "building", sitelinks: Int) -> Landmark {
    Landmark(qid: "Q-\(name)", name: name, description: "", type: type, latitude: 0, longitude: 0, sitelinks: sitelinks)
}

private func moment(
    _ id: String, hours: Double, durationHours: Double = 1, photos: Int = 5,
    city: City = manhattan, landmark: Landmark? = nil, kmFromHome: Double = 5
) -> Moment {
    let start = day0.addingTimeInterval(hours * 3600)
    let ids = (0..<photos).map { "\(id)-\($0)" }
    return Moment(id: id, photoIDs: ids, representativeIDs: Array(ids.prefix(5)), start: start,
                  end: start.addingTimeInterval(durationHours * 3600), latitude: 0, longitude: 0,
                  distanceFromHomeMeters: kmFromHome * 1_000, city: city, landmark: landmark)
}

private func tags(_ pairs: [String: Float]) -> TagSummary {
    TagSummary(tags: pairs.map { ScoredTag(name: $0.key, score: $0.value) })
}

private let noTags: (Moment) -> TagSummary = { _ in .empty }

struct ExperiencesTests {
    private let vessel = landmark("Vessel", type: "sculpture", sitelinks: 19)
    private let centralPark = landmark("Central Park", type: "urban park", sitelinks: 87)

    private let hoboken = City(name: "Hoboken", countryCode: "US", latitude: 40.74, longitude: -74.03, population: 1)
    private let home = HomePlace(city: "Jersey City", countryCode: "US")

    @Test func everyTripAndQualifyingOutingIsAnExperience() {
        let trip = Trip(moments: [moment("k1", hours: 100, city: kyoto, kmFromHome: 10_800)])
        let others = [
            moment("a", hours: 10, landmark: vessel),       // 10–11h, has a landmark
            moment("b", hours: 14),                         // 3 h after a ends: same outing
            moment("c", hours: 34, city: jerseyCity),       // 19 h later: own outing, 5 photos, no landmark → skipped
        ]
        let experiences = Experiences.build(trips: [trip], otherMoments: others, tags: noTags, calendar: utc)
        #expect(experiences.count == 2)
        let outing = experiences.first { $0.kind == .outing }
        #expect(outing?.moments.map(\.id) == ["a", "b"])
        #expect(experiences.contains { $0.kind == .trip && $0.moments.map(\.id) == ["k1"] })
    }

    @Test func outingsMergeAcrossCitiesWhileGapIsUnderFourHours() {
        let evening = [
            moment("h", hours: 18, durationHours: 1, photos: 6, city: hoboken),      // 18–19h
            moment("m", hours: 21, durationHours: 2, photos: 6, city: manhattan),    // starts 2 h later
        ]
        let groups = Experiences.outings(evening)
        #expect(groups.map { $0.map(\.id) } == [["h", "m"]])

        let experience = Experiences.build(trips: [], otherMoments: evening, tags: noTags, calendar: utc)[0]
        #expect(experience.place == "Hoboken & Manhattan")
        #expect(experience.title == "An evening in Hoboken & Manhattan")

        // Exactly 4 h apart splits; the gap comes from config.
        let apart = [moment("x", hours: 10), moment("y", hours: 15)]  // 11h → 15h
        #expect(Experiences.outings(apart).count == 2)
        var config = ClusterConfig()
        config.outingMaxGap = 5 * 3600
        #expect(Experiences.outings(apart, config: config).count == 1)
    }

    @Test func outingQualifiesByLandmarkOrPhotoCount() {
        #expect(Experiences.qualifies([moment("a", hours: 0, photos: 2, landmark: vessel)]))
        #expect(Experiences.qualifies([moment("a", hours: 0, photos: 4), moment("b", hours: 1, photos: 4)]))  // 8 photos
        #expect(!Experiences.qualifies([moment("a", hours: 0, photos: 7)]))
    }

    @Test func titlesFollowTemplates() {
        let trip = Trip(moments: [moment("k1", hours: 0, city: kyoto), moment("k2", hours: 30, city: kyoto)])
        let tripExperience = Experiences.build(trips: [trip], otherMoments: [], tags: noTags, calendar: utc)[0]
        #expect(tripExperience.title == "Exploring Kyoto")
        #expect(tripExperience.templateTitle == "Exploring Kyoto")
        #expect(tripExperience.place == "Kyoto")

        // Two most famous landmarks of the outing, in visit order.
        let deli = landmark("Some Deli", sitelinks: 5)
        let outing = Experiences.build(trips: [], otherMoments: [
            moment("a", hours: 9, landmark: vessel),
            moment("b", hours: 11, landmark: deli),
            moment("c", hours: 13, landmark: centralPark),
        ], tags: noTags, calendar: utc)[0]
        #expect(outing.title == "Vessel & Central Park")
        #expect(outing.place == "Manhattan")

        let daytime = Experiences.build(trips: [], otherMoments: [moment("d", hours: 10, photos: 9, city: jerseyCity)],
                                        tags: noTags, calendar: utc)[0]
        #expect(daytime.title == "A day in Jersey City")
    }

    @Test func worthinessUsesLogsAndWeights() {
        let moments = [
            moment("a", hours: 0, durationHours: 1, photos: 10, landmark: centralPark, kmFromHome: 6),
            moment("b", hours: 2, durationHours: 1, photos: 20, kmFromHome: 2),
        ]
        // 1.0·ln(1+87) + 1 (new city) + 0.5·ln(1+6) + 0.5·ln(1+30) + 0.5·ln(1+3 h)
        let expected = log1p(87) + 1 + 0.5 * log1p(6) + 0.5 * log1p(30) + 0.5 * log1p(3)
        #expect(abs(Experiences.worthiness(moments, novelty: .newCity) - expected) < 1e-9)

        var config = ClusterConfig()
        config.worthinessFameWeight = 0
        config.worthinessNewCityBonus = 0
        let withoutFame = 0.5 * log1p(6) + 0.5 * log1p(30) + 0.5 * log1p(3)
        #expect(abs(Experiences.worthiness(moments, novelty: .newCity, config: config) - withoutFame) < 1e-9)
    }

    @Test func distanceCannotDominate() {
        // Far away but plain (10,800 km, no landmark) vs. a famous place near home.
        let farTrip = Trip(moments: [moment("far", hours: 200, photos: 10, city: kyoto, kmFromHome: 10_800)])
        let famousOuting = [moment("park", hours: 10, durationHours: 3, photos: 30, landmark: centralPark, kmFromHome: 6)]
        let ranked = Experiences.build(trips: [farTrip], otherMoments: famousOuting, tags: noTags, home: home, calendar: utc)
        #expect(ranked.map(\.kind) == [.outing, .trip])
    }

    @Test func noveltyRewardsFirstVisitsButNotHome() {
        let items: [(id: String, start: Date, cities: [City])] = [
            (id: "home-day", start: day0, cities: [jerseyCity]),
            (id: "nyc-1", start: day0.addingTimeInterval(86_400), cities: [manhattan]),
            (id: "nyc-2", start: day0.addingTimeInterval(2 * 86_400), cities: [manhattan]),
            (id: "kyoto", start: day0.addingTimeInterval(3 * 86_400), cities: [kyoto]),
        ]
        let novelty = Experiences.novelty(items, home: home)
        #expect(novelty["home-day"] == Novelty.none)
        #expect(novelty["nyc-1"] == .newCity)
        #expect(novelty["nyc-2"] == Novelty.none)
        #expect(novelty["kyoto"] == .newCountry)
    }

    @Test func rankingBlendsMemorabilityOnlyWhenPresent() {
        let a = Experiences.make(id: "a", kind: .outing, moments: [moment("a", hours: 0, photos: 30, landmark: centralPark)], tags: noTags)
        let b = Experiences.make(id: "b", kind: .outing, moments: [moment("b", hours: 5, photos: 9)], tags: noTags)
        let c = Experiences.make(id: "c", kind: .outing, moments: [moment("c", hours: 9, photos: 15, landmark: vessel)], tags: noTags)

        // AI off: worthiness alone, normalized so the best is 1 and the worst 0.
        let plain = Ranking.rank([b, c, a], memorability: [:])
        #expect(plain.map(\.id) == ["a", "c", "b"])
        #expect(plain.first?.score == 1)
        #expect(plain.last?.score == 0)
        #expect(plain.allSatisfy { $0.memorability == nil })

        // With memorability: 0.7 × worthiness + 0.3 × (m − 1) / 9. b becomes as memorable as it gets.
        let blended = Ranking.rank([a, b, c], memorability: ["a": 1, "b": 10, "c": 1])
        let aScore = blended.first { $0.id == "a" }!.score
        let bScore = blended.first { $0.id == "b" }!.score
        #expect(abs(aScore - 0.7) < 1e-9)
        #expect(abs(bScore - 0.3) < 1e-9)
        #expect(blended.first { $0.id == "b" }?.memorability == 10)

        // An unrated experience keeps its normalized worthiness instead of being dragged down.
        let partial = Ranking.rank([a, b, c], memorability: ["b": 10])
        #expect(partial.first?.id == "a")
        #expect(partial.first?.score == 1)
    }

    @Test func categoryComesFromTopTags() {
        let culinary = Experiences.categories(tags: tags(["food": 2.0, "restaurant": 1.0, "street": 0.5]), landmarks: [])
        #expect(culinary == [.culinary, .city])

        let coast = Experiences.categories(tags: tags(["beach": 1.5, "ocean": 1.0, "sky": 3.0]), landmarks: [])
        #expect(coast == [.coast])  // "sky" maps to nothing
    }

    @Test func landmarkTypesAlsoVote() {
        let temple = landmark("Kiyomizu-dera", type: "Buddhist temple", sitelinks: 77)
        let result = Experiences.categories(tags: tags(["garden": 0.6]), landmarks: [temple, temple])
        #expect(result == [.culture, .nature])  // 2 temple moments (2.0) beat one garden tag (0.6)
    }

    @Test func noSignalFallsBackToDefaultCategory() {
        #expect(Experiences.categories(tags: .empty, landmarks: []) == [.city])
        var config = ClusterConfig()
        config.defaultCategory = .nature
        #expect(Experiences.categories(tags: .empty, landmarks: [], config: config) == [.nature])
    }

    @Test func coversSpreadAcrossMomentsAndHeroIsTheFamousOne() {
        let moments = [
            moment("a", hours: 0, photos: 3),
            moment("b", hours: 2, photos: 3, landmark: centralPark),
            moment("c", hours: 4, photos: 3),
        ]
        #expect(Experiences.coverIDs(moments, count: 3) == ["a-0", "b-1", "c-2"])
        #expect(Experiences.heroID(moments) == "b-1")
        #expect(Experiences.coverIDs([moment("x", hours: 0, photos: 2)], count: 3) == ["x-0", "x-1"])
    }

    @Test func durationText() {
        let start = day0.addingTimeInterval(10 * 3600)
        #expect(Experiences.durationText(from: start, to: start, calendar: utc) == "Quick stop")
        #expect(Experiences.durationText(from: start, to: start.addingTimeInterval(32 * 60), calendar: utc) == "~30 min")
        #expect(Experiences.durationText(from: start, to: start.addingTimeInterval(65 * 60), calendar: utc) == "~1 hr")
        #expect(Experiences.durationText(from: start, to: start.addingTimeInterval(2.6 * 3600), calendar: utc) == "~3 hrs")
        #expect(Experiences.durationText(from: start, to: start.addingTimeInterval(50 * 3600), calendar: utc) == "3 days")
    }
}
