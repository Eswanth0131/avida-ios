import SwiftUI
import Photos

/// App-wide state: photo access, the library scan, Vision tagging, and the experiences built from them.
@Observable
final class AppModel {
    var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var result: LibraryScanResult?
    private(set) var isScanning = false
    /// True once the first scan and tagging run have finished; later rescans update screens in place.
    private(set) var isReady = false
    let tagging = TaggingModel()
    /// Name and home override (set in Settings).
    let prefs = UserPrefs.shared
    /// Saved offers, ledger and verified check-ins (Documents/earn.json).
    let earn = EarnStore()
    /// Claude titles and memorability, keyed by experience id (Documents/ai-titles.json).
    let aiTitles = AITitleStore()
    /// True while Claude writes titles after a scan ("Writing your titles…").
    private(set) var isWritingTitles = false
    /// Outcome of the most recent titles run (shown on the Developer screen).
    private(set) var lastTitleRun: AITitleRun?

    private(set) var phase: ScanPhase = .idle
    /// 0…1 within the reading stage (fetching metadata, then clustering).
    private(set) var readProgress: Double = 0
    /// 0…1 within the titles stage.
    private(set) var titleProgress: Double = 0
    /// Bumped on every scan, so the experiences cache knows the clusters changed.
    private var scanCount = 0
    @ObservationIgnored private var experienceCache: (key: String, value: [Experience])?

    /// Full or Limited access lets Avida scan; Limited scans only the photos the user selected.
    var hasAccess: Bool { status == .authorized || status == .limited }
    var isLimited: Bool { status == .limited }

    /// The Analyzing ring (see ScanProgress). Reaches 1 only when experiences are ready.
    var progress: Double {
        ScanProgress.overall(phase: phase, reading: readProgress, tagged: tagging.done, toTag: tagging.total,
                             titling: titleProgress, isReady: isReady)
    }

    var summary: LibrarySummary? {
        if case .scanned(let summary, _) = result { return summary }
        return nil
    }

    var clusters: ClusterResult? {
        if case .scanned(_, let clusters) = result { return clusters }
        return nil
    }

    /// Ranked, best first. Rebuilt when the scan, tags or titles change (cached otherwise: whole libraries
    /// make this expensive), so categories fill in as tagging progresses.
    /// Saved Claude titles replace the templates and memorability joins the rank.
    var experiences: [Experience] {
        let key = "\(scanCount)|\(tagging.done)|\(aiTitles.entries.count)"
        if let cached = experienceCache, cached.key == key { return cached.value }
        let value = buildExperiences()
        experienceCache = (key, value)
        return value
    }

    private func buildExperiences() -> [Experience] {
        let base = baseExperiences
        guard !aiTitles.entries.isEmpty else { return base }
        let titled = base.map { experience in
            var copy = experience
            if let ai = aiTitles.entries[experience.id] { copy.title = ai.title }
            return copy
        }
        return Ranking.rank(titled, memorability: aiTitles.entries.mapValues(\.memorability))
    }

    /// Template titles, ranked by worthiness alone.
    private var baseExperiences: [Experience] {
        guard let clusters else { return [] }
        return Experiences.build(trips: clusters.trips, otherMoments: clusters.otherMoments,
                                 tags: { tagging.moment($0) }, home: home)
    }

    /// Rarity of every experience (Profile → Highlights, Ask "rarest").
    var rarityScores: [String: Double] {
        Rarity.scores(experiences, home: home)
    }

    /// Profile → Highlights: the rarest experiences.
    var highlights: [Experience] {
        let all = experiences
        return Rarity.highlights(all, scores: Rarity.scores(all, home: home), count: ClusterConfig.standard.profileHighlightsCount)
    }

    /// Profile → Places: experiences grouped by metro area.
    var placeGroups: [PlaceGroup] {
        MetroGrouping.groups(experiences, bigCities: PlaceLookup.bigCities)
    }

    /// Home city and country from the scan's home (detected from the photos, or set in Settings),
    /// so home never counts as a first or one-time visit.
    var home: HomePlace? {
        guard let city = homeCity else { return nil }
        return HomePlace(city: city.name, countryCode: city.countryCode)
    }

    var homeCity: City? {
        guard let home = summary?.home else { return nil }
        return PlaceLookup.shared?.nearest(latitude: home.latitude, longitude: home.longitude)
    }

    /// Claude titles for experiences without a saved one (batched). Runs after a scan, when AI suggestions is
    /// switched on, and from Developer → Rewrite titles. Only while AI suggestions is on; on any failure the
    /// template titles stay and the error is kept in `lastTitleRun`.
    func writeTitles() async {
        guard clusters != nil, !isWritingTitles else { return }
        isWritingTitles = true
        titleProgress = 0
        defer { isWritingTitles = false }
        let result = await AITitleWriter().titles(for: baseExperiences, existing: aiTitles.entries) { [weak self] fraction in
            self?.titleProgress = fraction
        }
        aiTitles.merge(result.titles)
        lastTitleRun = result.run
    }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Scans the whole library (camera photos only), tags the photos of found experiences, then writes titles.
    func scan() async {
        guard hasAccess, !isScanning else { return }
        isScanning = true
        phase = .reading
        readProgress = 0
        result = await LibraryScanner.scan(homeOverride: prefs.homeOverride, isLimited: isLimited) { fraction in
            Task { @MainActor in self.readProgress = fraction }  // the model lives as long as the app
        }
        scanCount += 1
        isScanning = false

        phase = .tagging
        tagging.start(photosToTag(baseExperiences))
        await tagging.waitUntilDone()

        phase = .titling
        await writeTitles()

        phase = .done
        isReady = true
    }

    /// Representative photos of moments that belong to experiences, best experiences first, capped at
    /// ClusterConfig.maxTaggedPhotos so a big library doesn't mean thousands of Vision runs.
    private func photosToTag(_ experiences: [Experience]) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []
        for id in experiences.flatMap({ $0.moments.flatMap(\.representativeIDs) }) where seen.insert(id).inserted {
            ids.append(id)
            if ids.count >= ClusterConfig.standard.maxTaggedPhotos { break }
        }
        return ids
    }
}

/// The scan's stages, for the Analyzing ring.
nonisolated enum ScanPhase: Sendable { case idle, reading, tagging, titling, done }

/// The Analyzing ring's value. Pure.
nonisolated enum ScanProgress {
    /// Reading 30%, tagging 55%, titles 15%. Capped at 99% until experiences are ready, then exactly 100%.
    static func overall(phase: ScanPhase, reading: Double, tagged: Int, toTag: Int, titling: Double, isReady: Bool) -> Double {
        if isReady { return 1 }
        let read = phase == .reading ? reading : (phase == .idle ? 0 : 1)
        let tag: Double = switch phase {
        case .idle, .reading: 0
        case .tagging: toTag > 0 ? Double(tagged) / Double(toTag) : 0
        case .titling, .done: 1
        }
        let title = phase == .titling ? titling : (phase == .done ? 1 : 0)
        return min(0.99, 0.30 * min(max(read, 0), 1) + 0.55 * tag + 0.15 * min(max(title, 0), 1))
    }
}
