import SwiftUI

/// Hero photo, category, title, place and dates, photo row, numbered stops, then every photo.
struct ExperienceDetailView: View {
    let experience: Experience

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let hero = experience.heroID {
                    Thumbnail(id: hero, pointSide: 420)
                        .frame(height: 260)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 8)
                }

                EyebrowText(experience.category.rawValue, color: Theme.accent, size: 13)
                    .padding(.top, 24)
                Text(experience.title)
                    .lineLimit(2)
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)

                HStack(spacing: 14) {
                    Label(placeLine, systemImage: "mappin.and.ellipse")
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 20)
                    Label(Experiences.durationText(from: experience.start, to: experience.end), systemImage: "clock")
                }
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 12)
                Text(dateLine)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 6)

                HStack(spacing: 6) {
                    ForEach(experience.coverIDs, id: \.self) { id in
                        Thumbnail(id: id, pointSide: 140)
                            .frame(maxWidth: .infinity)
                            .frame(height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 22)

                divider.padding(.top, 28)

                Text(experience.moments.count == 1 ? "1 stop in \(experience.place)" : "\(experience.moments.count) stops in \(experience.place)")
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 24)
                    .padding(.bottom, 12)

                ForEach(Array(experience.moments.enumerated()), id: \.element.id) { index, moment in
                    StopRow(number: index + 1, moment: moment,
                            isLast: index == experience.moments.count - 1,
                            showsDate: experience.kind == .trip)
                }

                divider.padding(.top, 20)

                HStack(alignment: .firstTextBaseline) {
                    Text("All photos")
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(experience.photoCount)")
                        .font(Theme.serif(22))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 24)
                .padding(.bottom, 14)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(experience.photoIDs, id: \.self) { id in
                        Thumbnail(id: id, pointSide: 120)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .avidaChrome()
    }

    private var divider: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }

    private var placeLine: String {
        guard let code = experience.countryCode else { return experience.place }
        return "\(experience.place), \(PlaceLookup.countryName(code))"
    }

    private var dateLine: String {
        let start = experience.start.formatted(date: .abbreviated, time: .omitted)
        let end = experience.end.formatted(date: .abbreviated, time: .omitted)
        return start == end ? start : "\(start) – \(end)"
    }
}

/// A numbered stop: terracotta circle on a connecting line, round photo, name, duration and photo count.
private struct StopRow: View {
    let number: Int
    let moment: Moment
    let isLast: Bool
    let showsDate: Bool

    var body: some View {
        NavigationLink {
            MomentPhotosView(moment: moment, title: name)
                .background(Theme.background)
        } label: {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 0) {
                    Text("\(number)")
                        .font(Theme.serif(17, weight: .medium))
                        .foregroundStyle(Theme.background)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent, in: Circle())
                    if !isLast {
                        Rectangle()
                            .fill(Theme.accent.opacity(0.6))
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(.top, 15)

                if let id = moment.representativeIDs.middle {
                    Thumbnail(id: id, pointSide: 64)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    if let detail = moment.landmark?.description, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(metaLine)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .padding(.bottom, isLast ? 0 : 8)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var name: String {
        moment.landmark?.name ?? moment.city?.name ?? "Somewhere"
    }

    private var metaLine: String {
        var parts = [Experiences.durationText(from: moment.start, to: moment.end)]
        parts.append(moment.photoIDs.count == 1 ? "1 photo" : "\(moment.photoIDs.count) photos")
        if showsDate { parts.append(moment.start.formatted(.dateTime.month(.abbreviated).day())) }
        return parts.joined(separator: "  ·  ")
    }
}

private extension Array {
    var middle: Element? { isEmpty ? nil : self[count / 2] }
}
