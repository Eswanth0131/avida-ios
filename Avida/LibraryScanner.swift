import Foundation
import Photos

nonisolated struct LibrarySummary: Sendable {
    /// "Your photo library", or "Your selected photos" with Limited access.
    let source: String
    /// Limited Photos access: only the photos the user selected were scanned.
    let isLimited: Bool
    /// Camera photos considered (screenshots excluded).
    let photoCount: Int
    let skippedScreenshots: Int
    let earliestDate: Date?
    let latestDate: Date?
    let withGPS: Int
    let withoutGPS: Int
    /// Photos with no creation date can't be placed in time, so they skip clustering.
    let withoutDate: Int
    /// Stage timings: reading PhotoKit metadata, and clustering including city and landmark lookup.
    let metadataTime: Duration
    let clusteringTime: Duration
    /// Home used for this scan, and where it came from.
    let home: Coordinate?
    let homeSource: HomeSource
}

nonisolated enum HomeSource: Sendable, Equatable {
    case detected
    case setByUser
    /// No GPS photos and no override: home doesn't affect anything.
    case none
}

nonisolated enum LibraryScanResult: Sendable {
    case scanned(LibrarySummary, ClusterResult)
}

nonisolated enum LibraryScanner {
    /// Reads metadata for every camera photo in the library (with Limited access: the selected photos), then
    /// clusters it. Skips videos (so screen recordings), screenshots, shared/synced items and photos without a
    /// creation date. Home is the user's override if set, else detected from these photos.
    /// Runs off the main thread; `progress` reports 0…1 (reading is most of it, clustering the rest).
    @concurrent
    static func scan(homeOverride: HomeOverride?, isLimited: Bool, progress: @escaping @Sendable (Double) -> Void) async -> LibraryScanResult {
        let clock = ContinuousClock()
        let metadataStart = clock.now

        let assetOptions = PHFetchOptions()
        assetOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        assetOptions.includeAssetSourceTypes = [.typeUserLibrary]
        let assets = PHAsset.fetchAssets(with: assetOptions)
        let total = assets.count
        let step = max(250, total / 100)
        progress(0)

        var earliest: Date?
        var latest: Date?
        var withGPS = 0
        var withoutDate = 0
        var screenshots = 0
        var points: [PhotoPoint] = []
        points.reserveCapacity(total)
        assets.enumerateObjects { asset, index, _ in
            if index % step == 0 { progress(0.85 * Double(index) / Double(max(total, 1))) }
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                screenshots += 1
                return
            }
            let coordinate = asset.location?.coordinate
            if coordinate != nil { withGPS += 1 }
            guard let date = asset.creationDate else {
                withoutDate += 1
                return
            }
            if earliest == nil || date < earliest! { earliest = date }
            if latest == nil || date > latest! { latest = date }
            points.append(PhotoPoint(
                id: asset.localIdentifier,
                date: date,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude
            ))
        }

        let metadataTime = clock.now - metadataStart
        progress(0.85)

        let clusteringStart = clock.now
        var nearestCity: Clustering.CityLookup?
        if let lookup = PlaceLookup.shared {
            nearestCity = { lookup.nearest(latitude: $0, longitude: $1) }
        }
        var bestLandmark: Clustering.LandmarkLookupFunction?
        if let landmarks = LandmarkLookup.shared {
            bestLandmark = { landmarks.match($0) }
        }
        var config = ClusterConfig.standard
        let home: Coordinate?
        let homeSource: HomeSource
        if let homeOverride {
            home = Coordinate(latitude: homeOverride.latitude, longitude: homeOverride.longitude)
            homeSource = .setByUser
        } else if let detected = HomeDetection.detect(points) {
            home = detected
            homeSource = .detected
        } else {
            home = nil
            homeSource = .none
        }
        if let home {
            config.homeLatitude = home.latitude
            config.homeLongitude = home.longitude
        }
        let clusters = Clustering.cluster(points, config: config, nearestCity: nearestCity, bestLandmark: bestLandmark)
        let clusteringTime = clock.now - clusteringStart

        progress(1)
        let photoCount = total - screenshots
        let summary = LibrarySummary(
            source: isLimited ? "Your selected photos" : "Your photo library",
            isLimited: isLimited,
            photoCount: photoCount,
            skippedScreenshots: screenshots,
            earliestDate: earliest,
            latestDate: latest,
            withGPS: withGPS,
            withoutGPS: photoCount - withGPS,
            withoutDate: withoutDate,
            metadataTime: metadataTime,
            clusteringTime: clusteringTime,
            home: home,
            homeSource: homeSource
        )
        return .scanned(summary, clusters)
    }
}
