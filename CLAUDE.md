# Avida iOS app

SwiftUI app, iOS 18.0 minimum deployment target. No third-party packages unless asked.

## The app today (branch jin-recap, after Step 7e)

Onboarding (ContentView), as in Step 4:
1. Welcome: "Let Avida read your life." with three feature rows → Allow Photo Access. Small print: "Avida reads the camera photos in your library, on this iPhone." and the AI line "Avida uses Claude to write your experience titles. Only text is sent, never photos." (AIDisclosure.line). Denied/restricted → a message with Open Settings.
2. Analyzing: "Analyzing your photos." with the progress ring, percentage and Photos / Moments / Experiences counts. The ring covers the whole scan (ScanProgress: reading 30%, tagging 55%, titles 15%; capped at 99% until experiences are ready). Status line: "Reading your photo library…" (Limited: "Reading the photos you selected…") → "Looking closely at X of Y photos" → "Writing your titles…".
3. Review: "We found N experiences." with every experience as a card (tap → ExperienceDetailView); with Limited access, a note to allow Full Access → "Create my profile" → tabs, opening on Profile.
No album picker, name screen or AI opt-in screen (removed in Step 7e).

Scanning (LibraryScanner): the whole photo library, camera photos only: images in the user's library (includeAssetSourceTypes = .typeUserLibrary, so no shared/synced items), skipping screenshots (.photoScreenshot), videos (so screen recordings) and photos without a creation date. Photos without GPS still don't drive clustering (they join a moment within 3 h, found by binary search). With Limited access only the selected photos are scanned and the app says so. Fetching runs off the main thread with progress callbacks; experiences are cached per scan / tag count / title count. Vision tags only the representative photos of moments that belong to experiences, best experiences first, up to ClusterConfig.maxTaggedPhotos (1,500).

Home: detected on every scan from the library (HomeDetection: the ~2 km place, scored with its neighbours, where photos were taken on the most distinct days), unless the user set one in Settings ("Use my current location"; "Detect from my photos" clears it). Trips, novelty and rarity are measured from it.

AI (always on, text only): no switch. After tagging, Claude writes titles + memorability for the top ClusterConfig.aiTitlesMaxExperiences (60) experiences by worthiness that don't have a saved title, in batches of aiTitlesPerRequest (20) with max_tokens aiTitlesMaxTokens (2000); bodies ~6 KB. Everything else keeps its template title. Results are saved in Documents/ai-titles.json; the last run's outcome and error are on the Developer screen. Ask (Profile) always works when the proxy config is present.

Tabs (MainTabView):
- Profile: avatar + name (Settings; empty → "Your profile" with a person symbol) + "N LIFE EXPERIENCES"; gear → Settings; Ask section (5 prefilled questions; answers link [eN]/[oN]/[cN]); tabs:
  - Highlights: top 5 by rarity (Rarity: one-time country/city bonus, ln distance, unusual = small population from cities.tsv, + memorability when Claude rated it), numbered 01–05.
  - All: every experience (and verified check-ins) newest first, no ranking.
  - Places: metro groups (MetroGrouping: an experience within 40 km of a city of 1M+ joins the most populous such city, e.g. Manhattan/Brooklyn/Hoboken → "New York"; else its own city). Row = cover, name, country, count, sorted by count; tap → that place's experiences newest first.
  - "Review your N experiences" and a small "Developer" link at the bottom.
- Earn: 6 sponsored experiences (JR East, Hoshinoya, City of Miyazaki, JAL, City of Hiroshima, ANA; text names, "Partner brands shown are illustrative."), photo tiles or gradients, "Add to List" / "Added ✓". Check-in/verification is hidden (code kept).
- Connect: 4 mock friends (stories row of faces) → Experience Profile with numbered highlights → detail with stops and Add to List ("From {friend}").
- List: everything saved from Earn and Connect, newest first; tap for detail, swipe to remove (EarnState.list in Documents/earn.json).
- Settings (from Profile): name, home (detected / set by you), and the Claude line (AIDisclosure.line).
- Developer (from Profile): scan stats (source, Limited, skipped screenshots / undated, GPS counts, timings), Earn tools (Reset Earn data), Claude (Test Claude, Show last request, Rewrite titles, last titles run and its error).

