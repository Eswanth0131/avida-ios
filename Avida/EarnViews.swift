import SwiftUI
import CoreLocation

// MARK: Shared pieces

extension ExperienceCategory {
    var symbol: String {
        switch self {
        case .nature: "leaf"
        case .city: "building.2"
        case .culinary: "fork.knife"
        case .culture: "building.columns"
        case .coast: "water.waves"
        case .nightlife: "moon.stars"
        }
    }

    /// Two-stop gradient used on offer cards in place of photos.
    var gradient: [Color] {
        switch self {
        case .nature: [Color(hex: 0x7C9A6B), Color(hex: 0x2F4A35)]
        case .city: [Color(hex: 0x6B7684), Color(hex: 0x262B33)]
        case .culinary: [Color(hex: 0xD9A05B), Color(hex: 0x8A4B1C)]
        case .culture: [Color(hex: 0xC9694A), Color(hex: 0x6E2716)]
        case .coast: [Color(hex: 0x5E9DBA), Color(hex: 0x1F4659)]
        case .nightlife: [Color(hex: 0x6C5A92), Color(hex: 0x1E1730)]
        }
    }
}

/// Gradient panel with a category icon, standing in for photos on offers.
struct OfferBanner: View {
    let category: ExperienceCategory
    var height: CGFloat = 150

    var body: some View {
        LinearGradient(colors: category.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle().fill(.white.opacity(0.08)).frame(width: height * 1.1).offset(x: height * 0.3, y: -height * 0.35)
            }
            .overlay(alignment: .bottomLeading) {
                Circle().fill(.white.opacity(0.06)).frame(width: height * 0.8).offset(x: -height * 0.25, y: height * 0.35)
            }
            .overlay {
                Image(systemName: category.symbol)
                    .font(.system(size: height * 0.32, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.photoCorner + 2))
            .accessibilityHidden(true)
    }
}

/// Partner name as text, with the "Illustrative partner" label. No logos.
struct PartnerName: View {
    let name: String
    var size: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            Text("Illustrative partner")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

struct VerifiedBadge: View {
    var body: some View {
        Label("Verified", systemImage: "checkmark.seal.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.accent.opacity(0.1), in: Capsule())
    }
}

private func distanceText(_ meters: Double) -> String {
    Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
}

// MARK: Earn list

/// A photo cropped from the design mockups (Assets.xcassets/Earn), or the category gradient when there's none.
struct OfferImage: View {
    let name: String?
    let category: ExperienceCategory
    var height: CGFloat = 150

    var body: some View {
        if let name {
            Color.clear
                .overlay { Image(name).resizable().scaledToFill() }
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)
        } else {
            OfferBanner(category: category, height: height)
        }
    }
}

/// Wide cover plus two tiles, like the mockups' photo rows. Falls back to one gradient panel.
struct OfferPhotoRow: View {
    let offer: Offer
    var height: CGFloat = 120

    var body: some View {
        let images = offer.images ?? []
        if images.isEmpty {
            OfferBanner(category: offer.category, height: height)
        } else {
            HStack(spacing: 6) {
                ForEach(Array(images.prefix(3).enumerated()), id: \.offset) { index, name in
                    OfferImage(name: name, category: offer.category, height: height)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(index == 0 ? 1 : 0)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(height: height)
        }
    }
}

/// "Add to List" / "Added ✓".
struct AddToListButton: View {
    let isAdded: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isAdded ? "Added ✓" : "Add to List")
                .font(.system(size: compact ? 15 : 17, weight: .semibold))
                .foregroundStyle(isAdded ? Theme.accent : Theme.background)
                .padding(.horizontal, compact ? 16 : 0)
                .frame(maxWidth: compact ? nil : .infinity)
                .frame(height: compact ? 36 : 54)
                .background(isAdded ? Theme.accent.opacity(0.12) : Theme.text,
                            in: RoundedRectangle(cornerRadius: compact ? 18 : 14))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isAdded)
        .accessibilityLabel(isAdded ? "Added to List. Double tap to remove." : "Add to List")
    }
}

struct EarnView: View {
    let store: EarnStore

