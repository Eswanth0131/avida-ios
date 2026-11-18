import Foundation

/// Tunable thresholds for grouping photos into moments and trips.
nonisolated struct ClusterConfig: Sendable {
    /// Home location. Trips are measured from here. In the app this is replaced on every scan by the home
    /// detected from the chosen album (HomeDetection) or the user's override in Settings; these values are only
    /// a fallback for albums without any GPS photos (where home doesn't affect anything) and a fixture for tests.
    var homeLatitude = 40.728
    var homeLongitude = -74.078
    /// Home detection groups photos into cells this many degrees wide (~2 km).
    var homeDetectionCellDegrees = 0.02

    /// A new moment starts when the gap from the previous photo is over this.
    var momentMaxGap: TimeInterval = 3 * 3600
    /// ...or when the distance from the previous photo is over this.
    var momentMaxDistanceMeters: Double = 2_000

    /// A moment farther than this from home counts as "away".
    var tripMinDistanceFromHomeMeters: Double = 50_000
    /// Consecutive away moments stay in the same trip while the gap between them is under this.
    var tripMaxGapBetweenMoments: TimeInterval = 2 * 86_400
    /// A trip is labelled "City A & City B" when the second city holds at least this share of its moments.
    var tripSecondCityMinShare = 0.25

    /// Photos without GPS join the nearest moment in time if within this window.
    var unlocatedMaxGap: TimeInterval = 3 * 3600

    /// How many photos per moment to show (and, in Step 3b, to tag).
    var representativesPerMoment = 5

    // MARK: Vision tagging (Step 3b)

    /// Longest side, in pixels, of the image handed to Vision.
    var tagImagePixelSide: CGFloat = 360
    /// Vision labels below this confidence are dropped.
    var tagMinConfidence: Float = 0.3
    var tagsPerMoment = 3
    var tagsPerTrip = 5
    /// How many photos are loaded and tagged at the same time.
    var taggingConcurrency = 4
    /// Most photos tagged per scan (sample photos of experiences' moments, best experiences first).
    var maxTaggedPhotos = 1_500

    // MARK: Landmarks (Step 3c)

    /// A moment matches a landmark when one of its GPS photos is within this distance.
    var landmarkDefaultRadiusMeters: Double = 250
    /// Wider radius for big areas, where photos are often far from the landmark's single coordinate.
    var landmarkLargeAreaRadiusMeters: Double = 1_000
    /// Landmark types containing any of these words get the large radius (whole words, so "parking" isn't "park").
    /// Keep in sync with LARGE_AREA_WORDS in tools/build_landmarks.py.
    var landmarkLargeAreaTypeWords: Set<String> = [
        "park", "beach", "island", "garden", "forest", "mountain", "lake", "zoo", "cemetery", "airport", "aerodrome",
    ]
    /// Score = sitelinks × type weight × falloff, where falloff goes from 1 at the landmark to this at the radius edge.
    var landmarkScoreAtRadiusEdge = 0.25
    /// Multipliers for types that are near almost everything in a city, so real sights win over them.
    var landmarkTypeWeights: [String: Double] = ["station": 0.25]
    /// How many landmarks a trip label names, e.g. "Vessel & Central Park, Manhattan".
    var tripLandmarksInLabel = 2

    // MARK: Experiences (Step 4)

    /// Vision labels (exact identifiers) that point to each category. Scores are the tags' summed confidence.
    var categoryTagLabels: [ExperienceCategory: Set<String>] = [
        .culinary: ["food", "seafood", "dessert", "frozen_dessert", "baked_goods", "bread", "cake", "fruit", "vegetable",
                    "sushi", "pizza", "drink", "coffee", "tea_drink", "wine", "red_wine", "white_wine", "sparkling_wine",
                    "wine_bottle", "cocktail", "beer", "restaurant", "tableware", "dining_room"],
        .coast: ["beach", "shore", "ocean", "sand", "sand_dune", "surfing", "surfboard", "island", "pier", "dock",
                 "boat", "sailboat", "lighthouse", "cliff"],
        .nature: ["mountain", "hill", "forest", "jungle", "hiking", "flower", "garden", "plant", "grass", "lake", "river",
                  "waterfall", "canyon", "volcano", "desert", "snow", "park", "animal", "bird", "deer"],
        .culture: ["museum", "art", "painting", "statue", "monument", "castle", "theater", "lantern", "belltower",
                   "clock_tower"],
        .city: ["cityscape", "skyscraper", "street", "alley", "building", "bridge", "streetcar", "train_station", "road"],
        .nightlife: ["nightclub", "concert", "fireworks", "night_sky", "bar"],
    ]
    /// Vision has no temple or shrine labels, so a matched landmark's type also votes for a category.
    var categoryLandmarkTypeWords: [ExperienceCategory: Set<String>] = [
        .culture: ["temple", "shrine", "church", "basilica", "cathedral", "mosque", "museum", "gallery", "monument",
                   "memorial", "castle", "palace", "theatre", "theater", "statue", "library"],
        .nature: ["park", "garden", "mountain", "forest", "lake", "waterfall", "zoo", "valley", "gorge"],
        .coast: ["beach", "island", "bay", "lighthouse", "pier", "promenade"],
        .city: ["skyscraper", "building", "tower", "bridge", "square", "street"],
        .culinary: ["restaurant", "market"],
        .nightlife: ["nightclub", "bar"],
    ]
    /// Points each matched landmark moment adds to its type's category (comparable to one strong tag).
    var categoryLandmarkWeight = 1.0
    /// Used when nothing matches.
    var defaultCategory = ExperienceCategory.city
    var categoriesPerExperience = 3

    var profileHighlightsCount = 5

    // MARK: Experience grouping and ranking (Step 7b)

    /// Non-trip moments merge into one experience while the gap between them is under this, even across cities.
    var outingMaxGap: TimeInterval = 4 * 3600
    /// A non-trip group is an experience if it has a matched landmark or at least this many photos.
    var outingMinPhotos = 8

    /// Worthiness (deterministic) =
    ///   fame × log(1 + top landmark sitelinks)
    /// + new country bonus, or new city bonus (first-ever visit, home excluded)
    /// + distance × log(1 + km from home)
    /// + photos × log(1 + photo count)
    /// + duration × log(1 + hours)
    /// Logs keep any single term (especially distance) from dominating.
    var worthinessFameWeight = 1.0
    var worthinessNewCountryBonus = 2.0
    var worthinessNewCityBonus = 1.0
    var worthinessDistanceWeight = 0.5
    var worthinessPhotoWeight = 0.5
    var worthinessDurationWeight = 0.5

    /// Final rank = worthiness weight × normalized worthiness + memorability weight × normalized memorability
    /// (Claude's 1–10, only when AI suggestions is on). Without memorability: worthiness alone.
    var rankWorthinessWeight = 0.7
    var rankMemorabilityWeight = 0.3

    // MARK: Profile (Step 7d)

    /// Rarity (Profile → Highlights, Ask "rarest") =
    ///   one-time country bonus, or one-time city bonus (the only experience in that place; home excluded)
    /// + distance × ln(1 + km from home)
    /// + uncommon × max(0, log10(rarityPopulationReference) − log10(population of its smallest city))
    /// + memorability × Claude's 1–10, when available.
    var rarityOneTimeCountryBonus = 2.0
    var rarityOneTimeCityBonus = 1.0
    var rarityDistanceWeight = 0.5
    var rarityUncommonWeight = 0.5
    /// A city this big (or bigger) isn't unusual at all.
    var rarityPopulationReference = 10_000_000.0
    var rarityMemorabilityWeight = 0.3

    /// Places tab: an experience within metroRadiusMeters of a city with more than metroMinPopulation people
    /// joins the most populous such city; otherwise it uses its own city.
    var metroMinPopulation = 1_000_000
    var metroRadiusMeters: Double = 40_000
    /// Friendlier names for some metro cities.
    var metroDisplayNames: [String: String] = ["New York City": "New York"]

    /// Claude titles longer than this (characters) are rejected and the template title is kept.
    /// The prompt asks for 25–45; only the upper bound is enforced.
    var aiTitleMaxCharacters = 45
    /// Only the top experiences by worthiness get Claude titles; the rest keep their template titles.
    var aiTitlesMaxExperiences = 60
    /// Experiences per titles request (60 → 3 requests). Each reply (~400 tokens) stays well inside
    /// aiTitlesMaxTokens and each body (~6 KB) well under the proxy's 64 KB limit.
    var aiTitlesPerRequest = 20
    /// max_tokens per titles request; the proxy allows up to 4096.
    var aiTitlesMaxTokens = 2000
    var coverPhotosPerExperience = 3

    // MARK: Earn (Step 5)

    /// Check-in radius for offers that don't set their own.
    var checkInDefaultRadiusMeters: Double = 150
    /// A GPS fix rougher than this can't verify a check-in.
    var checkInMaxAccuracyMeters: Double = 100

    static let standard = ClusterConfig()
}