Still specific to the original developer or demo (not personal data, but worth knowing):
- Bundle id com.aishwarya.hackathon.Avida and signing team PQ2Z794HCW (Personal Team) in the project; another developer must change both to build to their phone.
- Avida/LLMConfig.json (gitignored) holds this developer's proxy URL and app token; a build without it can't reach Claude (titles stay templates, Ask shows the "missing config" error).
- landmarks.tsv only covers NYC metro, Mumbai + Thane, Goa, Tokyo, Kyoto, Nagano and Miyazaki; photos elsewhere get city names (cities.tsv is worldwide) but no landmark names. Re-run tools/build_landmarks.py with more boxes to widen it. Its User-Agent contact defaults to github.com/aishwarya4114 (AVIDA_CONTACT overrides).
- Earn offers (offers.json) and Connect friends (connect.json) are fixed demo content, the same for everyone.
- ClusterConfig.homeLatitude/homeLongitude (Jersey City) remain only as the fallback for libraries with no GPS photos (where home changes nothing) and as unit-test fixtures. Tests and some code comments use NYC/Jersey City examples.

## Current state (step history)
- Step 0 done: photo permission works, usage description set, iOS 18.0 target.
- Xcode now in /Applications and xcode-select fixed.
- Step 1 done: AlbumScanner reads images from the chosen album (was AlbumConfig.albumName until Step 7d) off the main thread (count, date range, GPS vs. no GPS).
- Step 2 done: clustering into moments and trips.
  - Thresholds and home location live in ClusterConfig.swift (home 40.728, -74.078; moment: >3 h or >2 km from previous photo; trip: moments >50 km from home, <2 days apart; no-GPS photos join nearest moment within 3 h).
  - Clustering.swift is pure (PhotoPoint: id, date, lat, lon), no PhotoKit, unit tested in AvidaTests (Swift Testing).
  - Screen: stats header, trips with their moments, home/nearby moments, unassigned count.
- Step 2b done: offline place names.
  - Avida/cities.tsv (bundled) is built from GeoNames cities15000 by tools/build_cities.py: name, country code, lat, lon, population, sorted by latitude. Neighborhoods (PPLX) and historical/abandoned/destroyed places are skipped.
  - PlaceLookup finds the nearest city (binary search on latitude band, haversine). Country names come from Locale. No CLGeocoder, no network.
  - Each Moment stores its nearest city. Trip label: most common city + country, or "A & B, Country" when the second city has ≥25% of moments (ClusterConfig.tripSecondCityMinShare).
  - Distance from home is internal only (trip logic), not on screen.
  - To refresh the data: download https://download.geonames.org/export/dump/cities15000.zip, unzip, then run `python3 -I tools/build_cities.py <path>/cities15000.txt Avida/cities.tsv`.
- Step 3a done: photos on screen.
  - RepresentativePhotos.pick (pure, unit tested): up to 5 per moment (ClusterConfig.representativesPerMoment), spread evenly by time: first, last, then nearest photo to each evenly spaced time, no duplicates. Stored as Moment.representativeIDs. Step 3b tags exactly these.
  - ThumbnailLoader: PHCachingImageManager, small target size, isNetworkAccessAllowed = false, highQualityFormat + fast resize, NSCache. Missing (not on device) thumbnails show grey and are counted in the stats header.
  - Screen: NavigationStack. Each moment row has a strip of its representatives; each trip has a strip with the middle representative of its first 5 moments. Tapping a moment opens a lazy grid of all its photos (with startCaching/stopCaching).
