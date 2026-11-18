import Foundation
import Testing
import UIKit
@testable import Avida

private func offer(_ id: String = "park", radius: Double? = 150, isDemo: Bool? = nil, unit: String = "Park Points",
                   partner: String = "Gotham Parks Club", amount: Int = 500) -> Offer {
    Offer(id: id, title: "A Morning in Central Park", partner: partner, rewardAmount: amount, rewardUnit: unit,
          category: .nature, description: "", place: "Central Park, New York", duration: "~2 hrs",
          stops: [.init(name: "Bethesda Terrace", duration: nil)], latitude: 40.7740, longitude: -73.9708,
          checkInRadiusMeters: radius, isDemo: isDemo, images: ["earn-kyoto-1"])
}

private let bethesda = Coordinate(latitude: 40.7740, longitude: -73.9708)

/// Roughly `meters` north of a point (1° latitude ≈ 111 km).
private func north(of point: Coordinate, _ meters: Double) -> Coordinate {
    Coordinate(latitude: point.latitude + meters / 111_000, longitude: point.longitude)
}

struct CheckInDistanceTests {
    @Test func withinRadiusVerifies() {
        let result = EarnLogic.checkIn(at: north(of: bethesda, 100), accuracyMeters: 10, target: bethesda, radiusMeters: 150)
        guard case .withinRadius(let distance) = result else { Issue.record("expected within, got \(result)"); return }
        #expect(abs(distance - 100) < 2)
    }

    @Test func outsideRadiusIsTooFarWithDistance() {
        let result = EarnLogic.checkIn(at: north(of: bethesda, 2_000), accuracyMeters: 10, target: bethesda, radiusMeters: 150)
        guard case .tooFar(let distance, let radius) = result else { Issue.record("expected tooFar, got \(result)"); return }
        #expect(abs(distance - 2_000) < 20)
        #expect(radius == 150)
    }

    @Test func roughFixCannotVerify() {
        let result = EarnLogic.checkIn(at: bethesda, accuracyMeters: 500, target: bethesda, radiusMeters: 150)
        #expect(result == .inaccurate(accuracyMeters: 500))
        // Negative accuracy means Core Location has no valid fix.
        #expect(EarnLogic.checkIn(at: bethesda, accuracyMeters: -1, target: bethesda, radiusMeters: 150) == .inaccurate(accuracyMeters: -1))
    }

    @Test func clearlyFarIsTooFarEvenWithRoughFix() {
        let result = EarnLogic.checkIn(at: north(of: bethesda, 5_000), accuracyMeters: 500, target: bethesda, radiusMeters: 150)
        guard case .tooFar = result else { Issue.record("expected tooFar, got \(result)"); return }
    }

    @Test func missingRadiusUsesDefault() {
        #expect(offer(radius: nil).radiusMeters == 150)
        #expect(offer(radius: 400).radiusMeters == 400)
    }
}

