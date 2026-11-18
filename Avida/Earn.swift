import Foundation

nonisolated struct Coordinate: Codable, Sendable, Hashable {
    let latitude: Double
    let longitude: Double
}

/// A partner-sponsored experience from the bundled offers.json.
nonisolated struct Offer: Codable, Sendable, Hashable, Identifiable {
    struct Stop: Codable, Sendable, Hashable {
        let name: String
        let duration: String?
    }

    let id: String
    let title: String
    /// Text only, no logos. Always shown with an "Illustrative partner" label.
    let partner: String
    let rewardAmount: Int
    let rewardUnit: String
    let category: ExperienceCategory
    let description: String
    let place: String
    let duration: String
    let stops: [Stop]
    let latitude: Double
    let longitude: Double
    let checkInRadiusMeters: Double?
    /// The demo offer's real location is set from the Developer screen and stored in EarnState.
    let isDemo: Bool?
    /// Asset catalog names (Assets.xcassets/Earn), first is the cover. Nil or empty: category gradient.
    let images: [String]?

    var radiusMeters: Double { checkInRadiusMeters ?? ClusterConfig.standard.checkInDefaultRadiusMeters }
    var rewardText: String { "+\(rewardAmount.formatted()) \(rewardUnit)" }
}

nonisolated enum OfferCatalog {
    static let bundled: [Offer] = {
        guard let url = Bundle.main.url(forResource: "offers", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Offer].self, from: data)) ?? []
    }()
}

nonisolated struct LedgerEntry: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let offerID: String
    let partner: String
    let unit: String
    let amount: Int
    let date: Date
}

/// A check-in that passed the distance check and has a photo.
nonisolated struct VerifiedExperience: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let offerID: String
    let title: String
    let partner: String
    let rewardAmount: Int
    let rewardUnit: String
    let category: ExperienceCategory
    let place: String
    let date: Date
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    /// File name inside Documents/CheckIns. Never in the photo library.
    let photoFileName: String

    var rewardText: String { "+\(rewardAmount.formatted()) \(rewardUnit)" }
}

/// One saved thing on the List tab. Each item keeps its own copy of what the List shows, so items from
/// any source (Earn offers now, Connect next) render the same way and survive catalog changes.
nonisolated struct ListItem: Codable, Sendable, Hashable, Identifiable {
    enum Source: Codable, Sendable, Hashable {
        /// An Earn offer, by Offer.id.
        case offer(String)
        /// Something saved from Connect (a friend's experience or post), by its Connect id.
        case connect(String)
    }

    /// Stable and unique per source, e.g. "offer:jal-snow-monkeys", so adding twice is a no-op.
    let id: String
    let source: Source
    let title: String
    /// Who offers or shared it, shown under the title. Nil when there's no partner.
    let partner: String?
    /// e.g. "+750 JAL Miles". Nil when there's no reward.
    let reward: String?
    let place: String?
    let category: ExperienceCategory
    /// Asset catalog name for the row photo. Nil: category gradient.
    let imageName: String?
    let addedAt: Date

    static func id(for source: Source) -> String {
        switch source {
        case .offer(let id): "offer:\(id)"
        case .connect(let id): "connect:\(id)"
        }
    }

    static func offer(_ offer: Offer, addedAt: Date) -> ListItem {
        ListItem(id: id(for: .offer(offer.id)), source: .offer(offer.id), title: offer.title, partner: offer.partner,
                 reward: offer.rewardText, place: offer.place, category: offer.category,
                 imageName: offer.images?.first, addedAt: addedAt)
    }
}

/// Everything Earn persists, saved as one JSON file in Documents: the List, plus the (currently hidden)
/// check-in ledger and verified experiences.
nonisolated struct EarnState: Codable, Sendable, Equatable {
    var list: [ListItem] = []
    var ledger: [LedgerEntry] = []
    var verified: [VerifiedExperience] = []
    var demoLocation: Coordinate?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case list, ledger, verified, demoLocation
    }

    /// Every field is optional on disk, so files written by older builds (which had savedOfferIDs and no list)
    /// still load instead of resetting the ledger.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        list = try container.decodeIfPresent([ListItem].self, forKey: .list) ?? []
        ledger = try container.decodeIfPresent([LedgerEntry].self, forKey: .ledger) ?? []
        verified = try container.decodeIfPresent([VerifiedExperience].self, forKey: .verified) ?? []
        demoLocation = try container.decodeIfPresent(Coordinate.self, forKey: .demoLocation)
    }
}

nonisolated struct Balance: Sendable, Hashable {
    let partner: String
    let unit: String
    let amount: Int
}

