import SwiftUI
import Photos
import Vision

/// Runs Apple Vision on one photo, fully on device.
nonisolated enum PhotoTagger {
    enum Result: Sendable {
        case tagged(PhotoTags)
        /// Image not available on the device (e.g. only in iCloud). Skipped, nothing downloaded.
        case notOnDevice
        case visionFailed
    }

    struct Outcome: Sendable {
        let result: Result
        let imageTime: Duration
        let visionTime: Duration
    }

    private static let manager = PHImageManager.default()

    @concurrent
    static func tag(id: String, config: ClusterConfig = .standard) async -> Outcome {
        let clock = ContinuousClock()

        let imageStart = clock.now
        let image = await loadImage(id: id, pixelSide: config.tagImagePixelSide)
        let imageTime = clock.now - imageStart
        guard let image, let cgImage = image.cgImage else {
            return Outcome(result: .notOnDevice, imageTime: imageTime, visionTime: .zero)
        }

        let visionStart = clock.now
        let classify = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        do {
            try handler.perform([classify])
        } catch {
            return Outcome(result: .visionFailed, imageTime: imageTime, visionTime: clock.now - visionStart)
        }
        let labels = (classify.results ?? [])
            .filter { $0.confidence >= config.tagMinConfidence }
            .map { PhotoLabel(identifier: $0.identifier, confidence: $0.confidence) }
        let tags = PhotoTags(photoID: id, labels: labels)
        return Outcome(result: .tagged(tags), imageTime: imageTime, visionTime: clock.now - visionStart)
    }

    private static func loadImage(id: String, pixelSide: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat  // one callback
        options.resizeMode = .fast
        let size = CGSize(width: pixelSide, height: pixelSide)
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Tags every representative photo in the background, a few at a time, and keeps progress for the UI.
@Observable
final class TaggingModel {
    private(set) var results: [String: PhotoTags] = [:]
    private(set) var total = 0
    private(set) var done = 0
    private(set) var notOnDevice = 0
    private(set) var failed = 0
    /// Summed across all photos (workers run in parallel, so these can exceed wall time).
    private(set) var imageTime: Duration = .zero
    private(set) var visionTime: Duration = .zero
    /// Start to finish for the whole tagging run.
    private(set) var wallTime: Duration?

    var isRunning: Bool { done < total }

    @ObservationIgnored private var task: Task<Void, Never>?

    func start(_ ids: [String], config: ClusterConfig = .standard) {
        task?.cancel()
        results = [:]
        total = ids.count
        done = 0
        notOnDevice = 0
        failed = 0
        imageTime = .zero
        visionTime = .zero
        wallTime = nil

        task = Task {
            let clock = ContinuousClock()
            let start = clock.now
            await withTaskGroup(of: (String, PhotoTagger.Outcome).self) { group in
                var pending = ids.makeIterator()
                func addNext() {
                    guard let id = pending.next() else { return }
                    group.addTask { (id, await PhotoTagger.tag(id: id, config: config)) }
                }
                for _ in 0..<max(1, config.taggingConcurrency) { addNext() }

                for await (id, outcome) in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        return
                    }
                    record(id, outcome)
                    addNext()
                }
            }
            if !Task.isCancelled { wallTime = clock.now - start }
        }
    }

    /// Returns when the current run finishes (or immediately if none is running).
    func waitUntilDone() async {
        await task?.value
    }

    func moment(_ moment: Moment, config: ClusterConfig = .standard) -> TagSummary {
        TagAggregation.moment(moment.representativeIDs.compactMap { results[$0] }, config: config)
    }

    func trip(_ trip: Trip, config: ClusterConfig = .standard) -> TagSummary {
        TagAggregation.trip(trip.moments.map { moment($0, config: config) }, config: config)
    }

    private func record(_ id: String, _ outcome: PhotoTagger.Outcome) {
        switch outcome.result {
        case .tagged(let tags): results[id] = tags
        case .notOnDevice: notOnDevice += 1
        case .visionFailed: failed += 1
        }
        imageTime += outcome.imageTime
        visionTime += outcome.visionTime
        done += 1
    }
}

/// Small capsules for tags.
struct TagChips: View {
    let summary: TagSummary

    var body: some View {
        if !summary.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(summary.tags, id: \.name) { tag in
                        chip(tag.name.replacingOccurrences(of: "_", with: " "))
                    }
                }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }
}
