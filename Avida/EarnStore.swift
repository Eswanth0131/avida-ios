import SwiftUI

/// Persists Earn state (including the List tab) to Documents/earn.json and check-in photos to Documents/CheckIns.
/// Nothing leaves the device and nothing goes into the photo library.
@Observable
final class EarnStore {
    private(set) var state: EarnState
    let offers: [Offer]

    @ObservationIgnored private let directory: URL

    nonisolated static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(directory: URL = URL.documentsDirectory, offers: [Offer] = OfferCatalog.bundled) {
        self.directory = directory
        self.offers = offers
        let data = try? Data(contentsOf: directory.appending(path: "earn.json"))
        state = data.flatMap { try? Self.decoder.decode(EarnState.self, from: $0) } ?? EarnState()
    }

    private var stateURL: URL { directory.appending(path: "earn.json") }
    private var photosURL: URL { directory.appending(path: "CheckIns", directoryHint: .isDirectory) }

    var balances: [Balance] { EarnLogic.balances(state.ledger) }
    var verified: [VerifiedExperience] { state.verified.sorted { $0.date > $1.date } }

    func status(_ offer: Offer) -> OfferStatus { EarnLogic.status(of: offer, in: state) }
    func location(_ offer: Offer) -> Coordinate? { EarnLogic.location(of: offer, in: state) }
    func offer(id: String) -> Offer? { offers.first { $0.id == id } }

    // MARK: List (shared with Connect)

    /// Newest first.
    var list: [ListItem] { EarnLogic.listItems(state) }

    func isInList(_ itemID: String) -> Bool { EarnLogic.contains(itemID, in: state) }

    /// Any source can add here; Connect will call this with `.connect(...)` items.
    func addToList(_ item: ListItem) {
        update(EarnLogic.add(item, to: state))
    }

    func removeFromList(_ itemID: String) {
        update(EarnLogic.remove(itemID, from: state))
    }

    func toggleList(_ item: ListItem) {
        update(EarnLogic.toggle(item, in: state))
    }

    func toggleList(_ offer: Offer) {
        update(EarnLogic.toggleList(offer, in: state, at: .now))
    }

    func placeDemoOffer(at coordinate: Coordinate) {
        var next = state
        next.demoLocation = coordinate
        update(next)
    }

    /// Saves the photo, then credits the reward. Returns nil if the offer was already verified.
    func completeCheckIn(_ offer: Offer, photo: UIImage, at location: Coordinate, distanceMeters: Double) throws -> VerifiedExperience? {
        guard status(offer) != .verified else { return nil }
        let id = UUID()
        let fileName = "\(id.uuidString).jpg"
        try FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        guard let data = photo.downscaled(maxSide: 1600).jpegData(compressionQuality: 0.8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: photosURL.appending(path: fileName), options: [.atomic, .completeFileProtection])
        guard let result = EarnLogic.verify(offer, in: state, at: location, distanceMeters: distanceMeters,
                                            photoFileName: fileName, date: .now, id: id) else { return nil }
        update(result.state)
        return result.verified
    }

    func photo(for verified: VerifiedExperience) -> UIImage? {
        UIImage(contentsOfFile: photosURL.appending(path: verified.photoFileName).path(percentEncoded: false))
    }

    /// Developer screen: clears the List, the ledger, verified experiences, the demo location and photos.
    func reset() {
        try? FileManager.default.removeItem(at: photosURL)
        try? FileManager.default.removeItem(at: stateURL)
        state = EarnState()
    }

    private func update(_ next: EarnState) {
        state = next
        if let data = try? Self.encoder.encode(next) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}

private extension UIImage {
    func downscaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