- Step 3b done: Vision tagging, on device.
  - PhotoTagger: loads a ~360 px image per representative photo (isNetworkAccessAllowed = false; not on device → skipped and counted), runs VNClassifyImageRequest. (Face detection was removed in Step 3c: no people counts anywhere.)
  - TaggingModel runs it in a task group, ClusterConfig.taggingConcurrency (4) at a time, restarted on Rescan; shows "Tagging X of Y".
  - TagAggregation (pure, unit tested with made-up labels): drop labels < tagMinConfidence (0.3), sum confidence per label; moment = top tagsPerMoment (3); trip = sum of its moments' tag scores, top tagsPerTrip (5). Ties alphabetical.
  - Header timings: metadata fetch, clustering + place lookup (in AlbumSummary), image loading and Vision (summed per photo across workers), and tagging wall time.
  - Screen: tag chips under each moment and trip.
- Step 3c done: landmarks, on device at runtime.
  - Avida/landmarks.tsv (bundled, ~585 KB, ~5.4k items) is built by tools/build_landmarks.py from the Wikidata SPARQL endpoint: items with P625 inside bounding boxes for NYC metro (incl. Jersey City, Hoboken), Mumbai + Thane, Goa, Tokyo, Kyoto, Nagano and Miyazaki prefectures; ≥5 sitelinks; English label. Columns: QID, label, description, instance-of type label, lat, lon, sitelinks. Settlements/admin areas, regions, destroyed/defunct places, events, and non-places (companies, languages…) are filtered out; see the patterns in the script.
  - Refresh: `python3 -I tools/build_landmarks.py Avida/landmarks.tsv <scratch>/wikidata_raw.json` (the second arg caches raw results so filters can be re-tuned without re-querying; the endpoint rate-limits). AVIDA_CONTACT env var sets the User-Agent contact.
  - Matching (Landmarks.swift; LandmarkMatching is pure and unit tested): candidates near each GPS photo of a moment; radius 250 m by default, 1,000 m for big-area types (park, beach, island, garden, forest, mountain, lake, zoo, cemetery, airport); score = sitelinks × type weight (stations 0.25) × distance falloff (1 at the point, 0.25 at the radius edge), using the nearest GPS photo. Best is stored as Moment.landmark (name, description, sitelinks). No match → city.
  - All landmark thresholds are in ClusterConfig.
  - Screen: moment shows landmark in bold, description in grey, then "City, Country"; trip label = up to 2 most famous matched landmarks in visit order + main city ("Vessel & Central Park, Manhattan"), else the city label.
