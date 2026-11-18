import Foundation
import Testing
@testable import Avida

/// Made-up landmarks around a point in Manhattan. 1° latitude ≈ 111 km.
private let origin = (latitude: 40.7500, longitude: -73.9900)

private func north(_ meters: Double) -> (latitude: Double, longitude: Double) {
    (origin.latitude + meters / 111_000, origin.longitude)
}

private func landmark(_ name: String, type: String = "building", sitelinks: Int, metersNorth: Double) -> Landmark {
    let point = north(metersNorth)
    return Landmark(qid: "Q-\(name)", name: name, description: "made up", type: type,
                    latitude: point.latitude, longitude: point.longitude, sitelinks: sitelinks)
}

struct LandmarkMatchingTests {
    @Test func defaultRadiusIs250Meters() {
        let near = landmark("Near", sitelinks: 10, metersNorth: 200)
        let far = landmark("Far", sitelinks: 10, metersNorth: 300)
        #expect(LandmarkMatching.best(near: [origin], among: [near]) == near)
        #expect(LandmarkMatching.best(near: [origin], among: [far]) == nil)
    }

    @Test func bigAreasGetTheWiderRadius() {
        let park = landmark("Park", type: "urban park", sitelinks: 10, metersNorth: 800)
        let beach = landmark("Beach", type: "beach", sitelinks: 10, metersNorth: 900)
        let tooFar = landmark("Island", type: "tidal island", sitelinks: 10, metersNorth: 1_100)
        #expect(LandmarkMatching.radius(for: park) == 1_000)
        #expect(LandmarkMatching.best(near: [origin], among: [park]) == park)
        #expect(LandmarkMatching.best(near: [origin], among: [beach]) == beach)
        #expect(LandmarkMatching.best(near: [origin], among: [tooFar]) == nil)
    }

    @Test func typeWordsAreMatchedWhole() {
        // "parking garage" must not count as a park.
        let garage = landmark("Garage", type: "parking garage", sitelinks: 10, metersNorth: 0)
        #expect(LandmarkMatching.radius(for: garage) == 250)
    }

    @Test func moreFamousWinsAtSimilarDistance() {
        let famous = landmark("Famous", sitelinks: 80, metersNorth: 100)
        let obscure = landmark("Obscure", sitelinks: 8, metersNorth: 90)
        #expect(LandmarkMatching.best(near: [origin], among: [obscure, famous]) == famous)
    }

    @Test func distanceReducesTheScore() {
        // Same fame: the closer one wins.
        let close = landmark("Close", sitelinks: 20, metersNorth: 20)
        let edge = landmark("Edge", sitelinks: 20, metersNorth: 240)
        #expect(LandmarkMatching.best(near: [origin], among: [edge, close]) == close)
        // At the edge the score drops to a quarter: 30 sitelinks right here beat 100 at the edge.
        let nearby = landmark("Nearby", sitelinks: 30, metersNorth: 0)
        let famousAtEdge = landmark("FamousAtEdge", sitelinks: 100, metersNorth: 249)
        #expect(LandmarkMatching.best(near: [origin], among: [famousAtEdge, nearby]) == nearby)
    }

    @Test func stationsAreDownWeighted() {
        let station = landmark("Station", type: "railway station", sitelinks: 50, metersNorth: 50)
        let temple = landmark("Temple", type: "Buddhist temple", sitelinks: 20, metersNorth: 100)
        #expect(LandmarkMatching.best(near: [origin], among: [station, temple]) == temple)
    }

    @Test func nearestPhotoInTheMomentCounts() {
        // Far from the first photo but right next to the second one.
        let target = landmark("Target", sitelinks: 10, metersNorth: 2_000)
        #expect(LandmarkMatching.best(near: [origin, north(1_950)], among: [target]) == target)
    }

    @Test func lookupFindsCandidatesInRangeOnly() {
        let lookup = LandmarkLookup(landmarks: [
            landmark("A", sitelinks: 10, metersNorth: 100),
            landmark("B", sitelinks: 10, metersNorth: 900),
            landmark("C", sitelinks: 10, metersNorth: 5_000),
        ])
        let names = lookup.candidates(nearLatitude: origin.latitude, longitude: origin.longitude, within: 1_000).map(\.name)
        #expect(Set(names) == ["A", "B"])
        #expect(lookup.match([origin])?.name == "A")  // B is a plain building at 900 m: outside 250 m
    }

    @Test func noMatchFallsBackToCity() {
        let city = City(name: "Jersey City", countryCode: "US", latitude: 40.72, longitude: -74.07, population: 1)
        let photos = [PhotoPoint(id: "a", date: Date(timeIntervalSince1970: 0), latitude: origin.latitude, longitude: origin.longitude)]
        let lookup = LandmarkLookup(landmarks: [landmark("Far", sitelinks: 99, metersNorth: 5_000)])
        let (moments, _) = Clustering.makeMoments(photos, nearestCity: { _, _ in city }, bestLandmark: { lookup.match($0) })
        #expect(moments[0].landmark == nil)
        #expect(moments[0].city == city)
    }

    @Test func bundledLandmarksLoadAndMatchKnownPlaces() throws {
        let lookup = try #require(LandmarkLookup.shared)
        #expect(lookup.landmarks.count > 5_000)
        // Standing at the foot of the Statue of Liberty.
        #expect(lookup.match([(latitude: 40.6893, longitude: -74.0446)])?.name == "Statue of Liberty")
        // On the Great Lawn: Central Park (a big area) beats the smaller Great Lawn item next to it.
        #expect(lookup.match([(latitude: 40.7812, longitude: -73.9665)])?.name == "Central Park")
        #expect(lookup.match([(latitude: 34.9671, longitude: 135.7727)])?.name == "Fushimi Inari-taisha")
        // Your home: nothing within range, so the moment shows Jersey City.
        #expect(lookup.match([(latitude: 40.728, longitude: -74.078)]) == nil)
    }
}

struct TripLandmarkLabelTests {
    private let manhattan = City(name: "Manhattan", countryCode: "US", latitude: 40.78, longitude: -73.97, population: 1)

    private func moment(_ id: String, hours: Double, landmark: Landmark?) -> Moment {
        let date = Date(timeIntervalSince1970: hours * 3600)
        return Moment(id: id, photoIDs: [id], representativeIDs: [id], start: date, end: date,
                      latitude: 40.75, longitude: -73.99, distanceFromHomeMeters: 60_000,
                      city: manhattan, landmark: landmark)
    }

    @Test func labelUsesTwoMostFamousLandmarksInVisitOrderPlusCity() {
        let vessel = landmark("Vessel", sitelinks: 19, metersNorth: 0)
        let park = landmark("Central Park", type: "urban park", sitelinks: 87, metersNorth: 0)
        let deli = landmark("Some Deli", sitelinks: 5, metersNorth: 0)
        let trip = Trip(moments: [
            moment("1", hours: 0, landmark: vessel),
            moment("2", hours: 3, landmark: deli),
            moment("3", hours: 6, landmark: park),
            moment("4", hours: 9, landmark: nil),
        ])
        #expect(trip.placeLabel() == "Vessel & Central Park, Manhattan")
    }

    @Test func labelFallsBackToCitiesWithoutLandmarks() {
        let trip = Trip(moments: [moment("1", hours: 0, landmark: nil)])
        #expect(trip.placeLabel(locale: Locale(identifier: "en_US")) == "Manhattan, United States")
    }
}
