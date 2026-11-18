import Foundation
import Testing
@testable import Avida

/// Made-up photos. Home is Jersey City (config default); "Boston" is ~300 km away.
private let base = Date(timeIntervalSince1970: 1_780_000_000)
private let home = (40.728, -74.078)
private let boston = (42.360, -71.058)

private func photo(_ id: String, hours: Double, at place: (Double, Double)?) -> PhotoPoint {
    PhotoPoint(id: id, date: base.addingTimeInterval(hours * 3600), latitude: place?.0, longitude: place?.1)
}

/// Shift a place north by roughly `km` kilometres.
private func north(_ place: (Double, Double), km: Double) -> (Double, Double) {
    (place.0 + km / 111.0, place.1)
}

struct ClusteringTests {
    @Test func emptyAlbumGivesNothing() {
        let result = Clustering.cluster([])
        #expect(result.trips.isEmpty)
        #expect(result.otherMoments.isEmpty)
        #expect(result.unassignedPhotoIDs.isEmpty)
    }

    @Test func timeGapOverThreeHoursStartsNewMoment() {
        let photos = [
            photo("a", hours: 0, at: home),
            photo("b", hours: 1, at: home),
            photo("c", hours: 2.5, at: home),   // 1.5 h after b: same moment
            photo("d", hours: 6, at: home),     // 3.5 h after c: new moment
        ]
        let (moments, _) = Clustering.makeMoments(photos)
        #expect(moments.map(\.photoIDs) == [["a", "b", "c"], ["d"]])
    }

    @Test func distanceOverTwoKmStartsNewMoment() {
        let photos = [
            photo("a", hours: 0, at: home),
            photo("b", hours: 0.5, at: north(home, km: 1)),  // 1 km: same moment
            photo("c", hours: 1, at: north(home, km: 4)),    // 3 km from b: new moment
        ]
        let (moments, _) = Clustering.makeMoments(photos)
        #expect(moments.map(\.photoIDs) == [["a", "b"], ["c"]])
    }

    @Test func noGPSPhotoJoinsNearestMomentInTime() {
        let photos = [
            photo("a", hours: 0, at: home),
            photo("b", hours: 1, at: home),
            photo("c", hours: 10, at: home),
            photo("x", hours: 2.5, at: nil),   // 1.5 h after b, 7.5 h before c
            photo("y", hours: 0.5, at: nil),   // inside the first moment
        ]
        let (moments, unassigned) = Clustering.makeMoments(photos)
        #expect(moments.map(\.photoIDs) == [["a", "y", "b", "x"], ["c"]])
        #expect(moments[0].end == base.addingTimeInterval(2.5 * 3600))
        #expect(unassigned.isEmpty)
    }

    @Test func noGPSPhotoFarFromEveryMomentIsUnassigned() {
        let photos = [
            photo("a", hours: 0, at: home),
            photo("x", hours: 5, at: nil),
            photo("z", hours: 100, at: nil),
        ]
        let result = Clustering.cluster(photos)
        #expect(result.unassignedPhotoIDs == ["x", "z"])
        #expect(result.otherMoments.map(\.photoIDs) == [["a"]])
    }

    @Test func awayMomentsWithinTwoDaysFormOneTrip() {
        let photos = [
            photo("home1", hours: 0, at: home),
            photo("bos1", hours: 10, at: boston),
            photo("bos2", hours: 30, at: north(boston, km: 5)),   // next day, different spot
            photo("bos3", hours: 60, at: boston),                 // 30 h later: still under 2 days
            photo("home2", hours: 80, at: home),
        ]
        let result = Clustering.cluster(photos)
        #expect(result.trips.count == 1)
        #expect(result.trips[0].moments.count == 3)
        #expect(result.trips[0].photoCount == 3)
        #expect(result.trips[0].distanceFromHomeMeters > 250_000)
        #expect(result.otherMoments.map(\.id) == ["home1", "home2"])
    }

    @Test func homeMomentOrLongGapSplitsTrips() {
        let photos = [
            photo("bos1", hours: 0, at: boston),
            photo("home", hours: 12, at: home),       // back home in between: ends the trip
            photo("bos2", hours: 24, at: boston),
            photo("bos3", hours: 24 + 72, at: boston), // 3 days later, no home photo: still a new trip
        ]
        let result = Clustering.cluster(photos)
        #expect(result.trips.map { $0.moments.map(\.id) } == [["bos1"], ["bos2"], ["bos3"]])
        #expect(result.otherMoments.map(\.id) == ["home"])
    }