- Step 4 done: experiences and the designed UI. (Grouping, score and titles were reworked in Step 7b; see there.)
  - Experiences.swift (pure, tested in ExperiencesTests): every trip is an experience; every non-trip calendar day with a matched landmark is one too (all that day's non-trip moments are its stops).
  - Titles: trips "Exploring {city}" (or "A & B"); landmark days = up to 2 most famous landmarks in visit order ("Vessel & Central Park"). Place = main city (PlaceNaming in PlaceLookup.swift, shared with the debug trip label).
  - Category: Vision tags vote via ClusterConfig.categoryTagLabels (exact Vision identifiers, weighted by tag score); matched landmark types also vote via categoryLandmarkTypeWords (Vision has no temple/shrine labels). Up to 3, strongest first; default City.
  - Score = scoreFameWeight × top landmark sitelinks + scorePhotoWeight × photos + scoreDistanceWeightPerKm × km from home (1.0 / 0.3 / 0.01). Ranked best first; Profile highlights = top 5.
  - Look (Theme.swift): light only (preferredColorScheme + UIUserInterfaceStyle = Light), cream #F9F5EF, charcoal #2A2826, terracotta #B4472E (also AccentColor), serif "AVIDA" wordmark, bold sans headings, serif for rank numbers/display.
  - Flow (ContentView): Welcome → Analyzing (progress ring, waits for tagging) → Review ("We found N experiences.", cards, "Create my profile") → Profile (ProfileConfig.name, Highlights/All/Places). ExperienceDetailView: hero, category, title, place/duration, photo row, numbered stops, photo grid. AppModel holds scan/tagging state.
  - Old stats screen = DebugView, linked as "Developer" at the bottom of Profile.
  - design-reference/ (mockups + deck) lives at the repo root, outside the synced Avida/ folder: never move it into the app target.
- Step 5 done: the Earn loop, fully on device, no backend. (Offers, partner names and the save/check-in UI were replaced in Step 7a; the check-in code and ledger remain.)
  - Tabs (MainTabView, shown after Review): Profile, Earn, Connect (placeholder until Step 7c). List added in Step 7a.
  - Offers: Avida/offers.json (3 offers: Central Park / Bethesda Terrace, Kiyomizu-dera, and a Demo offer whose location is set from Developer → "Place demo offer at my current location"). Fields: id, title, partner, rewardAmount, rewardUnit, category, description, place, duration, 2–3 stops, latitude/longitude, checkInRadiusMeters (default ClusterConfig.checkInDefaultRadiusMeters = 150), isDemo.
  - Partner names are invented, text only, always with an "Illustrative partner" label. No real brands or logos. Cards use a category gradient + SF Symbol instead of photos.
  - Flow: Earn list → OfferDetailView (numbered stops, reward row, "Save to do") → saved shows "Check in" → CheckInView: one-shot Core Location (When In Use, LocationFetcher) → EarnLogic.checkIn: within radius and accuracy ≤ checkInMaxAccuracyMeters (100 m) → system camera (CameraPicker) for one photo → saved to Documents/CheckIns/<uuid>.jpg (complete file protection, never the photo library) → "Verified" screen. Too far shows the distance and doesn't verify; rough fix asks to retry.
  - Verification credits the ledger once per offer and records a VerifiedExperience (date, place, coordinates, distance, photo file). My Rewards (from Earn's top-right) shows balances per partner/unit and verified experiences. Verified experiences also appear in Profile → All with a "Verified" badge and count toward "N LIFE EXPERIENCES".
  - Storage: Documents/earn.json (EarnState: savedOfferIDs, ledger, verified, demoLocation) via EarnStore. Developer screen has "Reset Earn data" (deletes earn.json and CheckIns/).
  - Pure + tested (EarnLogicTests): status, save toggle, distance/accuracy check, verify (once per offer), balances, demo location, JSON round-trip, bundled offers.
  - Usage descriptions are build settings: INFOPLIST_KEY_NSCameraUsageDescription, INFOPLIST_KEY_NSLocationWhenInUseUsageDescription.
  - Deliberately NOT built yet: App Attest, server-side verification, or any anti-spoofing beyond the on-device GPS radius + accuracy check and a live camera photo. A jailbroken or location-spoofed device can fake a check-in. Rewards are local numbers only; nothing is sent to partners.
- Step 6a done: Claude plumbing, no agent logic yet. (The AI suggestions switch was removed in Step 7e: AI is always on, text only.)
  - tools/proxy: Cloudflare Worker (src/index.js, wrangler.toml, README.md with deploy steps). POST /v1/messages only; requires x-avida-token == APP_TOKEN secret (constant-time); adds ANTHROPIC_API_KEY secret and anthropic-version 2023-06-01; forwards to api.anthropic.com; passes status/body through. Limits: ALLOWED_MODELS (claude-haiku-5-5), MAX_TOKENS_CAP (4096), no streaming, 64 KB body. No body logging. The app token ships in the app, so it's a speed bump only; keep an Anthropic spend limit.
  - App config: Avida/LLMConfig.json (gitignored; proxyURL + appToken), copied from config/LLMConfig.example.json.
  - LLMClient.swift: AISettings (UserDefaults "aiSuggestionsEnabled", default false); LLMClient.send(system:messages:maxTokens:effort:) throws .disabled before loading config or building a request when the switch is off, and re-checks right before sending. Model claude-haiku-5-5. Parses text blocks only (ignores thinking), surfaces API/proxy error objects and refusals. Transport is the LLMTransport protocol (not a closure: closure isolation differed between the app and test targets and crashed).
  - Profile → gear → SettingsView: "AI suggestions" switch with the explanation text.
  - Developer → Claude → "Test Claude": one short message (effort low), shows the reply or the error.
  - Tests: LLMClientTests (off by default, no request when off, request shape: proxy URL, token header, no x-api-key, model/body; parsing, errors, refusal, missing config).
- Step 6b done: the Ask bar, a tool-calling agent over the user's experiences. (Free-text field replaced by prefilled questions in Step 7b.)
  - ExperienceTools.swift (pure, tested): snapshot() turns experiences + verified check-ins into text-only ExperienceRecords with short ids (e1 = best score, …; verified check-ins after). No PhotoKit identifiers, photo file names, coordinates or image data. Tools: search_experiences(text?, category?, city?, country?, year?) (≤20, best score first), get_experience(id) (with stops), stats(group_by: country|city|year|category; category = primary), top_experiences(n ≤ 10, by: score|rarity; rarity = scoreFameWeight × top sitelinks + scoreDistanceWeightPerKm × km). Results are compact sorted-key JSON; bad input/unknown tool → {"error"} with is_error.
  - AskAgent.swift: Messages API tool use through LLMClient.createMessage(JSONValue). Up to 5 tool rounds; the assistant turn is echoed back verbatim (thinking blocks + signatures). After round 5 the results get a "answer now" text block and the next request sets tool_choice {type: none}. System prompt: answer only from tool results, never invent, 2–4 sentences, refer to experiences as [eN].
  - LLMClient now has createMessage(_ body: JSONValue) (same switch gate, re-check before send) and records the exact body in LLMRequestLog; send() is built on it.
  - AskBarView on Profile under the name: field + chips "What defines me?", "Rarest experiences", "Where have I been?". Answer card shows the question, the answer with [eN] replaced by the experience title as a terracotta link (opens ExperienceDetailView or VerifiedExperienceView), and the tools used. Switch off → "Turn on AI suggestions to ask" (links to Settings), sends nothing.
  - Developer → Claude → "Show last request": the exact JSON body of the latest request (formatted or exact bytes).
  - Tests: ExperienceToolsTests (filters, fields, stops, stats, top by score vs rarity, errors, no photo data in snapshot output) and AskAgentTests with a scripted fake transport (tool call → result → answer, thinking echoed, nothing sent when off, 5-round limit then tool_choice none, unknown tool error, request log = exact body, [eN] parsing).
- Step 7a done (branch jin-recap): Earn rework per Jin's recap, and a List tab.
  - offers.json now has 6 sponsored experiences, partner names as text only (no logos): JR East "Discover Old Kyoto After Dark" (Kyoto, +500 JR Points), Hoshinoya "Sleep Above the Clouds" (Karuizawa, +2,000 Hoshinoya Points), City of Miyazaki "Find Miyazaki's Hidden Coast" (+1,000 Miyazaki City Tokens), JAL "Snow Monkeys in Nagano" (+750 JAL Miles), City of Hiroshima "Hiroshima, From Peace to Plates" (+1,000 Hiroshima City Tokens), ANA "Old Tokyo to the Sky" (+1,000 ANA Miles). Each: category, place, duration, 3 real attractions as stops, optional images. Earn shows "Partner brands shown are illustrative." at the bottom. The demo offer is gone (isDemo support kept).
  - Images: 12 photo tiles cropped from design-reference/ mockups (photos only, no UI or logos) in Assets.xcassets/Earn (earn-kyoto/clouds/miyazaki/monkeys-1…3, ~310 KB). Hiroshima and ANA use the category gradient. The PNGs/PDF in design-reference/ themselves are still never added to the target.
  - No verification for now: one "Add to List" button (toggles to "Added ✓") on cards and detail. CheckInView, LocationFetcher, CameraPicker, the ledger, My Rewards and the Developer "Place demo offer" action are kept in code but not reachable from the UI.
  - List tab (ListTabView): Profile, Earn, Connect, List. Shows saved items newest first with photo (or gradient), title, partner, reward; tap opens OfferDetailView (or ListItemDetailView for non-offer items); swipe to remove.
  - List storage: EarnState.list ([ListItem]) in Documents/earn.json. ListItem has a Source (.offer(id) now, .connect(id) for the next step), a stable id ("offer:<id>" / "connect:<id>"), and its own copy of title, partner, reward, place, category, imageName, addedAt. Connect adds items with EarnStore.addToList(_:) and removes with removeFromList(_:). EarnState decoding tolerates older files (the old savedOfferIDs is ignored).
  - Tests: EarnLogicTests (List toggle/status, verify still works, bundled 6 offers + every image name resolves) and ListTests (offer item fields, no duplicates, offer/connect ids don't collide, newest first, JSON round-trip, old files load).
- Step 7c done (branch jin-recap): Connect, per Jin's recap (mock data, no backend).
  - connect.json: 4 friends (Lina, Ken, Marion, Alex) with home city, face asset, profile totals (experienceCount, countryCount) and 4–5 experiences each (real places and attractions: Amalfi Coast, Sorrento, Capri, Lapland northern lights, Kyoto, Zermatt, Nichinan coast, Tokyo, Chamonix, Lyon, Hakone, Iceland's Golden Circle, Karuizawa, Cinque Terre, Hiroshima). Each: id, title, place, country, category, year, description, optional image, 3 stops (Offer.Stop shape).
  - Images (Assets.xcassets/Connect, ~210 KB): 4 round faces cropped from the Connect mockup's stories row, and 9 photos cropped from the Connect, onboarding and "Let Avida read your life" mockups (photos only). Two are named for what they show, not the mockup caption: connect-winter-onsen (a person in a snowy hot spring, captioned "Snow Monkeys") and connect-tokyo-tower (a lit tower among skyscrapers). Some experiences reuse Earn tiles (earn-monkeys-1, earn-kyoto-1, earn-miyazaki-1, earn-clouds-1); Lapland, Iceland, Cinque Terre and Hiroshima use gradients. Faces are small (~70 px source) so they look soft.
  - ConnectViews.swift: stories row of round faces with names (first friend selected; selected = terracotta ring) → the friend's Experience Profile underneath (face, name, "N experiences · N countries", home, numbered highlights 01… with thumbnail, title, place · category · year, like our Profile) → ConnectExperienceDetailView (hero, category, title, place/year, "From {friend}", description, numbered stops, Add to List / Added ✓).
  - List integration: ListItem.connect(experience, from: friend) → source .connect("<friend>/<experience>"), partner line "From {friend}", no reward. EarnStore.toggleList(_ item:) / EarnLogic.toggle work for any source. List rows from Connect open ConnectExperienceDetailView via ConnectCatalog.lookup.
  - Tests: ConnectTests (data loads, 4–5 experiences with 3 stops each, every face and image resolves, Connect list item fields and toggle, ids per friend, lookup back to the experience).
- Step 7b done (branch jin-recap): experiences, worthiness, Claude titles, prefilled Ask.
  - Grouping (Experiences.swift): trips unchanged. Non-trip moments become "outings": consecutive moments merge while the gap from one's end to the next's start is under ClusterConfig.outingMaxGap (4 h), even across cities (Hoboken → Manhattan). An outing is an experience if it has a matched landmark or ≥ outingMinPhotos (8) photos. Experience.Kind is .trip / .outing. Place = up to 2 main places (PlaceNaming.mainCities, "Hoboken & Manhattan"). Outing template titles: landmarks, else "An evening in …" (starts 17:00+) / "A day in …".
  - Worthiness (pure, deterministic): worthinessFameWeight·ln(1+top sitelinks) + new-country bonus (2) or new-city bonus (1) + worthinessDistanceWeight·ln(1+km) + worthinessPhotoWeight·ln(1+photos) + worthinessDurationWeight·ln(1+hours); weights 1.0 / 0.5 / 0.5 / 0.5 in ClusterConfig. Novelty walks experiences in time order; home city/country (nearest city to the home coordinates) never counts as new. The old linear score weights are gone.
  - Ranking (pure): score = (0.7 × min–max normalized worthiness + 0.3 × (memorability − 1)/9), weights rankWorthinessWeight / rankMemorabilityWeight. Experiences without a memorability rating (and everything when AI is off) use normalized worthiness alone. Experience.score is 0…1; the Ask tools report it 0–100. Rarity (Ask) = fame and distance log terms.
  - Claude titles (AITitles.swift), only while AI suggestions is on: after tagging, AppModel.writeTitles() sends ONE request (structured outputs, output_config.format json_schema, effort low, max_tokens 4000) with a text-only list of experiences that don't have a saved title yet: short id e1…, kind, places, country, month/year, categories, landmark names, duration, photo count. No PhotoKit ids or coordinates. Reply is validated on the phone: known id, title non-empty, ≤ aiTitleMaxCharacters (45), single line, memorability integer 1–10, no max_tokens cutoff; invalid entries are dropped and any failure keeps the template titles. Saved in Documents/ai-titles.json (AITitleStore) keyed by experience id; later scans only ask about new experiences. With AI on, saved titles replace templates (Experience.templateTitle keeps the original) and memorability joins the rank. Developer → Claude → "Rewrite titles" clears and re-asks.
  - Titles fix: titles were only requested during a scan with AI already on, so turning AI on later never asked Claude, and every failure was silent. Now: requested after a scan, whenever AI suggestions is switched on (ContentView .onChange), and from Developer → Rewrite titles; sent in batches of ClusterConfig.aiTitlesPerRequest (40) so replies stay inside max_tokens and bodies under the proxy's 64 KB; LLM request timeout 120 s. Each run's outcome (titled/requested, rejections by reason, first error) is AppModel.lastTitleRun, shown on the Developer screen. The request shape was verified against the deployed proxy (200, schema-valid JSON). Note: Cloudflare blocks non-browser User-Agents like Python's with error 1010; the app's URLSession UA is fine.
  - Title style (prompt): one memorable sentence of 25–45 characters in Title Case, with examples "Slept Under the Northern Lights", "Dinner with a New York Legend", "Swam Beside Whale Sharks". Only the 45-character upper bound is enforced; longer titles keep the template. Every title Text in the UI has .lineLimit(2).
  - Flow: Welcome → Analyzing (scan → "Looking closely at X of Y photos" → "Writing your titles…" while Claude runs) → Review ("We found N experiences.", all of them) → each card opens ExperienceDetailView.
  - Ask (AskBarView): no text field; 5 prefilled questions ("What defines me?", "My rarest experiences", "Where have I been?", "My most memorable trip", "What should I do next?"). New tool list_suggestions(category?) returns Earn offers (o1…, with partner and reward) and Connect friends' experiences (c1…). Answers can link [eN] (own experiences), [oN] (OfferDetailView) and [cN] (ConnectExperienceDetailView).
  - Tests: ExperiencesTests (outing merge across cities, gap from config, qualification, titles, worthiness formula, distance can't dominate, novelty with home, ranking blend and fallback), AITitlesTests (request shape and no photo data, parsing and per-entry validation, fences, cutoff, writer asks once and only for new ones, nothing sent when off, store save/reload), AskAgentTests (list_suggestions, [o]/[c] links).
- Step 7d done (branch jin-recap): titles fix, app icon, Profile tabs, works on any phone. (Album picker, name and AI onboarding screens removed again in Step 7e; whole library instead of one album.)
  - Fix Claude titles: see the "Titles fix" note under Step 7b (trigger on AI switch-on, batches of 40, 120 s timeout, last run + error on Developer).
  - App icon: Assets.xcassets/AppIcon.appiconset/AppIcon.png, 1024×1024 RGB, no alpha, single universal size (from ~/Downloads/AvidaIcon-cream.png; it was never in the repo root).
  - Profile: Highlights by Rarity (ProfileRanking.swift, weights ClusterConfig.rarity*); All newest first; Places by MetroGrouping (ClusterConfig.metro*, metroDisplayNames ["New York City": "New York"], PlaceLookup.bigCities). Ask's "rarest" uses the same Rarity. Tests: ProfileRankingTests.
  - Any phone: UserPrefs (albumID/albumTitle, userName, didAskName, didAskAI, homeOverride); AlbumLibrary lists albums; AlbumScanner.scan(albumID:albumTitle:homeOverride:) detects home with HomeDetection and passes it to clustering; AppModel.home/homeCity come from the scan. AlbumConfig/ProfileConfig removed. Onboarding: OnboardingViews.swift. Settings: SettingsView(model:). Tests: HomeDetectionTests (most days beats one big day, ties, no GPS, cell size, cell-edge homes, city lookup) and UserPrefsTests.
- Step 7e done (branch jin-recap): back to the Step 4 onboarding, whole library, AI always on, batched titles.
  - "Restore original onboarding flow.": Welcome → Allow → Analyzing → "We found N" → Create my profile → Profile; album picker, name and AI opt-in screens removed (OnboardingViews.swift deleted). Name lives in Settings only (default "Your profile"). Why the phone showed no experiences before: Step 7d made the app re-run onboarding and scan whichever album was picked, and detected home from that album, which for a trip-heavy test album can land on a trip destination.
  - "Scan whole library.": AlbumScanner → LibraryScanner (camera photos only, Limited handled), AlbumConfig removed; Clustering matches GPS-less photos by binary search (same results as the old full scan; tested on 1,500 photos); tagging limited to experiences' photos (maxTaggedPhotos); ScanProgress drives the ring; experiences cached.
  - "AI always on.": AISettings, its switch and LLMError.disabled removed; AIDisclosure.line on Welcome and in Settings.
  - "Batch Claude titles.": top 60 by worthiness, batches of 20, max_tokens 2000, last error on Developer.

## Attribution (for the future About screen)
- Landmarks: Wikidata (https://www.wikidata.org), CC0 1.0 public domain dedication (no attribution required, but credit it anyway). Extracted via the Wikidata Query Service.
- Place names: GeoNames (https://www.geonames.org), licensed under Creative Commons Attribution 4.0 (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/). Data was converted to a compact format (fields subset, some place types removed). Show this in the app's About screen.

## Commands
- Build: `xcodebuild -project Avida.xcodeproj -scheme Avida -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- Test: `xcodebuild -project Avida.xcodeproj -scheme Avida -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' test`

## Hard rules
- All photo analysis runs on device. No network calls with photo data or derived data, with one exception:
  AI is always on, text only: LLMClient sends TEXT ONLY (experience places, months, categories, landmark names,
  durations, photo counts, and the Ask tools' text results) to Claude via the proxy, for titles and Ask. There is no
  switch; the Allow Photo Access screen and Settings say "Avida uses Claude to write your experience titles. Only text
  is sent, never photos." Never send photos, image data, thumbnails, PhotoKit identifiers, coordinates of individual
  photos, or anything else derived from pixels.
- The Anthropic API key lives only in the Cloudflare Worker secret. Never put it in the app, the repo, or LLMConfig.json.
- The scanner reads the whole photo library, camera photos only (no screenshots, screen recordings, shared/synced items, or photos without a creation date). With Limited access it reads only the selected photos and says so.
- Photo analysis uses PhotoKit metadata (creationDate, location) and Apple Vision only. The only cloud call in the app is LLMClient, under the text-only exception above.
- Work one step at a time. After each change, build with xcodebuild and stop so I can test on my iPhone.
- After each step, explain what changed in plain terms.

## Pipeline (build in this order)
0. Photo permission
1. Read album: count, date range, how many photos have GPS
2. Cluster into moments (time gaps) and trips (distance from home)
3. Vision tagging on 3–5 representative photos per cluster, with timing per stage
4. Experience cards: template title, place, dates, tags, worthiness score
5. Export experiences as JSON (format agreed with teammate)
