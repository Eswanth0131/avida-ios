import Foundation

/// A photo reduced to what clustering needs. No PhotoKit types, so this is easy to test.
nonisolated struct PhotoPoint: Sendable, Hashable {
    let id: String
    let date: Date
    let latitude: Double?
    let longitude: Double?

    var hasLocation: Bool { latitude != nil && longitude != nil }
}

nonisolated struct Moment: Sendable, Identifiable, Hashable {
    let id: String
    /// All photos in the moment, chronological.
    let photoIDs: [String]
    /// Up to 5 photos spread through the moment's time range (see RepresentativePhotos).
    let representativeIDs: [String]
    let start: Date
    let end: Date
    /// Average location of the moment's GPS photos.
    let latitude: Double
    let longitude: Double
    /// Used for trip logic only; not shown on screen.
    let distanceFromHomeMeters: Double
    /// Nearest city to the moment's location, if a lookup was provided.
    let city: City?
    /// Best landmark near the moment's GPS photos; nil means show the city instead.
    let landmark: Landmark?
}

nonisolated struct Trip: Sendable, Identifiable, Equatable {
    let moments: [Moment]

    var id: String { moments[0].id }
    var start: Date { moments.map(\.start).min()! }
    var end: Date { moments.map(\.end).max()! }
    var photoCount: Int { moments.reduce(0) { $0 + $1.photoIDs.count } }
    /// Farthest moment from home, i.e. roughly how far the trip went.
    var distanceFromHomeMeters: Double { moments.map(\.distanceFromHomeMeters).max()! }
}

nonisolated struct ClusterResult: Sendable, Equatable {
    let trips: [Trip]
    let otherMoments: [Moment]
    let unassignedPhotoIDs: [String]
}