    @Test func nearbyDayOutIsNotATrip() {
        // ~30 km away: under the 50 km threshold.
        let photos = [photo("a", hours: 0, at: north(home, km: 30))]
        let result = Clustering.cluster(photos)
        #expect(result.trips.isEmpty)
        #expect(result.otherMoments.count == 1)
    }
}

struct WholeLibraryTests {
    /// The old linear search, kept here as the reference the binary search must match.
    private func reference(_ photos: [PhotoPoint]) -> (moments: [[String]], unassigned: [String]) {
        let located = photos.filter(\.hasLocation).sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        let groups = Clustering.makeMoments(located).moments.map { $0 }
        var extras = Array(repeating: [String](), count: groups.count)
        var unassigned: [String] = []
        for photo in photos.filter({ !$0.hasLocation }).sorted(by: { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }) {
            var best: (index: Int, gap: TimeInterval)?
            for (index, group) in groups.enumerated() {
                let gap = photo.date < group.start ? group.start.timeIntervalSince(photo.date)
                    : (photo.date > group.end ? photo.date.timeIntervalSince(group.end) : 0)
                if best == nil || gap < best!.gap { best = (index, gap) }
            }
            if let best, best.gap <= ClusterConfig.standard.unlocatedMaxGap { extras[best.index].append(photo.id) } else { unassigned.append(photo.id) }
        }
        return (groups.indices.map { Set(groups[$0].photoIDs + extras[$0]).sorted() }, unassigned)
    }

    @Test func binarySearchMatchesTheFullScan() {
        // A deterministic "library": bursts in a few places over months, with and without GPS.
        var generator = SplitMix(seed: 42)
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let places = [(40.728, -74.078), (40.78, -73.97), (35.01, 135.77)]
        let photos: [PhotoPoint] = (0..<1_500).map { index in
            let hours = Double(generator.next() % 4_000) + Double(generator.next() % 60) / 60
            let place = places[Int(generator.next() % 3)]
            let hasGPS = generator.next() % 3 != 0
            return PhotoPoint(id: "p\(index)", date: base.addingTimeInterval(hours * 3600),
                              latitude: hasGPS ? place.0 : nil, longitude: hasGPS ? place.1 : nil)
        }
        let fast = Clustering.makeMoments(photos)
        let expected = reference(photos)
        #expect(fast.moments.map { Set($0.photoIDs).sorted() } == expected.moments)
        #expect(fast.unassigned.sorted() == expected.unassigned.sorted())
    }

    @Test func tiesGoToTheEarlierMomentLikeBefore() {
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let photos = [
            PhotoPoint(id: "a", date: base, latitude: 40.7, longitude: -74.0),
            PhotoPoint(id: "b", date: base.addingTimeInterval(4 * 3600), latitude: 40.7, longitude: -74.0),
            PhotoPoint(id: "x", date: base.addingTimeInterval(2 * 3600), latitude: nil, longitude: nil),  // 2 h from both
        ]
        let (moments, _) = Clustering.makeMoments(photos)
        #expect(moments.map(\.photoIDs) == [["a", "x"], ["b"]])
    }

    @Test func ringIsOnlyFullWhenReady() {
        #expect(ScanProgress.overall(phase: .idle, reading: 0, tagged: 0, toTag: 0, titling: 0, isReady: false) == 0)
        #expect(abs(ScanProgress.overall(phase: .reading, reading: 0.5, tagged: 0, toTag: 0, titling: 0, isReady: false) - 0.15) < 1e-9)
        #expect(abs(ScanProgress.overall(phase: .tagging, reading: 1, tagged: 50, toTag: 100, titling: 0, isReady: false) - 0.575) < 1e-9)
        #expect(abs(ScanProgress.overall(phase: .titling, reading: 1, tagged: 100, toTag: 100, titling: 0.5, isReady: false) - 0.925) < 1e-9)
        #expect(ScanProgress.overall(phase: .done, reading: 1, tagged: 100, toTag: 100, titling: 1, isReady: false) == 0.99)
        #expect(ScanProgress.overall(phase: .done, reading: 1, tagged: 100, toTag: 100, titling: 1, isReady: true) == 1)
    }
}

/// Small deterministic random numbers for test data.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
