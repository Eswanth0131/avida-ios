import Foundation
import Testing
@testable import Avida

struct PlaceLookupTests {
    private let english = Locale(identifier: "en_US")

    @Test func bundledDataLoads() throws {
        let lookup = try #require(PlaceLookup.shared)
        #expect(lookup.cities.count > 30_000)
    }

    @Test(arguments: [
        (40.728, -74.078, "Jersey City", "US"),     // home
        (48.853, 2.3499, "Paris", "FR"),            // Notre-Dame
        (35.6895, 139.6917, "Tokyo", "JP"),
        (-33.8568, 151.2153, "Sydney", "AU"),       // Opera House
        (40.758, -73.9855, "Manhattan", "US"),      // Times Square: neighborhood rows are filtered out
        (-16.8, -179.99, "Labasa", "FJ"),           // across the antimeridian from the city
    ])
    func nearestCityForKnownCoordinates(latitude: Double, longitude: Double, name: String, country: String) throws {
        let city = try #require(PlaceLookup.shared?.nearest(latitude: latitude, longitude: longitude))
        #expect(city.name == name)
        #expect(city.countryCode == country)
    }

    @Test func matchesBruteForceOnSmallList() {
        let cities = [
            City(name: "A", countryCode: "US", latitude: 10, longitude: 0, population: 1),
            City(name: "B", countryCode: "US", latitude: 0, longitude: 20, population: 1),
            City(name: "C", countryCode: "US", latitude: 0.5, longitude: 0.5, population: 1),
        ]
        let lookup = PlaceLookup(cities: cities)
        #expect(lookup.nearest(latitude: 0, longitude: 0)?.name == "C")
        #expect(lookup.nearest(latitude: 9, longitude: 0)?.name == "A")
        #expect(lookup.nearest(latitude: 0, longitude: 19)?.name == "B")
        #expect(PlaceLookup(cities: []).nearest(latitude: 0, longitude: 0) == nil)
    }

    @Test func countryNameComesFromLocale() {
        #expect(PlaceLookup.countryName("FR", locale: english) == "France")
        #expect(PlaceLookup.countryName("JP", locale: english) == "Japan")
    }

    // MARK: Trip labels

    private let boston = City(name: "Boston", countryCode: "US", latitude: 42.36, longitude: -71.06, population: 1)
    private let cambridge = City(name: "Cambridge", countryCode: "US", latitude: 42.37, longitude: -71.11, population: 1)
    private let montreal = City(name: "Montréal", countryCode: "CA", latitude: 45.51, longitude: -73.59, population: 1)

    private func trip(_ cities: [City]) -> Trip {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        return Trip(moments: cities.enumerated().map { index, city in
            Moment(id: "\(index)", photoIDs: ["\(index)"], representativeIDs: ["\(index)"], start: start, end: start,
                   latitude: city.latitude, longitude: city.longitude,
                   distanceFromHomeMeters: 300_000, city: city, landmark: nil)
        })
    }

    @Test func labelUsesMostCommonCity() {
        let label = trip([boston, boston, boston, boston, cambridge]).placeLabel(locale: english)  // Cambridge 20%
        #expect(label == "Boston, United States")
    }

    @Test func labelNamesTwoCitiesWhenBothHaveAQuarter() {
        let label = trip([boston, boston, boston, cambridge]).placeLabel(locale: english)  // Cambridge 25%
        #expect(label == "Boston & Cambridge, United States")
    }

    @Test func labelNamesBothCountriesWhenTheyDiffer() {
        let label = trip([montreal, montreal, boston, boston]).placeLabel(locale: english)
        #expect(label == "Boston, United States & Montréal, Canada")
    }
}
