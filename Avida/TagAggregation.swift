import Foundation

/// One Vision classification label. Made-up values in tests, VNClassificationObservation in the app.
nonisolated struct PhotoLabel: Sendable, Hashable {
    let identifier: String
    let confidence: Float
}

/// What Vision found in one photo.
nonisolated struct PhotoTags: Sendable, Hashable {
    let photoID: String
    let labels: [PhotoLabel]
}

nonisolated struct ScoredTag: Sendable, Hashable {
    let name: String
    /// Sum of confidences that went into this tag.
    let score: Float
}

/// Tags for a moment or a trip.
nonisolated struct TagSummary: Sendable, Hashable {
    let tags: [ScoredTag]

    static let empty = TagSummary(tags: [])
}

/// Pure combining of Vision results. No Vision imports, so it's unit testable with made-up labels.
nonisolated enum TagAggregation {
    /// Drops labels under the confidence threshold, sums confidence per label across photos,
    /// and keeps the top `tagsPerMoment`.
    static func moment(_ photos: [PhotoTags], config: ClusterConfig = .standard) -> TagSummary {
        var totals: [String: Float] = [:]
        for label in photos.flatMap(\.labels) where label.confidence >= config.tagMinConfidence {
            totals[label.identifier, default: 0] += label.confidence
        }
        return TagSummary(tags: top(totals, count: config.tagsPerMoment))
    }

    /// Sums each moment's tag scores across the trip and keeps the top `tagsPerTrip`.
    static func trip(_ moments: [TagSummary], config: ClusterConfig = .standard) -> TagSummary {
        var totals: [String: Float] = [:]
        for tag in moments.flatMap(\.tags) {
            totals[tag.name, default: 0] += tag.score
        }
        return TagSummary(tags: top(totals, count: config.tagsPerTrip))
    }

    /// Highest score first; ties broken alphabetically so results are stable.
    private static func top(_ totals: [String: Float], count: Int) -> [ScoredTag] {
        totals
            .map { ScoredTag(name: $0.key, score: $0.value) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.name < $1.name }
            .prefix(count)
            .map { $0 }
    }
}
