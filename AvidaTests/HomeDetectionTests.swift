import Foundation
import Testing
@testable import Avida

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private let day0 = Date(timeIntervalSince1970: 1_780_272_000)  // 2026-06-01 UTC
private let homeSpot = (latitude: 51.5007, longitude: -0.1246)   // somewhere that isn't the developer's home
private let tripSpot = (latitude: 35.0116, longitude: 135.7681)

private func photo(_ id: String, day: Double, at spot: (latitude: Double, longitude: Double)?, nudge: Double = 0) -> PhotoPoint {
    PhotoPoint(id: id, date: day0.addingTimeInterval(day * 86_400),
               latitude: spot.map { $0.latitude + nudge }, longitude: spot.map { $0.longitude + nudge })
}

struct HomeDetectionTests {
    @Test func homeIsWherePhotosAreTakenOnTheMostDays() throws {
        // 6 ordinary days at home, a few photos each…
        var photos = (0..<6).map { photo("h\($0)", day: Double($0 * 3), at: homeSpot, nudge: Double($0) * 0.001) }
        // …beat one huge trip day with 200 photos.
        photos += (0..<200).map { photo("t\($0)", day: 40, at: tripSpot) }
        let home = try #require(HomeDetection.detect(photos, calendar: utc))
        #expect(abs(home.latitude - (homeSpot.latitude + 0.0025)) < 1e-9)   // average of the home photos
        #expect(abs(home.longitude - (homeSpot.longitude + 0.0025)) < 1e-9)
    }

    @Test func sameDayCountGoesToMorePhotos() throws {
        let photos = [
            photo("a1", day: 0, at: homeSpot), photo("a2", day: 1, at: homeSpot),
            photo("b1", day: 0, at: tripSpot), photo("b2", day: 1, at: tripSpot), photo("b3", day: 1, at: tripSpot),
        ]
        let home = try #require(HomeDetection.detect(photos, calendar: utc))
        #expect(abs(home.latitude - tripSpot.latitude) < 1e-9)
    }

    @Test func homeOnACellEdgeIsNotSplitInTwo() throws {
        // Home straddles the 0.02° grid line at longitude 0.00: 3 days just west, 3 days just east.
        // A trip spot has 4 days. Scored alone, each home half (3) would lose; with neighbours, home has 6.
        let edge = (latitude: 51.51, longitude: 0.0)
        var photos = (0..<3).map { photo("w\($0)", day: Double($0), at: (edge.latitude, edge.longitude - 0.001)) }
        photos += (3..<6).map { photo("e\($0)", day: Double($0), at: (edge.latitude, edge.longitude + 0.001)) }
        photos += (10..<14).map { photo("t\($0)", day: Double($0), at: tripSpot) }
        let home = try #require(HomeDetection.detect(photos, cellDegrees: 0.02, calendar: utc))
        #expect(abs(home.latitude - edge.latitude) < 1e-9)
        #expect(abs(home.longitude - edge.longitude) < 1e-9)
    }

    @Test func noGPSMeansNoHome() {
        #expect(HomeDetection.detect([photo("x", day: 0, at: nil), photo("y", day: 1, at: nil)], calendar: utc) == nil)
        #expect(HomeDetection.detect([], calendar: utc) == nil)
    }

    @Test func nearbyPhotosShareOneCellAndFarOnesDont() throws {
        // ~1 km apart (same 0.02° cell) on 3 days vs. ~6 km away on 2 days.
        let photos = [
            photo("n1", day: 0, at: homeSpot), photo("n2", day: 1, at: homeSpot, nudge: 0.005), photo("n3", day: 2, at: homeSpot, nudge: 0.008),
            photo("f1", day: 3, at: homeSpot, nudge: 0.06), photo("f2", day: 4, at: homeSpot, nudge: 0.06),
        ]
        let home = try #require(HomeDetection.detect(photos, cellDegrees: 0.02, calendar: utc))
        #expect(home.latitude < homeSpot.latitude + 0.01)
    }

    @Test func detectedHomeFindsItsCity() throws {
        let home = try #require(HomeDetection.detect([photo("l", day: 0, at: homeSpot)], calendar: utc))
        #expect(PlaceLookup.shared?.nearest(latitude: home.latitude, longitude: home.longitude)?.countryCode == "GB")
    }
}

struct UserPrefsTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "UserPrefsTests-\(UUID().uuidString)")! }

    @Test func startsEmptyWithNothingHardCoded() {
        let prefs = UserPrefs(defaults: defaults())
        #expect(prefs.displayName == nil)  // Profile shows "Your profile"
        #expect(prefs.homeOverride == nil)
    }

    @Test func choicesAreRemembered() {
        let store = defaults()
        let prefs = UserPrefs(defaults: store)
        prefs.userName = "  Sam  "
        prefs.homeOverride = HomeOverride(latitude: 1, longitude: 2)

        let reloaded = UserPrefs(defaults: store)
        #expect(reloaded.displayName == "Sam")
        #expect(reloaded.homeOverride == HomeOverride(latitude: 1, longitude: 2))

        reloaded.homeOverride = nil
        reloaded.userName = "   "
        #expect(UserPrefs(defaults: store).homeOverride == nil)
        #expect(UserPrefs(defaults: store).displayName == nil)
    }
}
