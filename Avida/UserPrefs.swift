import Foundation

/// A home the user set by hand in Settings (instead of the one detected from their photos).
nonisolated struct HomeOverride: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double
}

/// Choices made in Settings, saved in UserDefaults. Nothing here is hard-coded to one person.
@Observable
final class UserPrefs {
    static let shared = UserPrefs()

    @ObservationIgnored private let defaults: UserDefaults

    /// Shown on Profile; set in Settings. Empty → "Your profile".
    var userName: String { didSet { defaults.set(userName, forKey: Keys.userName) } }
    var homeOverride: HomeOverride? {
        didSet { defaults.set(homeOverride.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.homeOverride) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        userName = defaults.string(forKey: Keys.userName) ?? ""
        homeOverride = defaults.data(forKey: Keys.homeOverride).flatMap { try? JSONDecoder().decode(HomeOverride.self, from: $0) }
    }

    /// The name to show, or nil when none is set.
    var displayName: String? {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum Keys {
        static let userName = "avida.userName"
        static let homeOverride = "avida.homeOverride"
    }
}

/// Finds home from the scanned photos. Pure, unit tested.
nonisolated enum HomeDetection {
    /// The place where photos were taken on the most different days; ties go to more photos. Photos are put in
    /// cells about `cellDegrees` wide, and each cell is scored with its 8 neighbours, so a home that sits on a
    /// cell edge isn't split in two. Counting days, not photos, stops one big trip day from beating everyday life
    /// at home. Returns the average position of the winning neighbourhood's photos, or nil with no GPS photos.
    static func detect(_ points: [PhotoPoint], cellDegrees: Double = ClusterConfig.standard.homeDetectionCellDegrees,
                       calendar: Calendar = .current) -> Coordinate? {
        struct Cell: Hashable { let x: Int; let y: Int }
        var days: [Cell: Set<Date>] = [:]
        var located: [Cell: [(Double, Double)]] = [:]
        for point in points {
            guard let latitude = point.latitude, let longitude = point.longitude else { continue }
            let cell = Cell(x: Int((longitude / cellDegrees).rounded(.down)), y: Int((latitude / cellDegrees).rounded(.down)))
            days[cell, default: []].insert(calendar.startOfDay(for: point.date))
            located[cell, default: []].append((latitude, longitude))
        }
        func neighbourhood(_ cell: Cell) -> [Cell] {
            (-1...1).flatMap { dx in (-1...1).map { dy in Cell(x: cell.x + dx, y: cell.y + dy) } }
        }
        func dayCount(_ cell: Cell) -> Int { neighbourhood(cell).reduce(into: Set<Date>()) { $0.formUnion(days[$1] ?? []) }.count }
        func photoCount(_ cell: Cell) -> Int { neighbourhood(cell).reduce(0) { $0 + (located[$1]?.count ?? 0) } }

        guard let best = located.keys.max(by: { a, b in
            let da = dayCount(a), db = dayCount(b)
            if da != db { return da < db }
            let pa = photoCount(a), pb = photoCount(b)
            if pa != pb { return pa < pb }
            return (a.y, a.x) > (b.y, b.x)  // deterministic final tie-break
        }) else { return nil }
        let photos = neighbourhood(best).flatMap { located[$0] ?? [] }
        let count = Double(photos.count)
        return Coordinate(latitude: photos.reduce(0) { $0 + $1.0 } / count, longitude: photos.reduce(0) { $0 + $1.1 } / count)
    }
}
