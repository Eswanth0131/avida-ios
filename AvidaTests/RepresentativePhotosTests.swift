import Foundation
import Testing
@testable import Avida

private let base = Date(timeIntervalSince1970: 1_780_000_000)

/// One photo per entry, `minutes` after `base`, ids "p0", "p1", ...
private func photos(atMinutes minutes: [Double]) -> [PhotoPoint] {
    minutes.enumerated().map { index, minute in
        PhotoPoint(id: "p\(index)", date: base.addingTimeInterval(minute * 60), latitude: nil, longitude: nil)
    }
}

struct RepresentativePhotosTests {
    @Test func fewerPhotosThanMaxReturnsAllInOrder() {
        let picked = RepresentativePhotos.pick(photos(atMinutes: [20, 0, 10]), maxCount: 5)
        #expect(picked.map(\.id) == ["p1", "p2", "p0"])
    }

    @Test func emptyInputGivesNothing() {
        #expect(RepresentativePhotos.pick([], maxCount: 5).isEmpty)
    }

    @Test func evenlySpacedPhotosPickFirstLastAndQuarters() {
        // 0, 10, ..., 80 minutes: targets are 0, 20, 40, 60, 80.
        let picked = RepresentativePhotos.pick(photos(atMinutes: stride(from: 0, through: 80, by: 10).map { $0 }), maxCount: 5)
        #expect(picked.map(\.id) == ["p0", "p2", "p4", "p6", "p8"])
    }

    @Test func spreadIsByTimeNotByCount() {
        // A burst of 8 photos at the start, then two later ones. Index-based picking would
        // take mostly burst photos; time-based picking reaches the later photos too.
        let picked = RepresentativePhotos.pick(photos(atMinutes: [0, 1, 2, 3, 4, 5, 6, 7, 50, 100]), maxCount: 5)
        #expect(picked.first?.id == "p0")
        #expect(picked.last?.id == "p9")
        #expect(picked.map(\.id).contains("p8"))
        #expect(picked.count == 5)
    }

    @Test func samePhotoIsNeverPickedTwice() {
        // Targets 25 and 50 are both nearest to the photo at 40; the second one must take another photo.
        let picked = RepresentativePhotos.pick(photos(atMinutes: [0, 1, 2, 40, 99, 100]), maxCount: 5)
        #expect(Set(picked.map(\.id)).count == 5)
        #expect(picked.map(\.id).contains("p3"))
    }

    @Test func identicalTimestampsStillGiveMaxCountDistinctPhotos() {
        let picked = RepresentativePhotos.pick(photos(atMinutes: Array(repeating: 0, count: 8)), maxCount: 5)
        #expect(picked.map(\.id) == ["p0", "p1", "p2", "p3", "p7"])
    }
}
