import Foundation

/// A Wikidata landmark from the bundled landmarks.tsv (CC0).
nonisolated struct Landmark: Sendable, Hashable {
    let qid: String
    let name: String
    let description: String
    /// English label of the item's instance-of (P31) type, e.g. "urban park".
    let type: String
    let latitude: Double
    let longitude: Double
    /// Number of Wikipedia/Wikimedia sitelinks: a rough measure of how famous it is.
    let sitelinks: Int
}

/// Pure matching rules, tested with made-up landmarks.
nonisolated enum LandmarkMatching {
    static func radius(for landmark: Landmark, config: ClusterConfig = .standard) -> Double {
        typeWords(landmark).isDisjoint(with: config.landmarkLargeAreaTypeWords)
            ? config.landmarkDefaultRadiusMeters
            : config.landmarkLargeAreaRadiusMeters
    }

    /// Nil when the landmark is outside its match radius.
    static func score(_ landmark: Landmark, distanceMeters: Double, config: ClusterConfig = .standard) -> Double? {
        let radius = radius(for: landmark, config: config)
        guard distanceMeters <= radius else { return nil }
        let falloff = 1 - (1 - config.landmarkScoreAtRadiusEdge) * (distanceMeters / radius)
        let words = typeWords(landmark)
        let weight = config.landmarkTypeWeights.filter { words.contains($0.key) }.values.min() ?? 1
        return Double(landmark.sitelinks) * weight * falloff
    }

    /// Best-scoring landmark for a moment, using each landmark's distance to the moment's nearest GPS photo.
    static func best(
        near points: [(latitude: Double, longitude: Double)],
        among candidates: [Landmark],
        config: ClusterConfig = .standard
    ) -> Landmark? {
        var best: (landmark: Landmark, score: Double)?
        for landmark in candidates {
            guard let distance = points.map({
                Clustering.distanceMeters(($0.latitude, $0.longitude), (landmark.latitude, landmark.longitude))
            }).min(),
                let score = score(landmark, distanceMeters: distance, config: config) else { continue }
            if let current = best {
                let better = score != current.score
                    ? score > current.score
                    : (landmark.sitelinks, current.landmark.name) > (current.landmark.sitelinks, landmark.name)
                if !better { continue }
            }
            best = (landmark, score)
        }
        return best?.landmark
    }

    static func typeWords(_ landmark: Landmark) -> Set<String> {
        Set(landmark.type.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }
}

/// Offline landmark lookup over the bundled Wikidata extract. No network.
nonisolated final class LandmarkLookup: Sendable {
    static let shared: LandmarkLookup? = {
        guard let url = Bundle.main.url(forResource: "landmarks", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return LandmarkLookup(landmarks: parse(text))
    }()

    /// Sorted by latitude for band searches.
    let landmarks: [Landmark]

    init(landmarks: [Landmark]) {
        self.landmarks = landmarks.sorted { $0.latitude < $1.latitude }
    }

    /// Lines of: QID, label, description, type, latitude, longitude, sitelinks (tab-separated).
    static func parse(_ text: String) -> [Landmark] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 7,
                  let latitude = Double(fields[4]),
                  let longitude = Double(fields[5]),
                  let sitelinks = Int(fields[6]) else { return nil }
            return Landmark(
                qid: String(fields[0]),
                name: String(fields[1]),
                description: String(fields[2]),
                type: String(fields[3]),
                latitude: latitude,
                longitude: longitude,
                sitelinks: sitelinks
            )
        }
    }

    /// Landmarks within `meters` of a coordinate.
    func candidates(nearLatitude latitude: Double, longitude: Double, within meters: Double) -> [Landmark] {
        let latitudeSpan = meters / 111_000
        var index = firstIndex(atOrAbove: latitude - latitudeSpan)
        var found: [Landmark] = []
        while index < landmarks.count, landmarks[index].latitude <= latitude + latitudeSpan {
            let landmark = landmarks[index]
            if Clustering.distanceMeters((latitude, longitude), (landmark.latitude, landmark.longitude)) <= meters {
                found.append(landmark)
            }
            index += 1
        }
        return found
    }

    /// Best landmark for a moment's GPS photos, or nil to fall back to the city.
    func match(_ points: [(latitude: Double, longitude: Double)], config: ClusterConfig = .standard) -> Landmark? {
        let searchRadius = max(config.landmarkDefaultRadiusMeters, config.landmarkLargeAreaRadiusMeters)
        var candidates = Set<Landmark>()
        for point in points {
            candidates.formUnion(self.candidates(nearLatitude: point.latitude, longitude: point.longitude, within: searchRadius))
        }
        return LandmarkMatching.best(near: points, among: Array(candidates), config: config)
    }

    private func firstIndex(atOrAbove latitude: Double) -> Int {
        var low = 0, high = landmarks.count
        while low < high {
            let mid = (low + high) / 2
            if landmarks[mid].latitude < latitude { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
