import SwiftUI

/// Profile: name, "N LIFE EXPERIENCES", the Ask bar, and Highlights / All / Places.
struct ProfileView: View {
    let model: AppModel
    let onReview: () -> Void

    enum Tab: String, CaseIterable {
        case highlights = "Highlights"
        case all = "All"
        case places = "Places"
    }

    @State private var tab: Tab = .highlights
    @State private var askTarget: AskTarget?

    var body: some View {
        let experiences = model.experiences
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Wordmark(size: 22)
                    Spacer()
                    NavigationLink {
                        SettingsView(model: model)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.text)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }
                .padding(.top, 8)
                header(count: experiences.count + model.earn.verified.count)
                    .padding(.top, 28)
                AskBarView(model: model, target: $askTarget)
                    .padding(.top, 24)
                tabBar
                    .padding(.top, 32)

                switch tab {
                case .highlights:
                    // The rarest experiences (Rarity: one-time places, distance, unusual places, memorability).
                    ForEach(Array(model.highlights.enumerated()), id: \.element.id) { index, experience in
                        row(experience, rank: index + 1, meta: "\(experience.place)  ·  \(experience.category.rawValue)  ·  \(experience.start.yearText)")
                    }
                case .all:
                    ForEach(allItems(experiences)) { item in
                        switch item {
                        case .photos(let experience):
                            row(experience, rank: nil, meta: "\(experience.place)  ·  \(experience.category.rawValue)  ·  \(experience.start.monthYear)")
                        case .verified(let verified):
                            verifiedRow(verified)
                        }
                    }
                case .places:
                    // Grouped by metro area (MetroGrouping), most experiences first.
                    ForEach(model.placeGroups) { group in
                        NavigationLink {
                            PlaceExperiencesView(group: group)
                        } label: {
                            PlaceRow(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if experiences.isEmpty && (tab != .all || model.earn.verified.isEmpty) {
                    Text("No experiences yet.")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.vertical, 32)
                }

                Button(action: onReview) {
                    HStack(spacing: 14) {
                        Image(systemName: "tray")
                        Text("Review your \(experiences.count) experiences")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                    }
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                    .padding(.vertical, 20)
                }
                .padding(.top, 8)

                NavigationLink {
                    DebugView(model: model)
                } label: {
                    Text("Developer")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .underline()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .padding(.horizontal, Theme.gutter)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $askTarget) { target in
            switch target {
            case .photos(let experience): ExperienceDetailView(experience: experience)
            case .verified(let verified): VerifiedExperienceView(verified: verified, store: model.earn)
            case .offer(let offer): OfferDetailView(offer: offer, store: model.earn)
            case .connect(let friend, let experience):
                ConnectExperienceDetailView(friend: friend, experience: experience, store: model.earn)
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 20) {
            Group {
                if initials.isEmpty {
                    Image(systemName: "person")  // name skipped in onboarding
                } else {
                    Text(initials)
                }
            }
                .font(.system(size: 34))
                .foregroundStyle(Theme.text)
                .frame(width: 92, height: 92)
                .background(Theme.fill, in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(model.prefs.displayName ?? "Your profile")
                    .font(Theme.display(38))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                EyebrowText("\(count) life \(count == 1 ? "experience" : "experiences")", color: Theme.text, size: 14)
            }
        }
    }

    private var initials: String {
        (model.prefs.displayName ?? "").split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    private var tabBar: some View {
        HStack(spacing: 28) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 10) {
                        EyebrowText(item.rawValue, color: tab == item ? Theme.text : Theme.secondaryText, size: 14)
                            .fontWeight(tab == item ? .semibold : .regular)
                        Rectangle()
                            .fill(tab == item ? Theme.accent : .clear)
                            .frame(height: 2.5)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private func row(_ experience: Experience, rank: Int?, meta: String) -> some View {
        ExperienceListRow(experience: experience, rank: rank, meta: meta)
    }

    /// Photo experiences and verified check-ins together, newest first.
    private enum AllItem: Identifiable {
        case photos(Experience)
        case verified(VerifiedExperience)

        var id: String {
            switch self {
            case .photos(let experience): experience.id
            case .verified(let verified): "verified-\(verified.id)"
            }
        }

        var date: Date {
            switch self {
            case .photos(let experience): experience.start
            case .verified(let verified): verified.date
            }
        }
    }

    private func allItems(_ experiences: [Experience]) -> [AllItem] {
        (experiences.map(AllItem.photos) + model.earn.verified.map(AllItem.verified)).sorted { $0.date > $1.date }
    }

    private func verifiedRow(_ verified: VerifiedExperience) -> some View {
        NavigationLink {
            VerifiedExperienceView(verified: verified, store: model.earn)
        } label: {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    VerifiedBadge()
                    Text(verified.title)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text("\(verified.place)  ·  \(verified.category.rawValue)  ·  \(verified.date.monthYear)")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Group {
                    if let photo = model.earn.photo(for: verified) {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        OfferBanner(category: verified.category, height: 72)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.vertical, 18)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

}

/// Numbered serif rank (Highlights only), title, meta line, and one rounded thumbnail. Opens the experience.
struct ExperienceListRow: View {
    let experience: Experience
    let rank: Int?
    let meta: String

    var body: some View {
        NavigationLink {
            ExperienceDetailView(experience: experience)
        } label: {
            HStack(spacing: 18) {
                if let rank {
                    Text(String(format: "%02d", rank))
                        .font(Theme.serif(36, weight: .light))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 52, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(experience.title)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(meta)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let id = experience.heroID {
                    Thumbnail(id: id, pointSide: 72)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.vertical, 18)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }
}

/// Profile → Places row: cover photo, metro name, country, and experience count.
struct PlaceRow: View {
    let group: PlaceGroup

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let cover = group.coverID {
                    Thumbnail(id: cover, pointSide: 72)
                } else {
                    Theme.fill
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if let code = group.countryCode {
                    Text(PlaceLookup.countryName(code))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            Text("\(group.experiences.count)")
                .font(Theme.serif(30, weight: .light))
                .foregroundStyle(Theme.text)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(group.experiences.count) experiences")
    }
}

/// One metro area's experiences, newest first.
struct PlaceExperiencesView: View {
    let group: PlaceGroup

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(group.name)
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)
                Text([group.countryCode.map { PlaceLookup.countryName($0) },
                      group.experiences.count == 1 ? "1 experience" : "\(group.experiences.count) experiences"]
                    .compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                ForEach(group.experiences) { experience in
                    ExperienceListRow(experience: experience, rank: nil,
                                      meta: "\(experience.place)  ·  \(experience.category.rawValue)  ·  \(experience.start.monthYear)")
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .avidaChrome()
    }
}
