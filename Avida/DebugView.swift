import SwiftUI
import CoreLocation

/// The original stats screen from Steps 1–3, kept behind the "Developer" link.
struct DebugView: View {
    let model: AppModel

    private var result: LibraryScanResult? { model.result }
    private var isScanning: Bool { model.isScanning }
    private var tagging: TaggingModel { model.tagging }

    var body: some View {
        albumView
            .navigationTitle("Developer")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var albumView: some View {
        if isScanning && result == nil {
            ProgressView("Reading your photo library…")
        } else if case .scanned(let summary, let clusters) = result {
            List {
                Section {
                    statsHeader(summary)
                    rescanButton
                }

                EarnDebugSection(store: model.earn)
                ClaudeDebugSection(model: model)

                ForEach(clusters.trips) { trip in
                    Section {
                        // One photo from each of the trip's first 5 moments: the middle representative.
                        ThumbnailStrip(ids: trip.moments.prefix(5).compactMap { moment in
                            moment.representativeIDs.isEmpty ? nil : moment.representativeIDs[moment.representativeIDs.count / 2]
                        }, side: 80)
                        TagChips(summary: tagging.trip(trip))
                        ForEach(trip.moments) { momentRow($0) }
                    } header: {
                        tripHeader(trip)
                    }
                }

                Section("Home & nearby moments (\(clusters.otherMoments.count))") {
                    if clusters.otherMoments.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(clusters.otherMoments) { momentRow($0) }
                }

                Section("Unassigned") {
                    Text("\(clusters.unassignedPhotoIDs.count + summary.withoutDate) photos")
                    Text("No GPS and more than 3 h from any moment, or no date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func statsHeader(_ summary: LibrarySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.source).font(.headline)
            if summary.isLimited {
                Text("Limited access: only the photos you selected were scanned.")
            }
            Text("\(summary.skippedScreenshots) screenshots and \(summary.withoutDate) photos without a date skipped")
            Text("\(summary.photoCount) photos · \(summary.withGPS) with GPS · \(summary.withoutGPS) without")
            Text("\(dateOnly(summary.earliestDate)) – \(dateOnly(summary.latestDate))")
            if tagging.isRunning {
                Text("Tagging \(tagging.done) of \(tagging.total)")
                    .foregroundStyle(.primary)
            }
            Text("Metadata \(seconds(summary.metadataTime)) · Clustering + places \(seconds(summary.clusteringTime))")
            Text("Images \(seconds(tagging.imageTime)) · Vision \(seconds(tagging.visionTime))"
                 + (tagging.wallTime.map { " · Tagging total \(seconds($0))" } ?? ""))
            if tagging.notOnDevice + tagging.failed > 0 {
                Text("Not tagged: \(tagging.notOnDevice) not on device, \(tagging.failed) Vision errors")
            }
            let missing = ThumbnailLoader.shared.missingIDs.count
            if missing > 0 {
                Text("\(missing) thumbnails not on this device (shown grey)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func tripHeader(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.placeLabel())
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(dateOnly(trip.start)) – \(dateOnly(trip.end)) · \(trip.moments.count) moments · \(trip.photoCount) photos")
                .font(.caption)
        }
        .textCase(nil)
    }

    private func momentRow(_ moment: Moment) -> some View {
        NavigationLink {
            MomentPhotosView(moment: moment, title: moment.landmark?.name ?? moment.city?.name ?? "Moment")
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                momentSummary(moment)
                TagChips(summary: tagging.moment(moment))
                ThumbnailStrip(ids: moment.representativeIDs)
            }
        }
    }

    /// Landmark in bold with its description, then city and country.
    /// Without a landmark, the city and country take the bold line.
    private func momentSummary(_ moment: Moment) -> some View {
        let cityLine = moment.city.map { "\($0.name), \(PlaceLookup.countryName($0.countryCode))" } ?? "Unknown place"
        return VStack(alignment: .leading, spacing: 2) {
            if let landmark = moment.landmark {
                Text(landmark.name).font(.subheadline.bold())
                if !landmark.description.isEmpty {
                    Text(landmark.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(cityLine).font(.caption)
            } else {
                Text(cityLine).font(.subheadline.bold())
            }
            HStack {
                Text(timeRange(moment.start, moment.end))
                Spacer()
                Text("\(moment.photoIDs.count) photos")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var rescanButton: some View {
        Button("Rescan") {
            Task { await model.scan() }
        }
        .disabled(isScanning)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.red)
    }

    /// Stage durations in the header; summed time for image loading and Vision.
    private func seconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2f s", value)
    }

    private func dateOnly(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .omitted) ?? "—"
    }

    /// "Mar 3, 2026, 2:10 PM – 5:40 PM", or full dates on both ends when it spans days.
    private func timeRange(_ start: Date, _ end: Date) -> String {
        let startText = start.formatted(date: .abbreviated, time: .shortened)
        if start == end { return startText }
        let endText = Calendar.current.isDate(start, inSameDayAs: end)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(date: .abbreviated, time: .shortened)
        return "\(startText) – \(endText)"
    }
}

/// Developer tools for the Earn loop.
private struct EarnDebugSection: View {
    let store: EarnStore

    @State private var locator = LocationFetcher()
    @State private var message: String?
    @State private var placing = false  // used by placeDemo(), whose button is hidden
    @State private var confirmReset = false

    var body: some View {
        Section("Earn") {
            // "Place demo offer at my current location" is hidden with the check-in flow (Step 7a); placeDemo() is kept.
            if let demo = store.state.demoLocation {
                Text("Demo offer at \(demo.latitude.formatted(.number.precision(.fractionLength(5)))), \(demo.longitude.formatted(.number.precision(.fractionLength(5))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Text("List \(store.state.list.count) · Ledger \(store.state.ledger.count) · Verified \(store.state.verified.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Reset Earn data", role: .destructive) { confirmReset = true }
                .confirmationDialog("Delete the List, rewards, verified experiences and check-in photos?",
                                    isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Reset Earn data", role: .destructive) {
                        store.reset()
                        message = "Earn data reset."
                    }
                }
        }
    }

    private func placeDemo() async {
        placing = true
        defer { placing = false }
        do {
            let location = try await locator.currentLocation()
            store.placeDemoOffer(at: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
            message = "Placed (±\(Int(location.horizontalAccuracy)) m). Check in from Earn → Demo offer."
        } catch {
            message = error.localizedDescription
        }
    }
}

/// One short round trip to Claude through the proxy. Respects the AI suggestions switch.
private struct ClaudeDebugSection: View {
    let model: AppModel
    @State private var reply: String?
    @State private var isSending = false

    var body: some View {
        Section("Claude") {
            Text("AI always on (text only) · model \(LLMClient.model)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await test() }
            } label: {
                Label(isSending ? "Sending…" : "Test Claude", systemImage: "sparkles")
            }
            .disabled(isSending)
            if let reply {
                Text(reply)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            NavigationLink("Show last request") { LastRequestView() }
            Button {
                model.aiTitles.reset()
                Task { await model.writeTitles() }
            } label: {
                Label(model.isWritingTitles ? "Writing titles…" : "Rewrite titles (\(model.aiTitles.entries.count) saved)",
                      systemImage: "text.badge.star")
            }
            .disabled(model.isWritingTitles)
            if let run = model.lastTitleRun {
                Text("Last titles run \(run.date.formatted(date: .omitted, time: .standard)): \(run.summary)")
                    .font(.caption)
                    .foregroundStyle(run.error == nil ? Color.secondary : Color.red)
                    .textSelection(.enabled)
            } else {
                Text("No titles run yet this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func test() async {
        isSending = true
        defer { isSending = false }
        do {
            let text = try await LLMClient().send(
                messages: [.user("Reply with one short, friendly sentence confirming the Avida app reached you.")],
                maxTokens: 256,
                effort: "low"
            )
            reply = "Reply: \(text)"
        } catch {
            reply = "Error: \(error.localizedDescription)"
        }
    }
}

/// The exact JSON body of the most recent request to the proxy (what Claude saw, minus the API key the proxy adds).
private struct LastRequestView: View {
    private let log = LLMRequestLog.shared
    @State private var formatted = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let body = log.lastBody {
                    Text("Sent \(log.lastDate?.formatted(date: .abbreviated, time: .standard) ?? "") · \(body.utf8.count) bytes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("View", selection: $formatted) {
                        Text("Formatted").tag(true)
                        Text("Exact bytes").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(formatted ? Self.pretty(body) : body)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No request sent yet in this session.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Last request")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func pretty(_ body: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return body }
        return String(decoding: data, as: UTF8.self)
    }
}