    private let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading),
                           GridItem(.flexible(), alignment: .leading)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Wordmark(size: 22)
                    .padding(.top, 8)

                Text("Earn")
                    .font(Theme.display(52))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 28)
                Text("Free experiences. Real rewards.")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 2)

                Text("Our partners")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 32)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(partners, id: \.self) { partner in
                        Text(partner)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.vertical, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }

                ForEach(store.offers) { offer in
                    OfferCard(offer: offer, store: store)
                }

                Text("Partner brands shown are illustrative.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// In catalog order, each once.
    private var partners: [String] {
        var seen = Set<String>()
        return store.offers.map(\.partner).filter { seen.insert($0).inserted }
    }
}

private struct OfferCard: View {
    let offer: Offer
    let store: EarnStore

    var body: some View {
        let status = store.status(offer)
        NavigationLink {
            OfferDetailView(offer: offer, store: store)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    if status == .verified { VerifiedBadge() } else { EyebrowText("Free", size: 13) }
                    Text(offer.title)
                        .lineLimit(2)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 14) {
                    Label(offer.place, systemImage: "mappin.and.ellipse")
                    Label(offer.duration, systemImage: "clock")
                    Label(offer.category.rawValue, systemImage: offer.category.symbol)
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                OfferPhotoRow(offer: offer)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(offer.partner)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(offer.rewardText)
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer(minLength: 8)
                    if status != .verified {
                        AddToListButton(isAdded: status == .added, compact: true) { store.toggleList(offer) }
                    }
                }
            }
            .padding(.vertical, 26)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: Offer detail

struct OfferDetailView: View {
    let offer: Offer
    let store: EarnStore

    var body: some View {
        let status = store.status(offer)
        let images = offer.images ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OfferImage(name: images.first, category: offer.category, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.top, 8)

                HStack {
                    EyebrowText(offer.category.rawValue, color: Theme.accent, size: 13)
                    Spacer()
                    if status == .verified { VerifiedBadge() }
                }
                .padding(.top, 24)
                Text(offer.title)
                    .lineLimit(2)
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)
                HStack(spacing: 14) {
                    Label(offer.place, systemImage: "mappin.and.ellipse")
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 20)
                    Label(offer.duration, systemImage: "clock")
                }
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 12)

                if images.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(images.dropFirst().prefix(2), id: \.self) { name in
                            OfferImage(name: name, category: offer.category, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.top, 20)
                }

                Text(offer.description)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
                    .padding(.top, 20)

                Rectangle().fill(Theme.divider).frame(height: 1).padding(.top, 24)

                Text("\(offer.stops.count) stops")
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                ForEach(Array(offer.stops.enumerated()), id: \.offset) { index, stop in
                    OfferStopRow(number: index + 1, stop: stop, isLast: index == offer.stops.count - 1)
                }

                Rectangle().fill(Theme.divider).frame(height: 1).padding(.top, 20)

                EyebrowText("Your reward", size: 12)
                    .padding(.top, 20)
                HStack(spacing: 18) {
                    PartnerName(name: offer.partner)
                        .frame(width: 120, alignment: .leading)
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 44)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("+\(offer.rewardAmount.formatted())")
                            .font(Theme.serif(30))
                        Text(offer.rewardUnit)
                            .font(.system(size: 19, weight: .semibold))
                            .lineLimit(2)
                    }
                    .foregroundStyle(Theme.text)
                }
                .padding(.vertical, 14)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if status == .verified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    AddToListButton(isAdded: status == .added) { store.toggleList(offer) }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 12)
            .background(Theme.background)
        }
        .avidaChrome()
    }
}