nonisolated enum Clustering {
    /// Maps a coordinate to its nearest city, e.g. `PlaceLookup.nearest`. Injected so tests can stub it.
    typealias CityLookup = @Sendable (_ latitude: Double, _ longitude: Double) -> City?
    /// Maps a moment's GPS photo coordinates to its best landmark, e.g. `LandmarkLookup.match`.
    typealias LandmarkLookupFunction = @Sendable (_ points: [(latitude: Double, longitude: Double)]) -> Landmark?

    static func cluster(
        _ photos: [PhotoPoint],
        config: ClusterConfig = .standard,
        nearestCity: CityLookup? = nil,
        bestLandmark: LandmarkLookupFunction? = nil
    ) -> ClusterResult {
        let (moments, unassigned) = makeMoments(photos, config: config, nearestCity: nearestCity, bestLandmark: bestLandmark)
        let (trips, other) = groupTrips(moments, config: config)
        return ClusterResult(trips: trips, otherMoments: other, unassignedPhotoIDs: unassigned)
    }

    /// Splits GPS photos into moments on time or distance jumps, then attaches non-GPS photos.
    static func makeMoments(
        _ photos: [PhotoPoint],
        config: ClusterConfig = .standard,
        nearestCity: CityLookup? = nil,
        bestLandmark: LandmarkLookupFunction? = nil
    ) -> (moments: [Moment], unassigned: [String]) {
        let located = photos.filter(\.hasLocation).sorted(by: chronological)
        let unlocated = photos.filter { !$0.hasLocation }.sorted(by: chronological)

        var groups: [[PhotoPoint]] = []
        for photo in located {
            if let previous = groups.last?.last,
               photo.date.timeIntervalSince(previous.date) <= config.momentMaxGap,
               distanceMeters(previous, photo) <= config.momentMaxDistanceMeters {
                groups[groups.count - 1].append(photo)
            } else {
                groups.append([photo])
            }
        }

        // Match against the GPS-only time ranges so the result doesn't depend on attach order.
        var extras = Array(repeating: [PhotoPoint](), count: groups.count)
        var unassigned: [String] = []
        // Groups come out in time order without overlapping, so the nearest one is next to where the photo's date
        // would be inserted: binary search instead of checking every group (whole libraries have thousands).
        let starts = groups.map { $0.first!.date }
        func gap(_ index: Int, _ date: Date) -> TimeInterval {
            timeGap(date, start: groups[index].first!.date, end: groups[index].last!.date)
        }
        for photo in unlocated {
            var best: (index: Int, gap: TimeInterval)?
            if !groups.isEmpty {
                var low = 0, high = starts.count  // first group starting after the photo
                while low < high {
                    let mid = (low + high) / 2
                    if starts[mid] <= photo.date { low = mid + 1 } else { high = mid }
                }
                for index in [low - 1, low] where groups.indices.contains(index) {
                    let g = gap(index, photo.date)
                    if best == nil || g < best!.gap { best = (index, g) }
                }
                // Same tie-break as a full scan: the earliest group with the smallest gap.
                while let current = best, current.index > 0, gap(current.index - 1, photo.date) == current.gap {
                    best = (current.index - 1, current.gap)
                }
            }
            if let best, best.gap <= config.unlocatedMaxGap {
                extras[best.index].append(photo)
            } else {
                unassigned.append(photo.id)
            }
        }

        let home = (config.homeLatitude, config.homeLongitude)
        let moments = groups.indices.map { index -> Moment in
            let gps = groups[index]
            let all = (gps + extras[index]).sorted(by: chronological)
            let latitude = gps.map { $0.latitude! }.reduce(0, +) / Double(gps.count)
            let longitude = gps.map { $0.longitude! }.reduce(0, +) / Double(gps.count)
            return Moment(
                id: all[0].id,
                photoIDs: all.map(\.id),
                representativeIDs: RepresentativePhotos.pick(all, maxCount: config.representativesPerMoment).map(\.id),
                start: all.first!.date,
                end: all.last!.date,
                latitude: latitude,
                longitude: longitude,
                distanceFromHomeMeters: distanceMeters(home, (latitude, longitude)),
                city: nearestCity?(latitude, longitude),
                landmark: bestLandmark?(gps.map { (latitude: $0.latitude!, longitude: $0.longitude!) })
            )
        }
        return (moments, unassigned)
    }

    /// Runs of consecutive away moments become trips; a home moment or a long gap ends the run.
    static func groupTrips(_ moments: [Moment], config: ClusterConfig = .standard) -> (trips: [Trip], other: [Moment]) {
        var trips: [Trip] = []
        var other: [Moment] = []
        var run: [Moment] = []

        func closeRun() {
            if !run.isEmpty { trips.append(Trip(moments: run)) }
            run = []
        }

        for moment in moments.sorted(by: { $0.start < $1.start }) {
            if moment.distanceFromHomeMeters > config.tripMinDistanceFromHomeMeters {
                if let last = run.last, moment.start.timeIntervalSince(last.end) >= config.tripMaxGapBetweenMoments {
                    closeRun()
                }
                run.append(moment)
            } else {
                closeRun()
                other.append(moment)
            }
        }
        closeRun()
        return (trips, other)
    }

    /// Great-circle distance (haversine), accurate enough at these scales.
    static func distanceMeters(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = a.0 * .pi / 180, lat2 = b.0 * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.1 - a.1) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    private static func distanceMeters(_ a: PhotoPoint, _ b: PhotoPoint) -> Double {
        distanceMeters((a.latitude!, a.longitude!), (b.latitude!, b.longitude!))
    }

    /// 0 if the date falls inside the range, otherwise the distance to the nearer end.
    private static func timeGap(_ date: Date, start: Date, end: Date) -> TimeInterval {
        if date < start { return start.timeIntervalSince(date) }
        if date > end { return date.timeIntervalSince(end) }
        return 0
    }

    private static func chronological(_ a: PhotoPoint, _ b: PhotoPoint) -> Bool {
        a.date == b.date ? a.id < b.id : a.date < b.date
    }
}
