import Foundation

nonisolated enum RepresentativePhotos {
    /// Picks up to `maxCount` photos spread evenly through the photos' time range:
    /// always the first and last, then the photo nearest each evenly spaced time between.
    /// Returned in chronological order. Step 3b tags exactly these photos.
    static func pick(_ photos: [PhotoPoint], maxCount: Int = ClusterConfig.standard.representativesPerMoment) -> [PhotoPoint] {
        let sorted = photos.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        guard maxCount > 0 else { return [] }
        guard sorted.count > maxCount else { return sorted }
        guard maxCount > 1 else { return [sorted[0]] }

        let start = sorted.first!.date
        let span = sorted.last!.date.timeIntervalSince(start)
        let targets = (0..<maxCount).map { start.addingTimeInterval(span * Double($0) / Double(maxCount - 1)) }

        // First and last targets go first so they always get the end photos.
        // On equal times, the last target prefers the later photo; the others prefer the earlier one.
        let order = [0, maxCount - 1] + Array(1..<(maxCount - 1))
        var chosen = Set<Int>()
        for targetIndex in order {
            let target = targets[targetIndex]
            let preferLater = targetIndex == maxCount - 1
            var best: Int?
            for index in sorted.indices where !chosen.contains(index) {
                guard let current = best else { best = index; continue }
                let gap = abs(sorted[index].date.timeIntervalSince(target))
                let bestGap = abs(sorted[current].date.timeIntervalSince(target))
                if gap < bestGap || (preferLater && gap == bestGap) { best = index }
            }
            if let best { chosen.insert(best) }
        }
        return chosen.sorted().map { sorted[$0] }
    }
}
