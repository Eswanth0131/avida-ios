import SwiftUI
import Photos

/// Loads small thumbnails from the device only. Never downloads from iCloud, never loads full size.
@Observable
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    /// Photos whose thumbnail wasn't available on the device (e.g. iCloud-only originals).
    private(set) var missingIDs: Set<String> = []

    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()

    nonisolated private static let manager = PHCachingImageManager()

    func image(for id: String, pixelSide: CGFloat) async -> UIImage? {
        let key = "\(id)|\(Int(pixelSide))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        if let image = await Self.load(id: id, pixelSide: pixelSide) {
            cache.setObject(image, forKey: key)
            return image
        }
        missingIDs.insert(id)
        return nil
    }

    /// Ask PhotoKit to prepare thumbnails ahead of scrolling, e.g. for a grid that just opened.
    func startCaching(_ ids: [String], pixelSide: CGFloat) {
        Self.caching(ids, pixelSide: pixelSide, start: true)
    }

    func stopCaching(_ ids: [String], pixelSide: CGFloat) {
        Self.caching(ids, pixelSide: pixelSide, start: false)
    }

    nonisolated private static func options() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat  // one callback, at roughly the target size
        options.resizeMode = .fast
        return options
    }

    @concurrent
    nonisolated private static func load(id: String, pixelSide: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let size = CGSize(width: pixelSide, height: pixelSide)
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options()) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    nonisolated private static func caching(_ ids: [String], pixelSide: CGFloat, start: Bool) {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        let assets = (0..<fetched.count).map { fetched.object(at: $0) }
        let size = CGSize(width: pixelSide, height: pixelSide)
        if start {
            manager.startCachingImages(for: assets, targetSize: size, contentMode: .aspectFill, options: options())
        } else {
            manager.stopCachingImages(for: assets, targetSize: size, contentMode: .aspectFill, options: options())
        }
    }
}

/// A square thumbnail that loads when it appears. Grey until loaded, and stays grey if missing.
/// The caller sets the frame.
struct Thumbnail: View {
    let id: String
    /// Size in points to request; the loader multiplies by screen scale.
    let pointSide: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color(.systemGray5)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: id) {
                image = await ThumbnailLoader.shared.image(for: id, pixelSide: pointSide * displayScale)
            }
    }
}

/// Horizontal row of small thumbnails.
struct ThumbnailStrip: View {
    let ids: [String]
    var side: CGFloat = 64

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(ids, id: \.self) { id in
                    Thumbnail(id: id, pointSide: side)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(height: side)
    }
}

/// Grid of every photo in a moment.
struct MomentPhotosView: View {
    let moment: Moment
    let title: String

    private static let cellSide: CGFloat = 110
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cellSide - 10), spacing: 2)], spacing: 2) {
                ForEach(moment.photoIDs, id: \.self) { id in
                    Thumbnail(id: id, pointSide: Self.cellSide)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ThumbnailLoader.shared.startCaching(moment.photoIDs, pixelSide: Self.cellSide * displayScale) }
        .onDisappear { ThumbnailLoader.shared.stopCaching(moment.photoIDs, pixelSide: Self.cellSide * displayScale) }
    }
}
