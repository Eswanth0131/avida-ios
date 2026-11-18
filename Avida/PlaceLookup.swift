import Foundation

nonisolated struct City: Sendable, Hashable {
    let name: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let population: Int
}

/// Offline nearest-city lookup over the bundled GeoNames cities15000 data (cities.tsv).
/// No network: data ships in the app, country names come from Locale.
nonisolated final class PlaceLookup: Sendable {
    /// Loaded once, on first use, from the app bundle. Nil only if cities.tsv is missing.
    static let shared: PlaceLookup? = {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return PlaceLookup(cities: parse(text))
    }()

    /// Sorted by latitude, so a search only has to look at a narrow band.
    let cities: [City]

    init(cities: [City]) {
        self.cities = cities.sorted { $0.latitude < $1.latitude }
    }

    /// Lines of: name, country code, latitude, longitude, population (tab-separated).
    static func parse(_ text: String) -> [City] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 5,
                  let latitude = Double(fields[2]),
                  let longitude = Double(fields[3]) else { return nil }
            return City(
                name: String(fields[0]),
                countryCode: String(fields[1]),
                latitude: latitude,
                longitude: longitude,
                population: Int(fields[4]) ?? 0
            )
        }
    }

    func nearest(latitude: Double, longitude: Double) -> City? {
        // Any city whose latitude alone is farther than the best match can't beat it,
        // so scan outwards from the target latitude and stop each side at that bound.
        let earthRadius = 6_371_000.0
        func latitudeBound(_ city: City) -> Double {
            earthRadius * abs(city.latitude - latitude) * .pi / 180
        }

        var best: (city: City, meters: Double)?
        func consider(_ city: City) {
            let meters = Clustering.distanceMeters((latitude, longitude), (city.latitude, city.longitude))
            if best == nil || meters < best!.meters { best = (city, meters) }
        }

        var up = firstIndex(atOrAbove: latitude)
        var down = up - 1
        while up < cities.count || down >= 0 {
            if up < cities.count {
                if let best, latitudeBound(cities[up]) >= best.meters { up = cities.count } else { consider(cities[up]); up += 1 }
            }
            if down >= 0 {
                if let best, latitudeBound(cities[down]) >= best.meters { down = -1 } else { consider(cities[down]); down -= 1 }
            }
        }
        return best?.city
    }

    static func countryName(_ code: String, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    private func firstIndex(atOrAbove latitude: Double) -> Int {
        var low = 0, high = cities.count
        while low < high {
            let mid = (low + high) / 2
            if cities[mid].latitude < latitude { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

/// Shared naming rules for trips and experiences.
nonisolated enum PlaceNaming {
    /// Cities by how many moments they hold, most first; ties alphabetical.
    static func rankedCities(_ moments: [Moment]) -> [(city: City, count: Int)] {
        var counts: [City: Int] = [:]
        for case let city? in moments.map(\.city) { counts[city, default: 0] += 1 }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.name < $1.key.name }
            .map { (city: $0.key, count: $0.value) }
    }

    /// The main city, plus a second one if it holds at least `tripSecondCityMinShare` of the moments.
    static func mainCities(_ moments: [Moment], config: ClusterConfig = .standard) -> [City] {
        let ranked = rankedCities(moments)
        guard let top = ranked.first?.city else { return [] }
        if ranked.count > 1, Double(ranked[1].count) >= config.tripSecondCityMinShare * Double(moments.count) {
            return [top, ranked[1].city]
        }
        return [top]
    }

    /// The `count` most famous matched landmarks (by sitelinks), returned in visit order.
    static func famousLandmarks(_ moments: [Moment], count: Int) -> [Landmark] {
        let famous = Set(Set(moments.compactMap(\.landmark))
            .sorted { $0.sitelinks != $1.sitelinks ? $0.sitelinks > $1.sitelinks : $0.name < $1.name }
            .prefix(count))
        var inVisitOrder: [Landmark] = []
        for case let landmark? in moments.sorted(by: { $0.start < $1.start }).map(\.landmark)
        where famous.contains(landmark) && !inVisitOrder.contains(landmark) {
            inVisitOrder.append(landmark)
        }
        return inVisitOrder
    }
}

extension Trip {
    /// With matched landmarks: the most famous ones (by sitelinks) in visit order, plus the main city,
    /// e.g. "Vessel & Central Park, Manhattan".
    /// Without: "Paris, France", or "Boston & Cambridge, United States" when two cities each hold
    /// at least `tripSecondCityMinShare` of the trip's moments.
    nonisolated func placeLabel(config: ClusterConfig = .standard, locale: Locale = .current) -> String {
        let landmarks = PlaceNaming.famousLandmarks(moments, count: config.tripLandmarksInLabel)
        let cities = PlaceNaming.mainCities(moments, config: config)
        if !landmarks.isEmpty {
            let names = landmarks.map(\.name).joined(separator: " & ")
            return cities.first.map { "\(names), \($0.name)" } ?? names
        }

        guard let top = cities.first else { return "Unknown place" }
        func country(_ city: City) -> String { PlaceLookup.countryName(city.countryCode, locale: locale) }
        if cities.count > 1 {
            let second = cities[1]
            if top.countryCode == second.countryCode {
                return "\(top.name) & \(second.name), \(country(top))"
            }
            return "\(top.name), \(country(top)) & \(second.name), \(country(second))"
        }
        return "\(top.name), \(country(top))"
    }
}
