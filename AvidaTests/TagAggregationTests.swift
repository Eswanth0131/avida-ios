import Foundation
import Testing
@testable import Avida

/// Made-up Vision output: ["beach": 0.9, ...] per photo.
private func photo(_ id: String, _ labels: [String: Float]) -> PhotoTags {
    PhotoTags(photoID: id, labels: labels.map { PhotoLabel(identifier: $0.key, confidence: $0.value) })
}

struct TagAggregationTests {
    @Test func noPhotosGivesNoTags() {
        #expect(TagAggregation.moment([]) == .empty)
        #expect(TagAggregation.trip([]) == .empty)
    }

    @Test func labelsUnderThresholdAreDropped() {
        let summary = TagAggregation.moment([photo("a", ["beach": 0.9, "dog": 0.29, "sky": 0.3])])
        #expect(summary.tags.map(\.name) == ["beach", "sky"])  // 0.3 is kept, 0.29 is not
    }

    @Test func confidencesAreSummedAcrossPhotosAndTopThreeKept() {
        let summary = TagAggregation.moment([
            photo("a", ["beach": 0.5, "sky": 0.9, "tree": 0.4]),
            photo("b", ["beach": 0.6, "sky": 0.4, "food": 0.35]),
            photo("c", ["beach": 0.7, "dog": 0.8]),
        ])
        // beach 1.8, sky 1.3, dog 0.8, tree 0.4, food 0.35
        #expect(summary.tags.map(\.name) == ["beach", "sky", "dog"])
        #expect(abs(summary.tags[0].score - 1.8) < 0.0001)
    }

    @Test func tiesAreBrokenAlphabetically() {
        let summary = TagAggregation.moment([photo("a", ["zoo": 0.5, "art": 0.5, "map": 0.5, "cat": 0.5])])
        #expect(summary.tags.map(\.name) == ["art", "cat", "map"])
    }

    @Test func tripCombinesMomentTagsAndKeepsTopFive() {
        let moments = [
            TagSummary(tags: [ScoredTag(name: "beach", score: 2), ScoredTag(name: "sky", score: 1)]),
            TagSummary(tags: [ScoredTag(name: "food", score: 1.5), ScoredTag(name: "beach", score: 0.5)]),
            TagSummary(tags: [ScoredTag(name: "boat", score: 0.9), ScoredTag(name: "dog", score: 0.8),
                              ScoredTag(name: "sand", score: 0.7)]),
        ]
        let summary = TagAggregation.trip(moments)
        // beach 2.5, food 1.5, sky 1, boat 0.9, dog 0.8, sand 0.7
        #expect(summary.tags.map(\.name) == ["beach", "food", "sky", "boat", "dog"])
    }

    @Test func thresholdsComeFromConfig() {
        var config = ClusterConfig()
        config.tagMinConfidence = 0.8
        config.tagsPerMoment = 1
        let summary = TagAggregation.moment([photo("a", ["beach": 0.9, "sky": 0.85, "dog": 0.5])], config: config)
        #expect(summary.tags.map(\.name) == ["beach"])
    }
}