/// Numbered stop on a connecting line. Used by Earn offers and Connect experiences.
struct OfferStopRow: View {
    let number: Int
    let stop: Offer.Stop
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 0) {
                Text("\(number)")
                    .font(Theme.serif(17, weight: .medium))
                    .foregroundStyle(Theme.background)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: Circle())
                if !isLast {
                    Rectangle().fill(Theme.accent.opacity(0.6)).frame(width: 1.5).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let duration = stop.duration {
                    Text(duration)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, isLast ? 0 : 22)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Check-in

/// Location check → camera → verified. Too far shows the distance and doesn't verify.
/// Hidden from the UI since Step 7a (no verification for now); kept so it can come back.
struct CheckInView: View {
    let offer: Offer
    let store: EarnStore

    enum Phase {
        case locating
        case notPlaced
        case failed(String)
        case tooFar(distance: Double, radius: Double)
        case inaccurate(accuracy: Double)
        case ready(location: Coordinate, distance: Double)
        case verified(VerifiedExperience)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .locating
    @State private var showCamera = false
    @State private var locator = LocationFetcher()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Wordmark(size: 18)
                Spacer()
                Button("Close") { dismiss() }
                    .foregroundStyle(Theme.text)
            }
            .padding(.top, 20)

            switch phase {
            case .verified(let verified):
                VerifiedSuccessView(verified: verified, photo: store.photo(for: verified)) { dismiss() }
            default:
                checkInBody
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .background(Theme.background.ignoresSafeArea())
        .task { await locate() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                finish(with: image)
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var checkInBody: some View {
        EyebrowText("Check in", color: Theme.accent, size: 13).padding(.top, 40)
        Text(offer.title)
            .lineLimit(2)
            .font(Theme.display(34))
            .foregroundStyle(Theme.text)
            .padding(.top, 8)
        Spacer()

        Group {
            switch phase {
            case .locating:
                status("location.circle", "Finding your location…", nil)
            case .notPlaced:
                status("mappin.slash", "Demo offer not placed",
                       "Open Profile → Developer and tap “Place demo offer at my current location”.")
            case .failed(let message):
                status("exclamationmark.triangle", "Couldn't check in", message)
            case .tooFar(let distance, let radius):
                status("location.slash", "You're \(distanceText(distance)) away",
                       "Get within \(distanceText(radius)) of \(offer.stops.first?.name ?? offer.place) to check in. Not verified.")
            case .inaccurate(let accuracy):
                status("location.magnifyingglass", "Location too rough",
                       "Your location is only accurate to about \(distanceText(accuracy)). Step outside or wait a moment, then try again.")
            case .ready(_, let distance):
                status("checkmark.circle", "You're here",
                       "\(distanceText(distance)) from the check-in point. Take one photo to verify. It stays in Avida, not your photo library.")
            case .verified:
                EmptyView()
            }
        }
        Spacer()

        switch phase {
        case .ready:
            if CameraPicker.isAvailable {
                Button { showCamera = true } label: { Label("Take check-in photo", systemImage: "camera") }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Text("This device has no camera, so it can't verify.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        case .tooFar, .inaccurate, .failed:
            Button { Task { await locate() } } label: { Label("Try again", systemImage: "arrow.clockwise") }
                .buttonStyle(PrimaryButtonStyle())
        default:
            EmptyView()
        }
    }

    private func status(_ symbol: String, _ title: String, _ detail: String?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func locate() async {
        guard let target = store.location(offer) else {
            phase = .notPlaced
            return
        }
        phase = .locating
        do {
            let location = try await locator.currentLocation()
            let user = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            switch EarnLogic.checkIn(at: user, accuracyMeters: location.horizontalAccuracy, target: target, radiusMeters: offer.radiusMeters) {
            case .withinRadius(let distance):
                phase = .ready(location: user, distance: distance)
                if CameraPicker.isAvailable { showCamera = true }
            case .tooFar(let distance, let radius):
                phase = .tooFar(distance: distance, radius: radius)
            case .inaccurate(let accuracy):
                phase = .inaccurate(accuracy: accuracy)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func finish(with image: UIImage) {
        guard case .ready(let location, let distance) = phase else { return }
        do {
            if let verified = try store.completeCheckIn(offer, photo: image, at: location, distanceMeters: distance) {
                phase = .verified(verified)
            } else {
                phase = .failed("This experience is already verified.")
            }
        } catch {
            phase = .failed("Couldn't save the check-in photo.")
        }
    }
}

private struct VerifiedSuccessView: View {
    let verified: VerifiedExperience
    let photo: UIImage?
    let onDone: () -> Void

    var body: some View {
        Spacer()
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text("Verified")
                .font(Theme.display(40))
                .foregroundStyle(Theme.text)
            Text(verified.rewardText)
                .font(Theme.serif(28))
                .foregroundStyle(Theme.text)
            Text("from \(verified.partner) · Illustrative partner")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 220, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.photoCorner))
                    .padding(.top, 8)
            }
            Text("\(verified.title)\n\(verified.place) · \(verified.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        Spacer()
        Button("Done", action: onDone)
            .buttonStyle(PrimaryButtonStyle())
    }
}

// MARK: My rewards

struct MyRewardsView: View {
    let store: EarnStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("My rewards")
                    .font(Theme.display(44))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                if store.balances.isEmpty {
                    Text("No rewards yet. Save an offer in Earn, then check in when you're there.")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.vertical, 20)
                }
                ForEach(store.balances, id: \.self) { balance in
                    HStack(spacing: 16) {
                        PartnerName(name: balance.partner, size: 14)
                            .frame(width: 110, alignment: .leading)
                        Text(balance.amount.formatted())
                            .font(Theme.display(30))
                            .foregroundStyle(Theme.text)
                        Text(balance.unit)
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                    }
                    .padding(.vertical, 22)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
                }

                Text("Verified experiences")
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 36)
                    .padding(.bottom, 8)
                if store.verified.isEmpty {
                    Text("Your verified check-ins will appear here.")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.vertical, 12)
                }
                ForEach(store.verified) { verified in
                    NavigationLink {
                        VerifiedExperienceView(verified: verified, store: store)
                    } label: {
                        VerifiedRow(verified: verified, photo: store.photo(for: verified))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .avidaChrome()
    }
}

private struct VerifiedRow: View {
    let verified: VerifiedExperience
    let photo: UIImage?

    var body: some View {
        HStack(spacing: 18) {
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    OfferBanner(category: verified.category, height: 96)
                }
            }
            .frame(width: 120, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: Theme.photoCorner))

            VStack(alignment: .leading, spacing: 5) {
                Text(verified.title)
                    .lineLimit(2)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Text(verified.rewardText)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                Text(verified.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText.opacity(0.8))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

/// Photo, title, reward, place and date of one verified check-in.
struct VerifiedExperienceView: View {
    let verified: VerifiedExperience
    let store: EarnStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let photo = store.photo(for: verified) {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        OfferBanner(category: verified.category, height: 300)
                    }
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.top, 8)

                HStack {
                    EyebrowText(verified.category.rawValue, color: Theme.accent, size: 13)
                    Spacer()
                    VerifiedBadge()
                }
                .padding(.top, 24)
                Text(verified.title)
                    .lineLimit(2)
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)
                HStack(spacing: 14) {
                    Label(verified.place, systemImage: "mappin.and.ellipse")
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 20)
                    Label(verified.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                }
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 12)

                HStack(spacing: 18) {
                    PartnerName(name: verified.partner)
                        .frame(width: 120, alignment: .leading)
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 44)
                    Text(verified.rewardText)
                        .font(Theme.serif(26))
                        .foregroundStyle(Theme.text)
                }
                .padding(.vertical, 20)
                .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
                .padding(.top, 24)

                Text("Checked in \(distanceText(verified.distanceMeters)) from the check-in point. Verified on this iPhone.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .avidaChrome()
    }
}
