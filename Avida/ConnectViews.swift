import SwiftUI

/// Connect: friends as round faces (stories style); the selected friend's Experience Profile underneath.
struct ConnectView: View {
    let store: EarnStore
    var friends: [ConnectFriend] = ConnectCatalog.bundled

    @State private var selectedID: String?

    private var selected: ConnectFriend? {
        friends.first { $0.id == selectedID } ?? friends.first
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Wordmark(size: 22)
                    .padding(.top, 8)
                Text("Connect")
                    .font(Theme.display(52))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 28)
                Text("Follow inspiring people and discover new experiences.")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(friends) { friend in
                            FriendBubble(friend: friend, isSelected: friend.id == selected?.id) {
                                withAnimation(.snappy) { selectedID = friend.id }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.top, 24)

                Rectangle().fill(Theme.divider).frame(height: 1).padding(.top, 20)

                if let friend = selected {
                    FriendProfile(friend: friend, store: store)
                        .id(friend.id)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Round face with the name underneath. The selected friend gets a terracotta ring.
private struct FriendBubble: View {
    let friend: ConnectFriend
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                FriendFace(friend: friend, size: 68)
                    .padding(4)
                    .overlay(Circle().stroke(isSelected ? Theme.accent : Theme.divider, lineWidth: isSelected ? 2.5 : 1))
                Text(friend.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(friend.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FriendFace: View {
    let friend: ConnectFriend
    let size: CGFloat

    var body: some View {
        Image(friend.face)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// Name, "N experiences · N countries", and numbered highlights styled like our Profile.
private struct FriendProfile: View {
    let friend: ConnectFriend
    let store: EarnStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                FriendFace(friend: friend, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(friend.name)
                        .font(Theme.display(34))
                        .foregroundStyle(Theme.text)
                    EyebrowText("\(friend.experienceCount) experiences · \(friend.countryCount) countries", color: Theme.text, size: 13)
                    Label(friend.home, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 10) {
                EyebrowText("Highlights", color: Theme.text, size: 14)
                    .fontWeight(.semibold)
                Rectangle().fill(Theme.accent).frame(width: 92, height: 2.5)
            }
            .padding(.top, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }

            ForEach(Array(friend.experiences.enumerated()), id: \.element.id) { index, experience in
                NavigationLink {
                    ConnectExperienceDetailView(friend: friend, experience: experience, store: store)
                } label: {
                    HighlightRow(rank: index + 1, experience: experience)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HighlightRow: View {
    let rank: Int
    let experience: ConnectExperience

    var body: some View {
        HStack(spacing: 18) {
            Text(String(format: "%02d", rank))
                .font(Theme.serif(36, weight: .light))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(experience.title)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text("\(experience.place)  ·  \(experience.category.rawValue)  ·  \(String(experience.year))")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            OfferImage(name: experience.image, category: experience.category, height: 72)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

/// Hero photo, title, place, numbered stops, and Add to List (saved with source Connect, "From {friend}").
struct ConnectExperienceDetailView: View {
    let friend: ConnectFriend
    let experience: ConnectExperience
    let store: EarnStore

    var body: some View {
        let item = ListItem.connect(experience, from: friend, addedAt: .now)
        let isAdded = store.isInList(item.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OfferImage(name: experience.image, category: experience.category, height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.top, 8)

                EyebrowText(experience.category.rawValue, color: Theme.accent, size: 13)
                    .padding(.top, 24)
                Text(experience.title)
                    .lineLimit(2)
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)
                HStack(spacing: 14) {
                    Label("\(experience.place), \(experience.country)", systemImage: "mappin.and.ellipse")
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 20)
                    Label(String(experience.year), systemImage: "calendar")
                }
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 12)

                HStack(spacing: 10) {
                    FriendFace(friend: friend, size: 28)
                    Text("From \(friend.name)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                .padding(.top, 16)

                Text(experience.description)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
                    .padding(.top, 16)

                Rectangle().fill(Theme.divider).frame(height: 1).padding(.top, 24)

                Text("\(experience.stops.count) stops")
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                ForEach(Array(experience.stops.enumerated()), id: \.offset) { index, stop in
                    OfferStopRow(number: index + 1, stop: stop, isLast: index == experience.stops.count - 1)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            AddToListButton(isAdded: isAdded) { store.toggleList(item) }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 12)
                .background(Theme.background)
        }
        .avidaChrome()
    }
}