nonisolated enum OfferStatus: Sendable, Equatable {
    case available
    /// On the List.
    case added
    /// Checked in (flow currently hidden from the UI).
    case verified
}

nonisolated enum CheckInResult: Sendable, Equatable {
    case withinRadius(distanceMeters: Double)
    case tooFar(distanceMeters: Double, radiusMeters: Double)
    /// GPS fix too rough to trust, though it might be in range. Try again outside or wait a moment.
    case inaccurate(accuracyMeters: Double)
}

/// Pure rules for the Earn loop, unit tested. No storage, location or camera here.
nonisolated enum EarnLogic {
    static func status(of offer: Offer, in state: EarnState) -> OfferStatus {
        if state.verified.contains(where: { $0.offerID == offer.id }) { return .verified }
        return contains(ListItem.id(for: .offer(offer.id)), in: state) ? .added : .available
    }

    /// Where to check in. Nil for the demo offer until it's placed.
    static func location(of offer: Offer, in state: EarnState) -> Coordinate? {
        if offer.isDemo == true { return state.demoLocation }
        return Coordinate(latitude: offer.latitude, longitude: offer.longitude)
    }

    // MARK: List

    static func contains(_ itemID: String, in state: EarnState) -> Bool {
        state.list.contains { $0.id == itemID }
    }

    /// Adds an item from any source. Adding an id that's already there changes nothing (keeps its original date).
    static func add(_ item: ListItem, to state: EarnState) -> EarnState {
        guard !contains(item.id, in: state) else { return state }
        var next = state
        next.list.append(item)
        return next
    }

    static func remove(_ itemID: String, from state: EarnState) -> EarnState {
        var next = state
        next.list.removeAll { $0.id == itemID }
        return next
    }

    /// Adds the item, or removes it if it's already there ("Add to List" / "Added ✓" for any source).
    static func toggle(_ item: ListItem, in state: EarnState) -> EarnState {
        contains(item.id, in: state) ? remove(item.id, from: state) : add(item, to: state)
    }

    /// "Add to List" / "Added ✓".
    static func toggleList(_ offer: Offer, in state: EarnState, at date: Date) -> EarnState {
        let item = ListItem.offer(offer, addedAt: date)
        return contains(item.id, in: state) ? remove(item.id, from: state) : add(item, to: state)
    }

    /// Newest first.
    static func listItems(_ state: EarnState) -> [ListItem] {
        state.list.sorted { $0.addedAt > $1.addedAt }
    }

    static func checkIn(
        at user: Coordinate,
        accuracyMeters: Double,
        target: Coordinate,
        radiusMeters: Double,
        config: ClusterConfig = .standard
    ) -> CheckInResult {
        let distance = Clustering.distanceMeters((user.latitude, user.longitude), (target.latitude, target.longitude))
        if distance > radiusMeters { return .tooFar(distanceMeters: distance, radiusMeters: radiusMeters) }
        if accuracyMeters < 0 || accuracyMeters > config.checkInMaxAccuracyMeters {
            return .inaccurate(accuracyMeters: accuracyMeters)
        }
        return .withinRadius(distanceMeters: distance)
    }

    /// Credits the reward once per offer and records the verified experience. Nil if already verified.
    static func verify(
        _ offer: Offer,
        in state: EarnState,
        at location: Coordinate,
        distanceMeters: Double,
        photoFileName: String,
        date: Date,
        id: UUID = UUID()
    ) -> (state: EarnState, verified: VerifiedExperience)? {
        guard status(of: offer, in: state) != .verified else { return nil }
        let verified = VerifiedExperience(
            id: id, offerID: offer.id, title: offer.title, partner: offer.partner,
            rewardAmount: offer.rewardAmount, rewardUnit: offer.rewardUnit, category: offer.category,
            place: offer.place, date: date, latitude: location.latitude, longitude: location.longitude,
            distanceMeters: distanceMeters, photoFileName: photoFileName
        )
        var next = state
        next.ledger.append(LedgerEntry(id: id, offerID: offer.id, partner: offer.partner, unit: offer.rewardUnit,
                                       amount: offer.rewardAmount, date: date))
        next.verified.append(verified)
        next.list.removeAll { $0.id == ListItem.id(for: .offer(offer.id)) }
        return (next, verified)
    }

    /// Sum per partner and unit, largest first.
    static func balances(_ ledger: [LedgerEntry]) -> [Balance] {
        Dictionary(grouping: ledger) { "\($0.partner)\u{1F}\($0.unit)" }
            .values
            .map { entries in Balance(partner: entries[0].partner, unit: entries[0].unit, amount: entries.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.partner < $1.partner }
    }
}