struct EarnLedgerTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func addToListTogglesAndSetsStatus() {
        let park = offer()
        var state = EarnState()
        #expect(EarnLogic.status(of: park, in: state) == .available)
        state = EarnLogic.toggleList(park, in: state, at: date)
        #expect(EarnLogic.status(of: park, in: state) == .added)
        state = EarnLogic.toggleList(park, in: state, at: date)
        #expect(EarnLogic.status(of: park, in: state) == .available)
        #expect(state.list.isEmpty)
    }

    @Test func verifyCreditsLedgerAndRecordsExperience() throws {
        let park = offer()
        let saved = EarnLogic.toggleList(park, in: EarnState(), at: date)
        let result = try #require(EarnLogic.verify(park, in: saved, at: bethesda, distanceMeters: 40,
                                                   photoFileName: "a.jpg", date: date))
        #expect(result.state.ledger.map(\.amount) == [500])
        #expect(result.state.verified.count == 1)
        #expect(result.verified.photoFileName == "a.jpg")
        #expect(result.verified.date == date)
        #expect(result.verified.place == "Central Park, New York")
        #expect(EarnLogic.status(of: park, in: result.state) == .verified)
        #expect(result.state.list.isEmpty)
    }

    @Test func sameOfferCannotBeCreditedTwice() throws {
        let park = offer()
        let first = try #require(EarnLogic.verify(park, in: EarnState(), at: bethesda, distanceMeters: 10,
                                                  photoFileName: "a.jpg", date: date))
        #expect(EarnLogic.verify(park, in: first.state, at: bethesda, distanceMeters: 10,
                                 photoFileName: "b.jpg", date: date) == nil)
    }

    @Test func balancesSumPerPartnerAndUnit() throws {
        var state = EarnState()
        let offers = [
            offer("p1", amount: 500),
            offer("p2", amount: 250),
            offer("k1", unit: "Rail Points", partner: "Kansai Rail Club", amount: 1_000),
        ]
        for item in offers {
            state = try #require(EarnLogic.verify(item, in: state, at: bethesda, distanceMeters: 1,
                                                  photoFileName: "\(item.id).jpg", date: date)).state
        }
        let balances = EarnLogic.balances(state.ledger)
        #expect(balances == [
            Balance(partner: "Kansai Rail Club", unit: "Rail Points", amount: 1_000),
            Balance(partner: "Gotham Parks Club", unit: "Park Points", amount: 750),
        ])
        #expect(EarnLogic.balances([]).isEmpty)
    }

    @Test func demoOfferHasNoLocationUntilPlaced() {
        let demo = offer("demo-offer", isDemo: true)
        var state = EarnState()
        #expect(EarnLogic.location(of: demo, in: state) == nil)
        state.demoLocation = Coordinate(latitude: 1, longitude: 2)
        #expect(EarnLogic.location(of: demo, in: state) == Coordinate(latitude: 1, longitude: 2))
        #expect(EarnLogic.location(of: offer(), in: state) == bethesda)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        let state = try #require(EarnLogic.verify(offer(), in: EarnState(), at: bethesda, distanceMeters: 5,
                                                  photoFileName: "a.jpg", date: date)).state
        let data = try EarnStore.encoder.encode(state)
        #expect(try EarnStore.decoder.decode(EarnState.self, from: data) == state)
    }

    @Test func bundledOffersLoad() throws {
        let offers = OfferCatalog.bundled
        #expect(offers.map(\.partner) == ["JR East", "Hoshinoya", "City of Miyazaki", "JAL", "City of Hiroshima", "ANA"])
        #expect(Set(offers.map(\.id)).count == 6)
        #expect(offers.allSatisfy { $0.isDemo != true && $0.stops.count == 3 && $0.radiusMeters == 150 && $0.rewardAmount > 0 })
        // Every image name must exist in the asset catalog; offers without images use the gradient.
        for name in offers.flatMap({ $0.images ?? [] }) {
            #expect(UIImage(named: name) != nil, "missing asset \(name)")
        }
        #expect(offers.filter { ($0.images ?? []).isEmpty }.map(\.partner) == ["City of Hiroshima", "ANA"])
    }
}

struct ListTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func connectItem(_ id: String, addedAt: Date) -> ListItem {
        ListItem(id: ListItem.id(for: .connect(id)), source: .connect(id), title: "Lina's Amalfi Coast", partner: nil,
                 reward: nil, place: "Amalfi", category: .coast, imageName: nil, addedAt: addedAt)
    }

    @Test func offerItemCopiesWhatTheListShows() {
        let item = ListItem.offer(offer("jal"), addedAt: date)
        #expect(item.id == "offer:jal")
        #expect(item.source == .offer("jal"))
        #expect(item.title == "A Morning in Central Park")
        #expect(item.partner == "Gotham Parks Club")
        #expect(item.reward == "+500 Park Points")
        #expect(item.imageName == "earn-kyoto-1")
    }

    @Test func addingTwiceKeepsOneItemAndTheFirstDate() {
        let first = ListItem.offer(offer("jal"), addedAt: date)
        let again = ListItem.offer(offer("jal"), addedAt: date.addingTimeInterval(60))
        let state = EarnLogic.add(again, to: EarnLogic.add(first, to: EarnState()))
        #expect(state.list == [first])
    }

    @Test func otherSourcesShareTheListAndDontCollide() {
        var state = EarnLogic.add(ListItem.offer(offer("x"), addedAt: date), to: EarnState())
        state = EarnLogic.add(connectItem("x", addedAt: date.addingTimeInterval(10)), to: state)
        #expect(state.list.count == 2)  // "offer:x" and "connect:x" are different items
        #expect(EarnLogic.listItems(state).map(\.id) == ["connect:x", "offer:x"])  // newest first

        state = EarnLogic.remove("connect:x", from: state)
        #expect(state.list.map(\.id) == ["offer:x"])
        #expect(EarnLogic.status(of: offer("x"), in: state) == .added)
    }

    @Test func listRoundTripsThroughJSON() throws {
        var state = EarnLogic.toggleList(offer("jal"), in: EarnState(), at: date)
        state = EarnLogic.add(connectItem("post-1", addedAt: date), to: state)
        let data = try EarnStore.encoder.encode(state)
        #expect(try EarnStore.decoder.decode(EarnState.self, from: data) == state)
    }

    @Test func olderFilesWithoutAListStillLoad() throws {
        // earn.json as written before Step 7a: savedOfferIDs, no list.
        let old = #"{"savedOfferIDs":["central-park-morning"],"ledger":[],"verified":[]}"#
        let state = try EarnStore.decoder.decode(EarnState.self, from: Data(old.utf8))
        #expect(state.list.isEmpty)
        #expect(state.ledger.isEmpty)
    }
}
